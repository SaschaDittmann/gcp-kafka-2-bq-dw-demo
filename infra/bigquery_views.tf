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

  # Split into dimension views (no cross-view deps) and fact views (depend on dim views)
  gold_dim_view_files = {
    for k, v in local.gold_view_files : k => v
    if startswith(k, "v_dim_")
  }
  gold_fct_view_files = {
    for k, v in local.gold_view_files : k => v
    if startswith(k, "v_fct_")
  }
}

# -----------------------------------------------------------------------------
# Silver Views — Reference/Lookup Tables (read from Bronze)
# -----------------------------------------------------------------------------
# Auto-discovered from transform/silver/views/*.sql
# These are simple views on Bronze tables for tables that don't need CQ
# processing (e.g., reference data like genres, media types).
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
# Gold Dimension Views — Current-State Access to SCD2 Dimensions
# -----------------------------------------------------------------------------
# Created first since fact views reference them.
# -----------------------------------------------------------------------------

resource "google_bigquery_table" "gold_dim_view" {
  for_each = local.gold_dim_view_files

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
  ]
}

# -----------------------------------------------------------------------------
# Gold Fact Views — Enriched Facts with Resolved Dimensions
# -----------------------------------------------------------------------------
# Depend on dimension views (v_dim_*) for JOIN resolution.
# -----------------------------------------------------------------------------

resource "google_bigquery_table" "gold_fct_view" {
  for_each = local.gold_fct_view_files

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
    google_bigquery_table.gold_dim_view,
    google_bigquery_table.gold_fct_invoice,
    google_bigquery_table.gold_fct_invoice_line,
  ]
}
