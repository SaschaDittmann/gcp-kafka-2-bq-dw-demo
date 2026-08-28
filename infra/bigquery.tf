# =============================================================================
# BigQuery Data Warehouse: Bronze, Silver & Gold Layers
# =============================================================================
# Three-layer medallion architecture for CDC data:
#
# Bronze  — Raw CDC events from Kafka (Debezium envelope format)
# Silver  — Current-state entity tables with soft-delete handling
# Gold    — Star schema: SCD Type 2 dimensions + point-in-time fact tables
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

# =============================================================================
# Bronze Layer Tables — Auto-created by BigQuery Sink Connector
# =============================================================================
# The BQ sink connector auto-creates tables (autoCreateTables=true) with the
# correct schema inferred from the Debezium CDC envelope. Table names follow
# the pattern: {table}_raw (via RegexRouter SMT).
#
# Schema is derived from the Debezium source schema with value.converter
# schemas.enable=true, which produces properly typed RECORD columns for
# the `before`, `after`, and `source` envelope fields.
# =============================================================================

# =============================================================================
# Silver Layer Tables — Current-State Entity Tables
# =============================================================================
# One table per entity with typed columns. Continuous Queries extract fields
# from the Bronze layer's JSON `after` payload and MERGE into these tables.
# =============================================================================

# --- customer ---
resource "google_bigquery_table" "silver_customer" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "customer"
  description         = "Current-state customer records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "customer_id",    type = "INTEGER",   mode = "REQUIRED" },
    { name = "first_name",     type = "STRING",    mode = "NULLABLE" },
    { name = "last_name",      type = "STRING",    mode = "NULLABLE" },
    { name = "company",        type = "STRING",    mode = "NULLABLE" },
    { name = "address",        type = "STRING",    mode = "NULLABLE" },
    { name = "city",           type = "STRING",    mode = "NULLABLE" },
    { name = "state",          type = "STRING",    mode = "NULLABLE" },
    { name = "country",        type = "STRING",    mode = "NULLABLE" },
    { name = "postal_code",    type = "STRING",    mode = "NULLABLE" },
    { name = "email",          type = "STRING",    mode = "NULLABLE" },
    { name = "support_rep_id", type = "INTEGER",   mode = "NULLABLE" },
    { name = "is_deleted",     type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",     type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms",  type = "INTEGER",   mode = "NULLABLE" },
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
    { name = "employee_id",  type = "INTEGER",   mode = "REQUIRED" },
    { name = "last_name",    type = "STRING",    mode = "NULLABLE" },
    { name = "first_name",   type = "STRING",    mode = "NULLABLE" },
    { name = "title",        type = "STRING",    mode = "NULLABLE" },
    { name = "reports_to",   type = "INTEGER",   mode = "NULLABLE" },
    { name = "birth_date",   type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "hire_date",    type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "address",      type = "STRING",    mode = "NULLABLE" },
    { name = "city",         type = "STRING",    mode = "NULLABLE" },
    { name = "state",        type = "STRING",    mode = "NULLABLE" },
    { name = "country",      type = "STRING",    mode = "NULLABLE" },
    { name = "postal_code",  type = "STRING",    mode = "NULLABLE" },
    { name = "email",        type = "STRING",    mode = "NULLABLE" },
    { name = "is_deleted",   type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",   type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",  mode = "NULLABLE" },
  ])
}

# =============================================================================
# Silver Layer Views — Reference/Lookup Tables (Non-Persistent)
# =============================================================================
# These tables change rarely (genre, media_type, artist, album, playlist,
# playlist_track). Instead of running continuous CQs, we use views on Bronze
# with QUALIFY ROW_NUMBER() to extract the latest state.
#
# Views are defined as SQL scripts in transform/silver_*.sql and deployed
# after the BQ sink connector creates the Bronze tables. This avoids a
# dependency on auto-created tables during terraform apply.
#
# See: transform/silver_artist.sql, silver_album.sql, silver_genre.sql,
#      silver_media_type.sql, silver_playlist.sql, silver_playlist_track.sql
# =============================================================================

# =============================================================================
# Silver Layer Tables — Core Entity Tables (Persistent via CQ)
# =============================================================================
# These tables change frequently or feed Gold layer CQs as streaming sources.
# They are populated by Continuous Queries from Bronze.
# =============================================================================

