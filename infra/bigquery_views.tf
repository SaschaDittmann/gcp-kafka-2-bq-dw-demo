# =============================================================================
# BigQuery Views — Silver (on Bronze) + Gold (current-state)
# =============================================================================
# Views are defined as SQL files in transform/ and loaded via file().
# Terraform manages the view lifecycle — no manual SQL deployment needed.
#
# SQL files:
#   transform/silver/views/*.sql — Silver views on Bronze
#   transform/gold/views/*.sql   — Gold current-state views
# =============================================================================

locals {
  transform_dir = "${path.module}/../transform"

  # Auto-discover view SQL files from subfolders.
  # The key becomes the table_id (filename without .sql extension).
  silver_view_files = {
    for f in fileset("${local.transform_dir}/silver/views", "*.sql") :
    trimsuffix(f, ".sql") => f
  }

  gold_view_files = {
    for f in fileset("${local.transform_dir}/gold/views", "*.sql") :
    trimsuffix(f, ".sql") => f
  }
}

# -----------------------------------------------------------------------------
# Silver Views — Reference/Lookup Tables (read from Bronze)
# -----------------------------------------------------------------------------
# These tables change rarely. Instead of CQs, views with QUALIFY ROW_NUMBER()
# provide current-state dedup on read.
# -----------------------------------------------------------------------------

resource "google_bigquery_table" "silver_view" {
  for_each = local.silver_view_files

  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = each.key
  description         = "Current-state ${each.key} records (view on Bronze)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = replace(file("${local.transform_dir}/silver/views/${each.value}"), "$${PROJECT_ID}", var.project_id)
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.bronze]
}

# -----------------------------------------------------------------------------
# Gold Views — Current-State Access to SCD2 Dimensions + Enriched Facts
# -----------------------------------------------------------------------------
# These views make it easy to query the latest active dimension record
# and facts with resolved dimension names.
# -----------------------------------------------------------------------------

resource "google_bigquery_table" "gold_view" {
  for_each = local.gold_view_files

  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = each.key
  description         = "Gold current-state view: ${each.key}"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = replace(file("${local.transform_dir}/gold/views/${each.value}"), "$${PROJECT_ID}", var.project_id)
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.gold_dim_customer,
    google_bigquery_table.gold_dim_employee,
    google_bigquery_table.gold_dim_track,
    google_bigquery_table.gold_fct_invoice,
    google_bigquery_table.gold_fct_invoice_line,
  ]
}
