# =============================================================================
# IAM: Service Accounts & Role Bindings
# =============================================================================
# Defines the Kafka Connect service account and assigns the minimum required
# IAM roles for CDC ingestion (Kafka client, Cloud SQL client, BigQuery writer,
# Cloud Storage writer, Artifact Registry reader).
#
# Uses google_project_iam_member (non-authoritative) to avoid overwriting
# existing role assignments in the project.
# =============================================================================

# -----------------------------------------------------------------------------
# Service Account for Kafka Connect
# Used by both Managed Kafka Connect and Cloud Run Kafka Connect services
# to access Managed Kafka, Cloud SQL, BigQuery, GCS, and Artifact Registry.
# -----------------------------------------------------------------------------

resource "google_service_account" "kafka_connect" {
  account_id   = "${var.name_prefix}-kafka-connect"
  display_name = "Kafka Connect CDC Pipeline"
  description  = "Service account for Kafka Connect — CDC source, BigQuery sink, GCS archive"
  project      = var.project_id

  depends_on = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# IAM Role Bindings
# Each role is bound non-authoritatively via google_project_iam_member.
# -----------------------------------------------------------------------------

locals {
  kafka_connect_roles = [
    "roles/managedkafka.client",     # Publish/subscribe to Managed Kafka topics
    "roles/cloudsql.client",         # Connect to Cloud SQL PostgreSQL instance
    "roles/bigquery.dataEditor",     # Write records to BigQuery Bronze tables
    "roles/bigquery.jobUser",        # Run BigQuery load and query jobs
    "roles/storage.objectCreator",   # Write CDC archive files to GCS
    "roles/artifactregistry.reader", # Pull container images from Artifact Registry (Cloud Run)
  ]
}

resource "google_project_iam_member" "kafka_connect_roles" {
  for_each = toset(local.kafka_connect_roles)
  project  = var.project_id
  role     = each.key
  member   = google_service_account.kafka_connect.member
}

# -----------------------------------------------------------------------------
# Managed Kafka Service Agent — roles for ALL connectors
# The managed Connect cluster uses the Managed Kafka SA (not our custom SA)
# for all API calls: Cloud SQL source, BigQuery sink, and GCS archive sink.
# SA: service-PROJECT_NUMBER@gcp-sa-managedkafka.iam.gserviceaccount.com
# -----------------------------------------------------------------------------

locals {
  managed_kafka_sa = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-managedkafka.iam.gserviceaccount.com"

  managed_kafka_roles = [
    "roles/cloudsql.client",       # Connect to Cloud SQL (includes instances.get)
    "roles/cloudsql.instanceUser", # IAM database authentication
    "roles/cloudsql.viewer",       # connectSettings API (instances.get)
    "roles/bigquery.dataEditor",   # Write records to BigQuery Bronze tables
    "roles/bigquery.jobUser",      # Run BigQuery load and query jobs
    "roles/storage.objectAdmin",   # Write/overwrite CDC archive files in GCS
  ]
}

resource "google_project_iam_member" "managed_kafka_roles" {
  for_each = toset(local.managed_kafka_roles)
  project  = var.project_id
  role     = each.key
  member   = local.managed_kafka_sa
}

# Cloud SQL IAM database user for the Managed Kafka SA
resource "google_sql_user" "managed_kafka_iam" {
  name     = "service-${data.google_project.current.number}@gcp-sa-managedkafka.iam"
  instance = google_sql_database_instance.postgres.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  project  = var.project_id

  # The CDC connector grants this user object ownership in chinook.
  # Database must be destroyed first (dropping owned objects) before
  # this user can be deleted.
  depends_on = [
    google_sql_database.chinook,
  ]
}

# -----------------------------------------------------------------------------
# Cloud Build — Default Compute Engine SA needs storage access
# gcloud builds submit uses this SA to upload source to the _cloudbuild bucket
# and write the built image to Artifact Registry.
# Needed for future Cloud Run Kafka Connect deployment.
# -----------------------------------------------------------------------------

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_iam_member" "cloudbuild_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}