# --- track ---
resource "google_bigquery_table" "silver_track" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "track"
  description         = "Current-state track records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "track_id",      type = "INTEGER",   mode = "REQUIRED" },
    { name = "name",          type = "STRING",    mode = "NULLABLE" },
    { name = "album_id",      type = "INTEGER",   mode = "NULLABLE" },
    { name = "media_type_id", type = "INTEGER",   mode = "NULLABLE" },
    { name = "genre_id",      type = "INTEGER",   mode = "NULLABLE" },
    { name = "composer",      type = "STRING",    mode = "NULLABLE" },
    { name = "milliseconds",  type = "INTEGER",   mode = "NULLABLE" },
    { name = "bytes",         type = "INTEGER",   mode = "NULLABLE" },
    { name = "unit_price",    type = "FLOAT",     mode = "NULLABLE" },
    { name = "is_deleted",    type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
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
    { name = "invoice_id",         type = "INTEGER",   mode = "REQUIRED" },
    { name = "customer_id",        type = "INTEGER",   mode = "NULLABLE" },
    { name = "invoice_date",       type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "billing_address",    type = "STRING",    mode = "NULLABLE" },
    { name = "billing_city",       type = "STRING",    mode = "NULLABLE" },
    { name = "billing_state",      type = "STRING",    mode = "NULLABLE" },
    { name = "billing_country",    type = "STRING",    mode = "NULLABLE" },
    { name = "billing_postal_code", type = "STRING",   mode = "NULLABLE" },
    { name = "total",              type = "FLOAT",     mode = "NULLABLE" },
    { name = "is_deleted",         type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",         type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms",      type = "INTEGER",   mode = "NULLABLE" },
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
    { name = "invoice_line_id", type = "INTEGER",   mode = "REQUIRED" },
    { name = "invoice_id",      type = "INTEGER",   mode = "NULLABLE" },
    { name = "track_id",        type = "INTEGER",   mode = "NULLABLE" },
    { name = "unit_price",      type = "FLOAT",     mode = "NULLABLE" },
    { name = "quantity",        type = "INTEGER",   mode = "NULLABLE" },
    { name = "is_deleted",      type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",      type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms",   type = "INTEGER",   mode = "NULLABLE" },
  ])
}


# =============================================================================
# Gold Layer — Star Schema (Managed Apache Iceberg Tables)
# =============================================================================
# Gold tables use BigQuery Managed Iceberg format, storing data as Parquet
# in a customer-owned GCS bucket. This enables interoperability with any
# engine that supports Apache Iceberg (Spark, Trino, Flink, etc.)
# =============================================================================

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
    { name = "surrogate_key", type = "STRING",    mode = "REQUIRED", description = "Unique row key (UUID)" },
    { name = "natural_key",   type = "INTEGER",   mode = "REQUIRED", description = "customer_id from source" },
    { name = "first_name",    type = "STRING",    mode = "NULLABLE" },
    { name = "last_name",     type = "STRING",    mode = "NULLABLE" },
    { name = "company",       type = "STRING",    mode = "NULLABLE" },
    { name = "address",       type = "STRING",    mode = "NULLABLE" },
    { name = "city",          type = "STRING",    mode = "NULLABLE" },
    { name = "state",         type = "STRING",    mode = "NULLABLE" },
    { name = "country",       type = "STRING",    mode = "NULLABLE" },
    { name = "postal_code",   type = "STRING",    mode = "NULLABLE" },
    { name = "email",         type = "STRING",    mode = "NULLABLE" },
    { name = "support_rep_id", type = "INTEGER",  mode = "NULLABLE" },
    { name = "valid_from",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to",      type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_active",     type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
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
    { name = "surrogate_key",   type = "STRING",    mode = "REQUIRED" },
    { name = "natural_key",     type = "INTEGER",   mode = "REQUIRED", description = "track_id from source" },
    { name = "track_name",      type = "STRING",    mode = "NULLABLE" },
    { name = "album_title",     type = "STRING",    mode = "NULLABLE" },
    { name = "artist_name",     type = "STRING",    mode = "NULLABLE" },
    { name = "genre_name",      type = "STRING",    mode = "NULLABLE" },
    { name = "media_type_name", type = "STRING",    mode = "NULLABLE" },
    { name = "composer",        type = "STRING",    mode = "NULLABLE" },
    { name = "milliseconds",    type = "INTEGER",   mode = "NULLABLE" },
    { name = "bytes",           type = "INTEGER",   mode = "NULLABLE" },
    { name = "unit_price",      type = "FLOAT",     mode = "NULLABLE" },
    { name = "valid_from",      type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to",        type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_active",       type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",      type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms",   type = "INTEGER",   mode = "NULLABLE" },
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
    { name = "surrogate_key", type = "STRING",    mode = "REQUIRED" },
    { name = "natural_key",   type = "INTEGER",   mode = "REQUIRED", description = "employee_id from source" },
    { name = "first_name",    type = "STRING",    mode = "NULLABLE" },
    { name = "last_name",     type = "STRING",    mode = "NULLABLE" },
    { name = "title",         type = "STRING",    mode = "NULLABLE" },
    { name = "reports_to",    type = "INTEGER",   mode = "NULLABLE" },
    { name = "birth_date",    type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "hire_date",     type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "address",       type = "STRING",    mode = "NULLABLE" },
    { name = "city",          type = "STRING",    mode = "NULLABLE" },
    { name = "state",         type = "STRING",    mode = "NULLABLE" },
    { name = "country",       type = "STRING",    mode = "NULLABLE" },
    { name = "postal_code",   type = "STRING",    mode = "NULLABLE" },
    { name = "email",         type = "STRING",    mode = "NULLABLE" },
    { name = "valid_from",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to",      type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_active",     type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
  ])
}

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
    { name = "invoice_id",          type = "INTEGER",   mode = "REQUIRED" },
    { name = "customer_key",        type = "STRING",    mode = "NULLABLE", description = "Surrogate key → dim_customer" },
    { name = "invoice_date",        type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "billing_address",     type = "STRING",    mode = "NULLABLE" },
    { name = "billing_city",        type = "STRING",    mode = "NULLABLE" },
    { name = "billing_state",       type = "STRING",    mode = "NULLABLE" },
    { name = "billing_country",     type = "STRING",    mode = "NULLABLE" },
    { name = "billing_postal_code", type = "STRING",    mode = "NULLABLE" },
    { name = "total",               type = "FLOAT",     mode = "NULLABLE" },
    { name = "_loaded_at",          type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms",       type = "INTEGER",   mode = "NULLABLE" },
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
    { name = "invoice_line_id", type = "INTEGER",   mode = "REQUIRED" },
    { name = "invoice_id",      type = "INTEGER",   mode = "NULLABLE" },
    { name = "track_key",       type = "STRING",    mode = "NULLABLE", description = "Surrogate key → dim_track" },
    { name = "customer_key",    type = "STRING",    mode = "NULLABLE", description = "Surrogate key → dim_customer (via invoice)" },
    { name = "unit_price",      type = "FLOAT",     mode = "NULLABLE" },
    { name = "quantity",        type = "INTEGER",   mode = "NULLABLE" },
    { name = "line_total",      type = "FLOAT",     mode = "NULLABLE", description = "unit_price * quantity" },
    { name = "_loaded_at",      type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms",   type = "INTEGER",   mode = "NULLABLE" },
  ])
}

