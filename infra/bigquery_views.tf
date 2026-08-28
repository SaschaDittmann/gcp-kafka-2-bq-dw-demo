# =============================================================================
# BigQuery Views — Silver (on Bronze) + Gold (current-state)
# =============================================================================
# All views are Terraform-managed so they survive `terraform apply`.
# Silver views depend on Bronze tables (pre-created in bigquery_bronze.tf).
# Gold views depend on Gold Iceberg tables (created in bigquery.tf).
# =============================================================================

# -----------------------------------------------------------------------------
# Silver Views — Reference/Lookup Tables (read from Bronze)
# -----------------------------------------------------------------------------
# These tables change rarely. Instead of CQs, views with QUALIFY ROW_NUMBER()
# provide current-state dedup on read.
# -----------------------------------------------------------------------------

resource "google_bigquery_table" "silver_artist_view" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "artist"
  description         = "Current-state artist records (view on Bronze)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        after.artist_id AS artist_id,
        after.name      AS name,
        IF(op = 'd', TRUE, FALSE) AS is_deleted,
        ts_ms AS _source_ts_ms
      FROM `${var.project_id}.bronze.artist_raw`
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY after.artist_id
        ORDER BY ts_ms DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.bronze["artist"]]
}

resource "google_bigquery_table" "silver_album_view" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "album"
  description         = "Current-state album records (view on Bronze)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        after.album_id  AS album_id,
        after.title     AS title,
        after.artist_id AS artist_id,
        IF(op = 'd', TRUE, FALSE) AS is_deleted,
        ts_ms AS _source_ts_ms
      FROM `${var.project_id}.bronze.album_raw`
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY after.album_id
        ORDER BY ts_ms DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.bronze["album"]]
}

resource "google_bigquery_table" "silver_genre_view" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "genre"
  description         = "Current-state genre records (view on Bronze)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        after.genre_id AS genre_id,
        after.name     AS name,
        IF(op = 'd', TRUE, FALSE) AS is_deleted,
        ts_ms AS _source_ts_ms
      FROM `${var.project_id}.bronze.genre_raw`
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY after.genre_id
        ORDER BY ts_ms DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.bronze["genre"]]
}

resource "google_bigquery_table" "silver_media_type_view" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "media_type"
  description         = "Current-state media type records (view on Bronze)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        after.media_type_id AS media_type_id,
        after.name          AS name,
        IF(op = 'd', TRUE, FALSE) AS is_deleted,
        ts_ms AS _source_ts_ms
      FROM `${var.project_id}.bronze.media_type_raw`
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY after.media_type_id
        ORDER BY ts_ms DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.bronze["media_type"]]
}

resource "google_bigquery_table" "silver_playlist_view" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "playlist"
  description         = "Current-state playlist records (view on Bronze)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        after.playlist_id AS playlist_id,
        after.name        AS name,
        IF(op = 'd', TRUE, FALSE) AS is_deleted,
        ts_ms AS _source_ts_ms
      FROM `${var.project_id}.bronze.playlist_raw`
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY after.playlist_id
        ORDER BY ts_ms DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.bronze["playlist"]]
}

resource "google_bigquery_table" "silver_playlist_track_view" {
  dataset_id          = google_bigquery_dataset.silver.dataset_id
  table_id            = "playlist_track"
  description         = "Current-state playlist_track records (view on Bronze)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        after.playlist_id AS playlist_id,
        after.track_id    AS track_id,
        IF(op = 'd', TRUE, FALSE) AS is_deleted,
        ts_ms AS _source_ts_ms
      FROM `${var.project_id}.bronze.playlist_track_raw`
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY after.playlist_id, after.track_id
        ORDER BY ts_ms DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.bronze["playlist_track"]]
}

# -----------------------------------------------------------------------------
# Gold Views — Current-State Access to SCD2 Dimensions + Enriched Facts
# -----------------------------------------------------------------------------
# These views make it easy to query the latest active dimension record
# and facts with resolved dimension names.
# -----------------------------------------------------------------------------

