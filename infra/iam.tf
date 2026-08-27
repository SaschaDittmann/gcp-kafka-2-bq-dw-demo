# =============================================================================
# IAM: Service Accounts & Role Bindings
# =============================================================================
# Defines the Kafka Connect service account and assigns the minimum required
# IAM roles for CDC ingestion (Kafka client, Cloud SQL client, BigQuery writer,
# Artifact Registry reader).
#
# Uses google_project_iam_member (non-authoritative) to avoid overwriting
# existing role assignments in the project.
# =============================================================================

# -----------------------------------------------------------------------------
# Service Account for Kafka Connect (Cloud Run)
# This identity is used by the Kafka Connect container running on Cloud Run
# to access Managed Kafka, Cloud SQL, BigQuery, and Artifact Registry.
# -----------------------------------------------------------------------------

resource "google_service_account" "kafka_connect" {
  account_id   = "${var.name_prefix}-kafka-connect"
  display_name = "Kafka Connect CDC Pipeline"
  description  = "Service account for Kafka Connect on Cloud Run — CDC ingestion and BigQuery sink"
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
    "roles/artifactregistry.reader",   # Pull container images from Artifact Registry
  ]
}

resource "google_project_iam_member" "kafka_connect_roles" {
  for_each = toset(local.kafka_connect_roles)
  project  = var.project_id
  role     = each.key
  member   = google_service_account.kafka_connect.member
}
