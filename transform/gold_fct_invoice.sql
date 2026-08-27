-- =============================================================================
-- Continuous Query: Silver → Gold — fct_invoice
-- =============================================================================
-- Enriches invoice records with customer dimension surrogate keys.
--
-- Uses scalar subquery to look up the active dim_customer record
-- at the time of the invoice for point-in-time correctness.
--
-- Run with: bq query --use_legacy_sql=false --continuous=true < transform/gold_fct_invoice.sql
-- =============================================================================

INSERT INTO `${PROJECT_ID}.gold.fct_invoice` (
  invoice_id, customer_key,
  invoice_date, billing_address, billing_city,
  billing_state, billing_country, billing_postal_code,
  total, _loaded_at, _source_ts_ms
)
SELECT
  i.invoice_id,
  (SELECT dc.surrogate_key FROM `${PROJECT_ID}.gold.dim_customer` dc
   WHERE dc.natural_key = i.customer_id
     AND dc.is_active = TRUE
   ORDER BY dc.valid_from DESC LIMIT 1)  AS customer_key,
  i.invoice_date,
  i.billing_address,
  i.billing_city,
  i.billing_state,
  i.billing_country,
  i.billing_postal_code,
  i.total,
  i._loaded_at,
  i._source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.silver.invoice`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
) AS i
WHERE i.is_deleted = FALSE;