resource "google_bigquery_table" "gold_v_dim_customer" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "v_dim_customer"
  description         = "Current-state customer dimension (latest active SCD2 record)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        surrogate_key,
        natural_key   AS customer_id,
        first_name,
        last_name,
        company,
        address,
        city,
        state,
        country,
        postal_code,
        email,
        support_rep_id,
        valid_from,
        _loaded_at,
        _source_ts_ms
      FROM `${var.project_id}.gold.dim_customer`
      WHERE is_active = TRUE
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY natural_key
        ORDER BY valid_from DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.gold_dim_customer]
}

resource "google_bigquery_table" "gold_v_dim_employee" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "v_dim_employee"
  description         = "Current-state employee dimension (latest active SCD2 record)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        surrogate_key,
        natural_key   AS employee_id,
        first_name,
        last_name,
        title,
        reports_to,
        birth_date,
        hire_date,
        address,
        city,
        state,
        country,
        postal_code,
        email,
        valid_from,
        _loaded_at,
        _source_ts_ms
      FROM `${var.project_id}.gold.dim_employee`
      WHERE is_active = TRUE
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY natural_key
        ORDER BY valid_from DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.gold_dim_employee]
}

resource "google_bigquery_table" "gold_v_dim_track" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "v_dim_track"
  description         = "Current-state track dimension (denormalized, latest active SCD2 record)"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        surrogate_key,
        natural_key   AS track_id,
        track_name,
        album_title,
        artist_name,
        genre_name,
        media_type_name,
        composer,
        milliseconds,
        bytes,
        unit_price,
        valid_from,
        _loaded_at,
        _source_ts_ms
      FROM `${var.project_id}.gold.dim_track`
      WHERE is_active = TRUE
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY natural_key
        ORDER BY valid_from DESC
      ) = 1
    SQL
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.gold_dim_track]
}

resource "google_bigquery_table" "gold_v_fct_invoice" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "v_fct_invoice"
  description         = "Invoices with resolved customer dimension names"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        f.invoice_id,
        f.customer_key,
        c.customer_id,
        c.first_name    AS customer_first_name,
        c.last_name     AS customer_last_name,
        c.company       AS customer_company,
        f.invoice_date,
        f.billing_address,
        f.billing_city,
        f.billing_state,
        f.billing_country,
        f.billing_postal_code,
        f.total,
        f._loaded_at,
        f._source_ts_ms
      FROM `${var.project_id}.gold.fct_invoice` f
      LEFT JOIN `${var.project_id}.gold.v_dim_customer` c
        ON f.customer_key = c.surrogate_key
    SQL
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.gold_fct_invoice,
    google_bigquery_table.gold_v_dim_customer,
  ]
}

resource "google_bigquery_table" "gold_v_fct_invoice_line" {
  dataset_id          = google_bigquery_dataset.gold.dataset_id
  table_id            = "v_fct_invoice_line"
  description         = "Invoice lines with resolved track and customer dimension names"
  deletion_protection = false
  labels              = local.common_labels

  view {
    query          = <<-SQL
      SELECT
        f.invoice_line_id,
        f.invoice_id,
        f.track_key,
        t.track_id,
        t.track_name,
        t.artist_name,
        t.album_title,
        t.genre_name,
        f.customer_key,
        c.customer_id,
        c.first_name    AS customer_first_name,
        c.last_name     AS customer_last_name,
        f.unit_price,
        f.quantity,
        f.line_total,
        f._loaded_at,
        f._source_ts_ms
      FROM `${var.project_id}.gold.fct_invoice_line` f
      LEFT JOIN `${var.project_id}.gold.v_dim_track` t
        ON f.track_key = t.surrogate_key
      LEFT JOIN `${var.project_id}.gold.v_dim_customer` c
        ON f.customer_key = c.surrogate_key
    SQL
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.gold_fct_invoice_line,
    google_bigquery_table.gold_v_dim_track,
    google_bigquery_table.gold_v_dim_customer,
  ]
}

