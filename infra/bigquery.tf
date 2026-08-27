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
# Bronze Layer Tables — Raw Debezium CDC Events
# =============================================================================
# Each table stores the full Debezium envelope: before, after, op, ts_ms, source
# The BigQuery Sink connector writes directly to these tables.
# =============================================================================

locals {
  bronze_tables = toset(local.chinook_tables)
}

resource "google_bigquery_table" "bronze" {
  for_each = local.bronze_tables

  dataset_id          = google_bigquery_dataset.bronze.dataset_id
  table_id            = "${each.value}_raw"
  description         = "Raw CDC events for ${each.value} table"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "before",        type = "STRING", mode = "NULLABLE", description = "Row state before the change (JSON)" },
    { name = "after",         type = "STRING", mode = "NULLABLE", description = "Row state after the change (JSON)" },
    { name = "op",            type = "STRING", mode = "NULLABLE", description = "Operation: c=create, u=update, d=delete, r=read(snapshot)" },
    { name = "ts_ms",         type = "INTEGER", mode = "NULLABLE", description = "Debezium event timestamp in milliseconds" },
    { name = "source",        type = "STRING", mode = "NULLABLE", description = "Source metadata (JSON): database, schema, table, LSN" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "NULLABLE", description = "Timestamp when the record was loaded into BigQuery" },
  ])
}

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

# --- artist ---
resource "google_bigquery_table" "silver_artist" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "artist"
  description         = "Current-state artist records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "artist_id",     type = "INTEGER",   mode = "REQUIRED" },
    { name = "name",          type = "STRING",    mode = "NULLABLE" },
    { name = "is_deleted",    type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
  ])
}

# --- album ---
resource "google_bigquery_table" "silver_album" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "album"
  description         = "Current-state album records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "album_id",      type = "INTEGER",   mode = "REQUIRED" },
    { name = "title",         type = "STRING",    mode = "NULLABLE" },
    { name = "artist_id",     type = "INTEGER",   mode = "NULLABLE" },
    { name = "is_deleted",    type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
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

# --- genre ---
resource "google_bigquery_table" "silver_genre" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "genre"
  description         = "Current-state genre records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "genre_id",      type = "INTEGER",   mode = "REQUIRED" },
    { name = "name",          type = "STRING",    mode = "NULLABLE" },
    { name = "is_deleted",    type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
  ])
}

# --- media_type ---
resource "google_bigquery_table" "silver_media_type" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "media_type"
  description         = "Current-state media type records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "media_type_id", type = "INTEGER",   mode = "REQUIRED" },
    { name = "name",          type = "STRING",    mode = "NULLABLE" },
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

# --- playlist ---
resource "google_bigquery_table" "silver_playlist" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "playlist"
  description         = "Current-state playlist records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "playlist_id",   type = "INTEGER",   mode = "REQUIRED" },
    { name = "name",          type = "STRING",    mode = "NULLABLE" },
    { name = "is_deleted",    type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
  ])
}

# --- playlist_track ---
resource "google_bigquery_table" "silver_playlist_track" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "playlist_track"
  description         = "Current-state playlist-track association records"
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "playlist_id",   type = "INTEGER",   mode = "REQUIRED" },
    { name = "track_id",      type = "INTEGER",   mode = "REQUIRED" },
    { name = "is_deleted",    type = "BOOLEAN",   mode = "REQUIRED" },
    { name = "_loaded_at",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "_source_ts_ms", type = "INTEGER",   mode = "NULLABLE" },
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
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/dim_customer"
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
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/dim_track"
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
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/dim_employee"
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
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/fct_invoice"
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
    storage_uri   = "gs://${google_storage_bucket.iceberg_data.name}/fct_invoice_line"
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
