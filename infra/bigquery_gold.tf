# =============================================================================
# BigQuery Gold Layer — Star Schema (Managed Apache Iceberg Tables)
# =============================================================================
# Gold tables use BigQuery Managed Iceberg format, storing data as Parquet
# in a customer-owned GCS bucket. This enables interoperability with any
# engine that supports Apache Iceberg (Spark, Trino, Flink, etc.)
#
# Gold views (current-state) are defined in bigquery_views.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# Iceberg Storage Infrastructure
# -----------------------------------------------------------------------------

# --- GCS Bucket for Iceberg Data ---
resource "google_storage_bucket" "iceberg_data" {
  name          = "${var.project_id}-iceberg-gold"
  location      = var.region
  force_destroy = true
  labels        = local.common_labels

  uniform_bucket_level_access = true

  depends_on = [google_project_service.apis]
}

# --- BigQuery Connection for Cloud Storage Access ---
resource "google_bigquery_connection" "iceberg" {
  connection_id = "iceberg-gold-connection"
  location      = var.region
  description   = "Connection for Gold layer Managed Iceberg tables"

  cloud_resource {}

  depends_on = [google_project_service.apis]
}

# --- IAM: Grant BQ Connection SA access to the Iceberg bucket ---
resource "google_storage_bucket_iam_member" "iceberg_connection" {
  bucket = google_storage_bucket.iceberg_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_bigquery_connection.iceberg.cloud_resource[0].service_account_id}"
}

# -----------------------------------------------------------------------------
# Dimension Tables (SCD Type 2)
# -----------------------------------------------------------------------------

