-- =============================================================================
-- Gold View: v_fct_invoice_line — Invoice lines with resolved dimensions
-- =============================================================================
-- Joins fact invoice lines with track and customer dimensions.
-- =============================================================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.gold.v_fct_invoice_line` AS
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
FROM `${PROJECT_ID}.gold.fct_invoice_line` f
LEFT JOIN `${PROJECT_ID}.gold.v_dim_track` t
  ON f.track_key = t.surrogate_key
LEFT JOIN `${PROJECT_ID}.gold.v_dim_customer` c
  ON f.customer_key = c.surrogate_key;

