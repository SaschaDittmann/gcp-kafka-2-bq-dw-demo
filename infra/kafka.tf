# =============================================================================
# Google Managed Service for Apache Kafka: Cluster & Topics
# =============================================================================
# Provisions a Managed Kafka cluster with:
# - Minimum 3 vCPU / 3 GiB for demo (smallest available)
# - VPC connectivity via the CDC pipeline subnet
# - IAM authentication (SASL/OAUTHBEARER, no static credentials)
# - 11 topics matching Debezium CDC naming: cdc.public.<table>
#
# Note: Cluster provisioning takes 15–30 minutes.
# =============================================================================

# -----------------------------------------------------------------------------
# Managed Kafka Cluster
# -----------------------------------------------------------------------------

resource "google_managed_kafka_cluster" "cluster" {
  provider   = google-beta
  project    = var.project_id
  cluster_id = "${var.name_prefix}-kafka"
  location   = var.region

  capacity_config {
    vcpu_count   = 3           # Minimum supported vCPU count
    memory_bytes = 3221225472  # 3 GiB (minimum: 1 GiB per vCPU)
  }

  gcp_config {
    access_config {
      network_configs {
        subnet = google_compute_subnetwork.subnet.id
      }
    }
  }

  rebalance_config {
    mode = "AUTO_REBALANCE_ON_SCALE_UP"
  }

  labels = local.common_labels

  timeouts {
    create = "2h"
    delete = "1h"
  }

  depends_on = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# Kafka Topics — one per Chinook table
# -----------------------------------------------------------------------------
# Debezium naming convention: <topic.prefix>.<schema>.<table>
# With topic.prefix=cdc and schema=public, topics are:
#   cdc.public.customer, cdc.public.invoice, etc.
# -----------------------------------------------------------------------------

locals {
  chinook_tables = [
    "customer",
    "employee",
    "artist",
    "album",
    "track",
    "genre",
    "media_type",
    "invoice",
    "invoice_line",
    "playlist",
    "playlist_track",
  ]

  # Build topic map: table_name => full topic ID
  chinook_topics = {
    for table in local.chinook_tables :
    table => "cdc.public.${table}"
  }
}

resource "google_managed_kafka_topic" "chinook" {
  for_each = local.chinook_topics

  provider           = google-beta
  project            = var.project_id
  cluster            = google_managed_kafka_cluster.cluster.cluster_id
  location           = var.region
  topic_id           = each.value
  partition_count    = 1  # Single partition for demo (low throughput)
  replication_factor = 3  # 3 replicas across availability zones

  configs = {
    "cleanup.policy" = "delete"
    "retention.ms"   = "604800000" # 7 days
  }
}

