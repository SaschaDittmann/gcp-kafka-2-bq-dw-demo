# =============================================================================
# Managed Kafka Connect: Cluster + Connectors
# =============================================================================
# Fully managed Kafka Connect cluster with built-in connector plugins:
#
# 1. Source — Cloud SQL for PostgreSQL (Debezium-based CDC)
#    - Captures row-level changes via logical replication
#    - Publishes to cdc.public.<table> topics
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
# Secret Manager — replication password for CDC source connector
# Managed Kafka Connect requires passwords as Secret Manager references.
# -----------------------------------------------------------------------------

resource "google_secret_manager_secret" "db_repl_password" {
  secret_id = "${var.name_prefix}-db-repl-password"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_repl_password" {
  secret      = google_secret_manager_secret.db_repl_password.id
  secret_data = random_password.db_repl_password.result
}

# Grant the Kafka Connect SA access to read the secret
resource "google_secret_manager_secret_iam_member" "connect_secret_access" {
  secret_id = google_secret_manager_secret.db_repl_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.kafka_connect.member
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
    vcpu_count   = 3          # Minimum supported
    memory_bytes = 3221225472 # 3 GiB (1 GiB per vCPU)
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

# Wait for Cloud SQL IAM authentication to propagate.
# The managed_kafka_iam user is created moments before the connector
# tries to connect. Without this delay, IAM auth fails on fresh deployments.
resource "time_sleep" "iam_propagation" {
  depends_on      = [google_sql_user.managed_kafka_iam]
  create_duration = "60s"
}

resource "google_managed_kafka_connector" "cdc_source" {
  count           = var.source_connector_type == "managed" ? 1 : 0
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

    # Cloud SQL connection — uses Managed Kafka SA with IAM auth
    # The managed service connects as service-PROJECT_NUMBER@gcp-sa-managedkafka.iam
    # No database.hostname needed — driver.cloudSqlInstance handles routing
    "database.dbname"         = "chinook"
    "driver.cloudSqlInstance" = google_sql_database_instance.postgres.connection_name
    "driver.enableIamAuth"    = "true"
    "driver.ipTypes"          = "PRIVATE,PUBLIC"
    "driver.sslmode"          = "disable"

    # CDC configuration
    "topic.prefix"                = "cdc"
    "table.include.list"          = "public.*"
    "plugin.name"                 = "pgoutput"
    "slot.name"                   = "debezium_slot"
    "publication.name"            = "debezium_publication"
    "publication.autocreate.mode" = "disabled"
    "snapshot.mode"               = "initial"
    "decimal.handling.mode"       = "double"
    "time.precision.mode"         = "connect"

    # Serialization — match Console UI defaults
    # value.converter.schemas.enable=true embeds Debezium schema in each record,
    # which the BQ sink requires for proper table creation and type inference
    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "true"
  }

  # Workaround: GCP auto-sets task_restart_policy; provider bug causes
  # update_mask error when Terraform tries to reconcile it.
  lifecycle {
    ignore_changes = [task_restart_policy]
  }

  timeouts {
    create = "30m"
    delete = "10m"
  }

  depends_on = [
    time_sleep.iam_propagation,
    google_sql_database.chinook,
  ]
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
    "tasks.max"       = "3"

    # BigQuery destination
    "topics.regex"               = "cdc\\.public\\..*"
    "project"                    = var.project_id
    "defaultDataset"             = "bronze"
    "autoCreateTables"           = "true"
    "autoUpdateSchemas"          = "true"
    "sanitizeTopics"             = "true"
    "bigQueryPartitionDecorator" = "false"

    # Serialization — schemas.enable=true to match CDC source output
    # The source embeds Debezium schema in each record; the sink needs it
    # for proper BigQuery table creation and type inference
    "key.converter"                  = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "true"

    # SMTs: rename topics to match table names, drop PII, filter tombstones
    # cdc.public.album → album_raw (auto-created by connector)
    "transforms"                             = "renameTopics,dropSensitiveFields,filterTombstones"
    "transforms.renameTopics.type"           = "org.apache.kafka.connect.transforms.RegexRouter"
    "transforms.renameTopics.regex"          = "cdc\\.public\\.(.*)"
    "transforms.renameTopics.replacement"    = "$1_raw"
    "transforms.dropSensitiveFields.type"    = "org.apache.kafka.connect.transforms.ReplaceField$Value"
    "transforms.dropSensitiveFields.exclude" = "phone,fax"
    "transforms.filterTombstones.type"       = "org.apache.kafka.connect.transforms.Filter"
    "transforms.filterTombstones.predicate"  = "isTombstone"
    "predicates"                             = "isTombstone"
    "predicates.isTombstone.type"            = "org.apache.kafka.connect.transforms.predicates.RecordIsTombstone"
  }

  timeouts {
    create = "30m"
    delete = "10m"
  }

  # GCP auto-sets task_restart_policy; ignore it to avoid update_mask errors
  lifecycle {
    ignore_changes = [task_restart_policy]
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
    "connector.class" = "io.aiven.kafka.connect.gcs.GcsSinkConnector"
    "tasks.max"       = "3"

    # GCS destination
    "topics.regex"            = "cdc\\.public\\..*"
    "gcs.bucket.name"         = google_storage_bucket.cdc_archive.name
    "gcs.credentials.default" = "true"

    # Output format
    "format.output.type" = "jsonl"

    # Serialization — schemas.enable=true to match CDC source output
    "key.converter"                  = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "true"
  }

  timeouts {
    create = "30m"
    delete = "10m"
  }

  # GCP auto-sets task_restart_policy; ignore it to avoid update_mask errors
  lifecycle {
    ignore_changes = [task_restart_policy]
  }
}
