# =============================================================================
# BigQuery Bronze Layer — Raw CDC Tables (Debezium Envelope)
# =============================================================================
# Pre-created with the exact schema the BigQuery Sink Connector expects.
# The connector's autoCreateTables finds these already exist and writes to
# them directly. This allows Silver views to reference Bronze tables in
# the same terraform apply.
#
# Schema: Debezium CDC envelope with typed RECORD columns.
# Shared fields: source (RECORD), transaction (RECORD), op, ts_ms, ts_us, ts_ns
# Table-specific: before (RECORD), after (RECORD) — mirror PG source columns
# =============================================================================

locals {
  # Shared Debezium source metadata RECORD — identical across all tables
  debezium_source_fields = jsonencode([
    { name = "version", type = "STRING", mode = "REQUIRED" },
    { name = "connector", type = "STRING", mode = "REQUIRED" },
    { name = "name", type = "STRING", mode = "REQUIRED" },
    { name = "ts_ms", type = "INTEGER", mode = "REQUIRED" },
    { name = "snapshot", type = "STRING", mode = "NULLABLE" },
    { name = "db", type = "STRING", mode = "REQUIRED" },
    { name = "sequence", type = "STRING", mode = "NULLABLE" },
    { name = "ts_us", type = "INTEGER", mode = "NULLABLE" },
    { name = "ts_ns", type = "INTEGER", mode = "NULLABLE" },
    { name = "schema", type = "STRING", mode = "REQUIRED" },
    { name = "table", type = "STRING", mode = "REQUIRED" },
    { name = "txId", type = "INTEGER", mode = "NULLABLE" },
    { name = "lsn", type = "INTEGER", mode = "NULLABLE" },
    { name = "xmin", type = "INTEGER", mode = "NULLABLE" },
  ])

  # Shared Debezium transaction RECORD
  debezium_transaction_fields = jsonencode([
    { name = "id", type = "STRING", mode = "REQUIRED" },
    { name = "total_order", type = "INTEGER", mode = "REQUIRED" },
    { name = "data_collection_order", type = "INTEGER", mode = "REQUIRED" },
  ])

  # Per-table entity fields (used for both before and after RECORDs)
  entity_fields = {
    artist = jsonencode([
      { name = "artist_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "name", type = "STRING", mode = "NULLABLE" },
    ])
    album = jsonencode([
      { name = "album_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "title", type = "STRING", mode = "REQUIRED" },
      { name = "artist_id", type = "INTEGER", mode = "REQUIRED" },
    ])
    genre = jsonencode([
      { name = "genre_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "name", type = "STRING", mode = "NULLABLE" },
    ])
    media_type = jsonencode([
      { name = "media_type_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "name", type = "STRING", mode = "NULLABLE" },
    ])
    playlist = jsonencode([
      { name = "playlist_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "name", type = "STRING", mode = "NULLABLE" },
    ])
    playlist_track = jsonencode([
      { name = "playlist_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "track_id", type = "INTEGER", mode = "REQUIRED" },
    ])
    customer = jsonencode([
      { name = "customer_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "first_name", type = "STRING", mode = "REQUIRED" },
      { name = "last_name", type = "STRING", mode = "REQUIRED" },
      { name = "company", type = "STRING", mode = "NULLABLE" },
      { name = "address", type = "STRING", mode = "NULLABLE" },
      { name = "city", type = "STRING", mode = "NULLABLE" },
      { name = "state", type = "STRING", mode = "NULLABLE" },
      { name = "country", type = "STRING", mode = "NULLABLE" },
      { name = "postal_code", type = "STRING", mode = "NULLABLE" },
      { name = "phone", type = "STRING", mode = "NULLABLE" },
      { name = "fax", type = "STRING", mode = "NULLABLE" },
      { name = "email", type = "STRING", mode = "REQUIRED" },
      { name = "support_rep_id", type = "INTEGER", mode = "NULLABLE" },
    ])
    employee = jsonencode([
      { name = "employee_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "last_name", type = "STRING", mode = "REQUIRED" },
      { name = "first_name", type = "STRING", mode = "REQUIRED" },
      { name = "title", type = "STRING", mode = "NULLABLE" },
      { name = "reports_to", type = "INTEGER", mode = "NULLABLE" },
      { name = "birth_date", type = "TIMESTAMP", mode = "NULLABLE" },
      { name = "hire_date", type = "TIMESTAMP", mode = "NULLABLE" },
      { name = "address", type = "STRING", mode = "NULLABLE" },
      { name = "city", type = "STRING", mode = "NULLABLE" },
      { name = "state", type = "STRING", mode = "NULLABLE" },
      { name = "country", type = "STRING", mode = "NULLABLE" },
      { name = "postal_code", type = "STRING", mode = "NULLABLE" },
      { name = "phone", type = "STRING", mode = "NULLABLE" },
      { name = "fax", type = "STRING", mode = "NULLABLE" },
      { name = "email", type = "STRING", mode = "NULLABLE" },
    ])
    track = jsonencode([
      { name = "track_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "name", type = "STRING", mode = "REQUIRED" },
      { name = "album_id", type = "INTEGER", mode = "NULLABLE" },
      { name = "media_type_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "genre_id", type = "INTEGER", mode = "NULLABLE" },
      { name = "composer", type = "STRING", mode = "NULLABLE" },
      { name = "milliseconds", type = "INTEGER", mode = "REQUIRED" },
      { name = "bytes", type = "INTEGER", mode = "NULLABLE" },
      { name = "unit_price", type = "FLOAT", mode = "REQUIRED" },
    ])
    invoice = jsonencode([
      { name = "invoice_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "customer_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "invoice_date", type = "TIMESTAMP", mode = "REQUIRED" },
      { name = "billing_address", type = "STRING", mode = "NULLABLE" },
      { name = "billing_city", type = "STRING", mode = "NULLABLE" },
      { name = "billing_state", type = "STRING", mode = "NULLABLE" },
      { name = "billing_country", type = "STRING", mode = "NULLABLE" },
      { name = "billing_postal_code", type = "STRING", mode = "NULLABLE" },
      { name = "total", type = "FLOAT", mode = "REQUIRED" },
    ])
    invoice_line = jsonencode([
      { name = "invoice_line_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "invoice_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "track_id", type = "INTEGER", mode = "REQUIRED" },
      { name = "unit_price", type = "FLOAT", mode = "REQUIRED" },
      { name = "quantity", type = "INTEGER", mode = "REQUIRED" },
    ])
  }
}

# -----------------------------------------------------------------------------
# Bronze tables — one per Chinook source table
# -----------------------------------------------------------------------------
# Uses for_each to avoid repeating the shared Debezium envelope for each table.

resource "google_bigquery_table" "bronze" {
  for_each = local.entity_fields

  dataset_id          = google_bigquery_dataset.bronze.dataset_id
  table_id            = "${each.key}_raw"
  description         = "Raw CDC events for ${each.key} (Debezium envelope)"
  deletion_protection = false
  labels              = local.common_labels

  # Ingestion-time partitioning (matches connector's auto-created tables)
  time_partitioning {
    type = "DAY"
  }

  schema = jsonencode([
    {
      name   = "before"
      type   = "RECORD"
      mode   = "NULLABLE"
      fields = jsondecode(each.value)
    },
    {
      name   = "after"
      type   = "RECORD"
      mode   = "NULLABLE"
      fields = jsondecode(each.value)
    },
    {
      name   = "source"
      type   = "RECORD"
      mode   = "REQUIRED"
      fields = jsondecode(local.debezium_source_fields)
    },
    {
      name   = "transaction"
      type   = "RECORD"
      mode   = "NULLABLE"
      fields = jsondecode(local.debezium_transaction_fields)
    },
    { name = "op", type = "STRING", mode = "REQUIRED" },
    { name = "ts_ms", type = "INTEGER", mode = "NULLABLE" },
    { name = "ts_us", type = "INTEGER", mode = "NULLABLE" },
    { name = "ts_ns", type = "INTEGER", mode = "NULLABLE" },
  ])
}

