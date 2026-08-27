-- =============================================================================
-- Continuous Query: Silver → Gold — fct_invoice_line
-- =============================================================================
-- Enriches invoice line records with track and customer dimension keys.
--
-- Uses scalar subqueries for point-in-time dimension lookups:
-- - track_key from dim_track (active record)
-- - customer_key via invoice → dim_customer (active record)
-- - Computes line_total = unit_price × quantity
--
-- Run with: bq query --use_legacy_sql=false --continuous=true < transform/gold_fct_invoice_line.sql
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
  (SELECT dt.surrogate_key FROM `${PROJECT_ID}.gold.dim_track` dt
   WHERE dt.natural_key = il.track_id
     AND dt.is_active = TRUE
   ORDER BY dt.valid_from DESC LIMIT 1)  AS track_key,
  (SELECT dc.surrogate_key FROM `${PROJECT_ID}.gold.dim_customer` dc
   INNER JOIN `${PROJECT_ID}.silver.invoice` inv
     ON dc.natural_key = inv.customer_id AND inv.is_deleted = FALSE
   WHERE inv.invoice_id = il.invoice_id
     AND dc.is_active = TRUE
   ORDER BY dc.valid_from DESC, inv._loaded_at DESC LIMIT 1) AS customer_key,
  il.unit_price,
  il.quantity,
  il.unit_price * il.quantity AS line_total,
  il._loaded_at,
  il._source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.silver.invoice_line`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
) AS il
WHERE il.is_deleted = FALSE;

