# =============================================================================
# BigQuery Data Warehouse: Bronze, Silver & Gold Layers
# =============================================================================
# Three-layer medallion architecture for CDC data:
#
# Bronze  — Raw CDC events from Kafka (Debezium envelope format)
#            See: bigquery_bronze.tf
# Silver  — Current-state entity tables with soft-delete handling
#            See: bigquery_silver.tf (CQ tables), bigquery_views.tf (views)
# Gold    — Star schema: SCD Type 2 dimensions + point-in-time fact tables
#            See: bigquery_gold.tf (Iceberg tables + scheduled queries),
#                 bigquery_views.tf (current-state views)
# =============================================================================

# -----------------------------------------------------------------------------
# Datasets
# -----------------------------------------------------------------------------

resource "google_bigquery_dataset" "bronze" {
  dataset_id  = "bronze"
  location    = var.region
  description = "Raw CDC events from Kafka (Debezium envelope format)"
  labels      = local.common_labels

  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "silver" {
  dataset_id  = "silver"
  location    = var.region
  description = "Current-state entity tables with soft-delete handling"
  labels      = local.common_labels

  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "gold" {
  dataset_id  = "gold"
  location    = var.region
  description = "Star schema: SCD Type 2 dimensions and fact tables"
  labels      = local.common_labels

  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

# =============================================================================
# BigQuery Reservation — Enterprise Slots for Continuous Queries
# =============================================================================
# CQs require BigQuery Enterprise edition with slot reservations.
# Using autoscaling: no upfront commitment, billed per-second for slots used.
# =============================================================================

resource "google_bigquery_reservation" "default" {
  name          = "cdc-demo-reservation"
  project       = var.project_id
  location      = var.region
  slot_capacity = 0
  edition       = "ENTERPRISE"

  autoscale {
    max_slots = 100
  }
}

resource "google_bigquery_reservation_assignment" "default" {
  project     = var.project_id
  location    = var.region
  reservation = google_bigquery_reservation.default.id
  assignee    = "projects/${var.project_id}"
  job_type    = "CONTINUOUS"
}
