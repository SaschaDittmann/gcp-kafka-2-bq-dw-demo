# =============================================================================
# BigQuery Silver Layer — Current-State Entity Tables (Persistent via CQ)
# =============================================================================
# These tables change frequently and are populated by Continuous Queries
# from Bronze. They serve as sources for Gold scheduled queries.
#
# Silver views (on Bronze) are defined in bigquery_views.tf.
# =============================================================================

# --- customer ---
resource "google_bigquery_table" "silver_customer" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "customer"
  description         = "Current-state customer records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "customer_id", type = "INTEGER", mode = "REQUIRED" },
    { name = "first_name", type = "STRING", mode = "NULLABLE" },
    { name = "last_name", type = "STRING", mode = "NULLABLE" },
    { name = "company", type = "STRING", mode = "NULLABLE" },
    { name = "address", type = "STRING", mode = "NULLABLE" },
    { name = "city", type = "STRING", mode = "NULLABLE" },
    { name = "state", type = "STRING", mode = "NULLABLE" },
    { name = "country", type = "STRING", mode = "NULLABLE" },
    { name = "postal_code", type = "STRING", mode = "NULLABLE" },
    { name = "email", type = "STRING", mode = "NULLABLE" },
    { name = "support_rep_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "is_deleted", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# --- employee ---
resource "google_bigquery_table" "silver_employee" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "employee"
  description         = "Current-state employee records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "employee_id", type = "INTEGER", mode = "REQUIRED" },
    { name = "last_name", type = "STRING", mode = "NULLABLE" },
    { name = "first_name", type = "STRING", mode = "NULLABLE" },
    { name = "title", type = "STRING", mode = "NULLABLE" },
    { name = "reports_to", type = "INTEGER", mode = "NULLABLE" },
    { name = "birth_date", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "hire_date", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "address", type = "STRING", mode = "NULLABLE" },
    { name = "city", type = "STRING", mode = "NULLABLE" },
    { name = "state", type = "STRING", mode = "NULLABLE" },
    { name = "country", type = "STRING", mode = "NULLABLE" },
    { name = "postal_code", type = "STRING", mode = "NULLABLE" },
    { name = "email", type = "STRING", mode = "NULLABLE" },
    { name = "is_deleted", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# --- track ---
resource "google_bigquery_table" "silver_track" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "track"
  description         = "Current-state track records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "track_id", type = "INTEGER", mode = "REQUIRED" },
    { name = "name", type = "STRING", mode = "NULLABLE" },
    { name = "album_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "media_type_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "genre_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "composer", type = "STRING", mode = "NULLABLE" },
    { name = "milliseconds", type = "INTEGER", mode = "NULLABLE" },
    { name = "bytes", type = "INTEGER", mode = "NULLABLE" },
    { name = "unit_price", type = "FLOAT", mode = "NULLABLE" },
    { name = "is_deleted", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# --- invoice ---
resource "google_bigquery_table" "silver_invoice" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "invoice"
  description         = "Current-state invoice records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "invoice_id", type = "INTEGER", mode = "REQUIRED" },
    { name = "customer_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "invoice_date", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "billing_address", type = "STRING", mode = "NULLABLE" },
    { name = "billing_city", type = "STRING", mode = "NULLABLE" },
    { name = "billing_state", type = "STRING", mode = "NULLABLE" },
    { name = "billing_country", type = "STRING", mode = "NULLABLE" },
    { name = "billing_postal_code", type = "STRING", mode = "NULLABLE" },
    { name = "total", type = "FLOAT", mode = "NULLABLE" },
    { name = "is_deleted", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# --- invoice_line ---
resource "google_bigquery_table" "silver_invoice_line" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "invoice_line"
  description         = "Current-state invoice line records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "invoice_line_id", type = "INTEGER", mode = "REQUIRED" },
    { name = "invoice_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "track_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "unit_price", type = "FLOAT", mode = "NULLABLE" },
    { name = "quantity", type = "INTEGER", mode = "NULLABLE" },
    { name = "is_deleted", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}