# =============================================================================
# Gold Layer — Scheduled Queries (every 5 minutes)
# =============================================================================
# Gold tables use Managed Iceberg (BigLake), which does NOT support CQs.
# Instead, we use BigQuery scheduled queries running every 5 minutes.
# Dimension tables run first; fact tables depend on dims for surrogate keys.
# =============================================================================

locals {
  gold_sql_dir = "${path.module}/../transform"
}

resource "google_bigquery_data_transfer_config" "gold_dim_customer" {
  display_name   = "Gold: dim_customer (every 5 min)"
  location       = var.region
  data_source_id = "scheduled_query"
  schedule               = "every 5 minutes"
  service_account_name   = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sql_dir}/gold_dim_customer.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [google_bigquery_table.gold_dim_customer]
}

resource "google_bigquery_data_transfer_config" "gold_dim_employee" {
  display_name   = "Gold: dim_employee (every 5 min)"
  location       = var.region
  data_source_id = "scheduled_query"
  schedule       = "every 5 minutes"
  service_account_name   = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sql_dir}/gold_dim_employee.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [google_bigquery_table.gold_dim_employee]
}

resource "google_bigquery_data_transfer_config" "gold_dim_track" {
  display_name   = "Gold: dim_track (every 5 min)"
  location       = var.region
  data_source_id = "scheduled_query"
  schedule       = "every 5 minutes"
  service_account_name   = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sql_dir}/gold_dim_track.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [google_bigquery_table.gold_dim_track]
}

resource "google_bigquery_data_transfer_config" "gold_fct_invoice" {
  display_name   = "Gold: fct_invoice (every 5 min)"
  location       = var.region
  data_source_id = "scheduled_query"
  schedule       = "every 5 minutes"
  service_account_name   = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sql_dir}/gold_fct_invoice.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [
    google_bigquery_table.gold_fct_invoice,
    google_bigquery_data_transfer_config.gold_dim_customer,
  ]
}

resource "google_bigquery_data_transfer_config" "gold_fct_invoice_line" {
  display_name   = "Gold: fct_invoice_line (every 5 min)"
  location       = var.region
  data_source_id = "scheduled_query"
  schedule       = "every 5 minutes"
  service_account_name   = google_service_account.kafka_connect.email

  params = {
    query = replace(file("${local.gold_sql_dir}/gold_fct_invoice_line.sql"), "$${PROJECT_ID}", var.project_id)
  }

  depends_on = [
    google_bigquery_table.gold_fct_invoice_line,
    google_bigquery_data_transfer_config.gold_dim_customer,
    google_bigquery_data_transfer_config.gold_dim_track,
  ]
}
