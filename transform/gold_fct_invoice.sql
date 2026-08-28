-- =============================================================================
-- Scheduled Query: Silver → Gold — fct_invoice
-- =============================================================================
-- Enriches invoice records with customer dimension surrogate keys.
-- Runs every 5 minutes.
--
-- NOTE: Uses JOIN instead of correlated subquery (Iceberg limitation).
-- =============================================================================

INSERT INTO `${PROJECT_ID}.gold.fct_invoice` (
  invoice_id, customer_key,
  invoice_date, billing_address, billing_city,
  billing_state, billing_country, billing_postal_code,
  total, _loaded_at, _source_ts_ms
)
SELECT
  i.invoice_id,
  dc.surrogate_key       AS customer_key,
  i.invoice_date,
  i.billing_address,
  i.billing_city,
  i.billing_state,
  i.billing_country,
  i.billing_postal_code,
  i.total,
  i._loaded_at,
  i._source_ts_ms
FROM `${PROJECT_ID}.silver.invoice` AS i
LEFT JOIN (
  SELECT natural_key, surrogate_key
  FROM `${PROJECT_ID}.gold.dim_customer`
  WHERE is_active = TRUE
  QUALIFY ROW_NUMBER() OVER (PARTITION BY natural_key ORDER BY valid_from DESC) = 1
) dc ON dc.natural_key = i.customer_id
WHERE i.is_deleted = FALSE
  AND i._loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);
