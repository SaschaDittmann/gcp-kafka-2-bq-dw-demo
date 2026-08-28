-- =============================================================================
-- Scheduled Query: Silver → Gold — fct_invoice_line
-- =============================================================================
-- Enriches invoice line records with track and customer dimension keys.
-- Runs every 5 minutes.
--
-- NOTE: Uses JOINs instead of correlated subqueries (Iceberg limitation).
-- =============================================================================

INSERT INTO `${PROJECT_ID}.gold.fct_invoice_line` (
  invoice_line_id, invoice_id,
  track_key, customer_key,
  unit_price, quantity, line_total,
  _loaded_at, _source_ts_ms
)
SELECT
  il.invoice_line_id,
  il.invoice_id,
  dt.surrogate_key       AS track_key,
  dc.surrogate_key       AS customer_key,
  il.unit_price,
  il.quantity,
  il.unit_price * il.quantity AS line_total,
  il._loaded_at,
  il._source_ts_ms
FROM `${PROJECT_ID}.silver.invoice_line` AS il
LEFT JOIN (
  SELECT natural_key, surrogate_key
  FROM `${PROJECT_ID}.gold.dim_track`
  WHERE is_active = TRUE
  QUALIFY ROW_NUMBER() OVER (PARTITION BY natural_key ORDER BY valid_from DESC) = 1
) dt ON dt.natural_key = il.track_id
LEFT JOIN `${PROJECT_ID}.silver.invoice` inv
  ON inv.invoice_id = il.invoice_id AND inv.is_deleted = FALSE
LEFT JOIN (
  SELECT natural_key, surrogate_key
  FROM `${PROJECT_ID}.gold.dim_customer`
  WHERE is_active = TRUE
  QUALIFY ROW_NUMBER() OVER (PARTITION BY natural_key ORDER BY valid_from DESC) = 1
) dc ON dc.natural_key = inv.customer_id
WHERE il.is_deleted = FALSE
  AND il._loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);
