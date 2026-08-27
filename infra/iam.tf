# =============================================================================
# IAM: Service Accounts & Role Bindings
# =============================================================================
# Defines the Kafka Connect service account and assigns the minimum required
# IAM roles for CDC ingestion (Kafka client, Cloud SQL client, BigQuery writer,
# Cloud Storage writer).
#
# Uses google_project_iam_member (non-authoritative) to avoid overwriting
# existing role assignments in the project.
# =============================================================================

# -----------------------------------------------------------------------------
# Service Account for Kafka Connect (Managed)
# This identity is used by the Managed Kafka Connect cluster to access
# Cloud SQL, BigQuery, and Cloud Storage.
# -----------------------------------------------------------------------------

resource "google_service_account" "kafka_connect" {
  account_id   = "${var.name_prefix}-kafka-connect"
  display_name = "Kafka Connect CDC Pipeline"
  description  = "Service account for Managed Kafka Connect — CDC source, BigQuery sink, GCS archive"
  project      = var.project_id

  depends_on = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# IAM Role Bindings
# Each role is bound non-authoritatively via google_project_iam_member.
# -----------------------------------------------------------------------------

locals {
  kafka_connect_roles = [
    "roles/managedkafka.client",       # Publish/subscribe to Managed Kafka topics
    "roles/cloudsql.client",           # Connect to Cloud SQL PostgreSQL instance
    "roles/bigquery.dataEditor",       # Write records to BigQuery Bronze tables
    "roles/bigquery.jobUser",          # Run BigQuery load and query jobs
    "roles/storage.objectCreator",     # Write CDC archive files to GCS
  ]
}

resource "google_project_iam_member" "kafka_connect_roles" {
  for_each = toset(local.kafka_connect_roles)
  project  = var.project_id
  role     = each.key
  member   = google_service_account.kafka_connect.member
}