# --- dim_customer (SCD Type 2, Iceberg) ---
resource "google_bigquery_table" "gold_dim_customer" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "dim_customer"
  description         = "Customer dimension with SCD Type 2 history (Managed Iceberg)"
  deletion_protection = false
  labels              = local.common_labels

  biglake_configuration {
    connection_id = google_bigquery_connection.iceberg.name
    file_format   = "PARQUET"
    table_format  = "ICEBERG"
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/dim_customer/"
  }

  schema = jsonencode([
    { name = "surrogate_key", type = "STRING", mode = "REQUIRED", description = "Unique row key (UUID)" },
    { name = "natural_key", type = "INTEGER", mode = "REQUIRED", description = "customer_id from source" },
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
    { name = "valid_from", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_active", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# --- dim_track (SCD Type 2, denormalized, Iceberg) ---
resource "google_bigquery_table" "gold_dim_track" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "dim_track"
  description         = "Track dimension denormalized with album, artist, genre, media type (SCD2, Iceberg)"
  deletion_protection = false
  labels              = local.common_labels

  biglake_configuration {
    connection_id = google_bigquery_connection.iceberg.name
    file_format   = "PARQUET"
    table_format  = "ICEBERG"
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/dim_track/"
  }

  schema = jsonencode([
    { name = "surrogate_key", type = "STRING", mode = "REQUIRED" },
    { name = "natural_key", type = "INTEGER", mode = "REQUIRED", description = "track_id from source" },
    { name = "track_name", type = "STRING", mode = "NULLABLE" },
    { name = "album_title", type = "STRING", mode = "NULLABLE" },
    { name = "artist_name", type = "STRING", mode = "NULLABLE" },
    { name = "genre_name", type = "STRING", mode = "NULLABLE" },
    { name = "media_type_name", type = "STRING", mode = "NULLABLE" },
    { name = "composer", type = "STRING", mode = "NULLABLE" },
    { name = "milliseconds", type = "INTEGER", mode = "NULLABLE" },
    { name = "bytes", type = "INTEGER", mode = "NULLABLE" },
    { name = "unit_price", type = "FLOAT", mode = "NULLABLE" },
    { name = "valid_from", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_active", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# --- dim_employee (SCD Type 2, Iceberg) ---
resource "google_bigquery_table" "gold_dim_employee" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "dim_employee"
  description         = "Employee dimension with SCD Type 2 history (Managed Iceberg)"
  deletion_protection = false
  labels              = local.common_labels

  biglake_configuration {
    connection_id = google_bigquery_connection.iceberg.name
    file_format   = "PARQUET"
    table_format  = "ICEBERG"
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/dim_employee/"
  }

  schema = jsonencode([
    { name = "surrogate_key", type = "STRING", mode = "REQUIRED" },
    { name = "natural_key", type = "INTEGER", mode = "REQUIRED", description = "employee_id from source" },
    { name = "first_name", type = "STRING", mode = "NULLABLE" },
    { name = "last_name", type = "STRING", mode = "NULLABLE" },
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
    { name = "valid_from", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_active", type = "BOOLEAN", mode = "REQUIRED" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# -----------------------------------------------------------------------------
# Fact Tables
# -----------------------------------------------------------------------------

# --- fct_invoice (Iceberg) ---
resource "google_bigquery_table" "gold_fct_invoice" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "fct_invoice"
  description         = "Invoice fact table with surrogate key references (Managed Iceberg)"
  deletion_protection = false
  labels              = local.common_labels

  biglake_configuration {
    connection_id = google_bigquery_connection.iceberg.name
    file_format   = "PARQUET"
    table_format  = "ICEBERG"
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/fct_invoice/"
  }

  schema = jsonencode([
    { name = "invoice_id", type = "INTEGER", mode = "REQUIRED" },
    { name = "customer_key", type = "STRING", mode = "NULLABLE", description = "Surrogate key → dim_customer" },
    { name = "invoice_date", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "billing_address", type = "STRING", mode = "NULLABLE" },
    { name = "billing_city", type = "STRING", mode = "NULLABLE" },
    { name = "billing_state", type = "STRING", mode = "NULLABLE" },
    { name = "billing_country", type = "STRING", mode = "NULLABLE" },
    { name = "billing_postal_code", type = "STRING", mode = "NULLABLE" },
    { name = "total", type = "FLOAT", mode = "NULLABLE" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# --- fct_invoice_line (Iceberg) ---
resource "google_bigquery_table" "gold_fct_invoice_line" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "fct_invoice_line"
  description         = "Invoice line fact table with surrogate key references (Managed Iceberg)"
  deletion_protection = false
  labels              = local.common_labels

  biglake_configuration {
    connection_id = google_bigquery_connection.iceberg.name
    file_format   = "PARQUET"
    table_format  = "ICEBERG"
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/fct_invoice_line/"
  }

  schema = jsonencode([
    { name = "invoice_line_id", type = "INTEGER", mode = "REQUIRED" },
    { name = "invoice_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "track_key", type = "STRING", mode = "NULLABLE", description = "Surrogate key → dim_track" },
    { name = "customer_key", type = "STRING", mode = "NULLABLE", description = "Surrogate key → dim_customer (via invoice)" },
    { name = "unit_price", type = "FLOAT", mode = "NULLABLE" },
    { name = "quantity", type = "INTEGER", mode = "NULLABLE" },
    { name = "line_total", type = "FLOAT", mode = "NULLABLE", description = "unit_price * quantity" },
    { name = "_loaded_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER", mode = "NULLABLE" },
  ])
}

# -----------------------------------------------------------------------------
# Scheduled Queries (every 5 minutes)
# -----------------------------------------------------------------------------
# Gold tables use Managed Iceberg (BigLake), which does NOT support CQs.
# Instead, we use BigQuery scheduled queries running every 5 minutes.
# Dimension tables run first; fact tables depend on dims for surrogate keys.
# -----------------------------------------------------------------------------

locals {
  gold_sq_dir = "${path.module}/../transform/gold/sq"
}

resource "google_bigquery_data_transfer_config" "gold_dim_customer" {
  display_name         = "Gold: dim_customer (every 5 min)"
  location             = var.region
  data_source_id       = "scheduled_query"
  schedule             = "every 5 minutes"
  service_account_name = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sq_dir}/dim_customer.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [google_bigquery_table.gold_dim_customer]
}

resource "google_bigquery_data_transfer_config" "gold_dim_employee" {
  display_name         = "Gold: dim_employee (every 5 min)"
  location             = var.region
  data_source_id       = "scheduled_query"
  schedule             = "every 5 minutes"
  service_account_name = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sq_dir}/dim_employee.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [google_bigquery_table.gold_dim_employee]
}

resource "google_bigquery_data_transfer_config" "gold_dim_track" {
  display_name         = "Gold: dim_track (every 5 min)"
  location             = var.region
  data_source_id       = "scheduled_query"
  schedule             = "every 5 minutes"
  service_account_name = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sq_dir}/dim_track.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [google_bigquery_table.gold_dim_track]
}

resource "google_bigquery_data_transfer_config" "gold_fct_invoice" {
  display_name         = "Gold: fct_invoice (every 5 min)"
  location             = var.region
  data_source_id       = "scheduled_query"
  schedule             = "every 5 minutes"
  service_account_name = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sq_dir}/fct_invoice.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [
    google_bigquery_table.gold_fct_invoice,
    google_bigquery_data_transfer_config.gold_dim_customer,
  ]
}

resource "google_bigquery_data_transfer_config" "gold_fct_invoice_line" {
  display_name         = "Gold: fct_invoice_line (every 5 min)"
  location             = var.region
  data_source_id       = "scheduled_query"
  schedule             = "every 5 minutes"
  service_account_name = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sq_dir}/fct_invoice_line.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [
    google_bigquery_table.gold_fct_invoice_line,
    google_bigquery_data_transfer_config.gold_dim_customer,
    google_bigquery_data_transfer_config.gold_dim_track,
  ]
}
