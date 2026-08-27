# =============================================================================
# Managed Kafka Connect: Cluster + Connectors
# =============================================================================
# Fully managed Kafka Connect cluster with built-in connector plugins:
#
# 1. Source — Cloud SQL for PostgreSQL (Debezium-based CDC)
#    - Captures row-level changes via logical replication
#    - Publishes to chinook.public.<table> topics
#
# 2. Sink — BigQuery
#    - Writes CDC events to Bronze dataset tables
#    - SMTs: drop phone/fax fields, filter tombstones
#
# 3. Sink — Cloud Storage (GCS)
#    - Archives CDC events as JSON files in GCS
#    - Useful for replay, auditing, and data lake integration
#
# Note: Connect cluster provisioning takes ~15 minutes.
# =============================================================================

# -----------------------------------------------------------------------------
# GCS Bucket for long-term CDC archive
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "cdc_archive" {
  name                        = "${var.project_id}-cdc-archive"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = local.common_labels
}

# Grant the Kafka Connect SA write access to the CDC archive bucket
resource "google_storage_bucket_iam_member" "connect_gcs_writer" {
  bucket = google_storage_bucket.cdc_archive.name
  role   = "roles/storage.objectCreator"
  member = google_service_account.kafka_connect.member
}

# -----------------------------------------------------------------------------
# Managed Kafka Connect Cluster
# Minimum: 3 vCPUs, 3 GiB memory. Requires /22 subnet.
# -----------------------------------------------------------------------------

resource "google_managed_kafka_connect_cluster" "connect" {
  provider           = google-beta
  project            = var.project_id
  connect_cluster_id = "${var.name_prefix}-connect"
  location           = var.region
  kafka_cluster      = "projects/${var.project_id}/locations/${var.region}/clusters/${google_managed_kafka_cluster.cluster.cluster_id}"

  capacity_config {
    vcpu_count   = 3           # Minimum supported
    memory_bytes = 3221225472  # 3 GiB (1 GiB per vCPU)
  }

  gcp_config {
    access_config {
      network_configs {
        primary_subnet = google_compute_subnetwork.subnet.id
      }
    }
  }

  labels = local.common_labels

  timeouts {
    create = "1h"
    delete = "30m"
  }

  depends_on = [
    google_project_service.apis,
    google_managed_kafka_cluster.cluster,
  ]
}

# -----------------------------------------------------------------------------
# Source Connector — Cloud SQL for PostgreSQL (CDC)
# -----------------------------------------------------------------------------
# Uses the built-in Debezium-based Cloud SQL PostgreSQL source connector.
# Captures changes via logical replication (pgoutput plugin).
# -----------------------------------------------------------------------------

resource "google_managed_kafka_connector" "cdc_source" {
  provider        = google-beta
  project         = var.project_id
  connector_id    = "cdc-source"
  location        = var.region
  connect_cluster = google_managed_kafka_connect_cluster.connect.connect_cluster_id

  configs = {
    # Connector identity
    "name"            = "cdc-source"
    "connector.class" = "io.debezium.connector.postgresql.PostgresConnector"
    "tasks.max"       = "1"

    # Cloud SQL connection
    "database.hostname" = google_sql_database_instance.postgres.private_ip_address
    "database.port"     = "5432"
    "database.user"     = "replication_user"
    "database.password" = random_password.db_repl_password.result
    "database.dbname"   = "chinook"

    # CDC configuration
    "topic.prefix"                   = "chinook"
    "table.include.list"             = "public.*"
    "plugin.name"                    = "pgoutput"
    "slot.name"                      = "debezium_slot"
    "publication.name"               = "debezium_publication"
    "publication.autocreate.mode"    = "disabled"
    "database.server.name"           = "chinook"
    "snapshot.mode"                  = "initial"
    "decimal.handling.mode"          = "double"
    "time.precision.mode"            = "connect"

    # Serialization — schemaless JSON
    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "false"
  }

  timeouts {
    create = "30m"
    delete = "10m"
  }
}

# -----------------------------------------------------------------------------
# Sink Connector — BigQuery (Bronze layer)
# -----------------------------------------------------------------------------
# Writes CDC events to BigQuery Bronze dataset.
# SMTs: drop PII fields (phone/fax), filter tombstone records.
# -----------------------------------------------------------------------------

resource "google_managed_kafka_connector" "bigquery_sink" {
  provider        = google-beta
  project         = var.project_id
  connector_id    = "bigquery-sink"
  location        = var.region
  connect_cluster = google_managed_kafka_connect_cluster.connect.connect_cluster_id

  configs = {
    # Connector identity
    "name"            = "bigquery-sink"
    "connector.class" = "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector"
    "tasks.max"       = "1"

    # BigQuery destination
    "topics.regex"       = "chinook\\.public\\..*"
    "project"            = var.project_id
    "defaultDataset"     = "bronze"
    "autoCreateTables"   = "true"
    "autoUpdateSchemas"  = "true"

    # Serialization — schemaless JSON
    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "false"

    # SMTs: drop PII fields, filter tombstones
    "transforms"                                = "dropSensitiveFields,filterTombstones"
    "transforms.dropSensitiveFields.type"       = "org.apache.kafka.connect.transforms.ReplaceField$Value"
    "transforms.dropSensitiveFields.exclude"    = "phone,fax"
    "transforms.filterTombstones.type"          = "org.apache.kafka.connect.transforms.Filter"
    "transforms.filterTombstones.predicate"     = "isTombstone"
    "predicates"                                = "isTombstone"
    "predicates.isTombstone.type"               = "org.apache.kafka.connect.transforms.predicates.RecordIsTombstone"
  }

  timeouts {
    create = "30m"
    delete = "10m"
  }
}

# -----------------------------------------------------------------------------
# Sink Connector — Cloud Storage (CDC archive as JSON)
# -----------------------------------------------------------------------------
# Archives all CDC events as JSON files in GCS for replay, auditing,
# and data lake integration.
# -----------------------------------------------------------------------------

resource "google_managed_kafka_connector" "gcs_sink" {
  provider        = google-beta
  project         = var.project_id
  connector_id    = "gcs-sink"
  location        = var.region
  connect_cluster = google_managed_kafka_connect_cluster.connect.connect_cluster_id

  configs = {
    # Connector identity
    "name"            = "gcs-sink"
    "connector.class" = "com.google.cloud.kafka.connect.gcs.GcsSinkConnector"
    "tasks.max"       = "1"

    # GCS destination
    "topics.regex"            = "chinook\\.public\\..*"
    "gcs.bucket.name"         = google_storage_bucket.cdc_archive.name
    "gcs.credentials.default" = "true"

    # Output format
    "format.output.type"    = "jsonl"
    "file.compression.type" = "gzip"

    # Serialization — schemaless JSON
    "key.converter"                  = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "false"
  }

  timeouts {
    create = "30m"
    delete = "10m"
  }
}
