-- =============================================================================
-- Scheduled Query: Silver → Gold — dim_customer (SCD Type 2)
-- =============================================================================
-- Runs every 5 minutes. Inserts new customer versions from Silver into Gold.
-- Uses a 10-minute lookback window (2× interval for overlap safety).
--
-- Run manually: bq query --use_legacy_sql=false < transform/gold_dim_customer.sql
-- =============================================================================

INSERT INTO `${PROJECT_ID}.gold.dim_customer` (
  surrogate_key, natural_key,
  first_name, last_name, company, address, city,
  state, country, postal_code, email, support_rep_id,
  valid_from, valid_to, is_active,
  _loaded_at, _source_ts_ms
)
SELECT
  GENERATE_UUID()        AS surrogate_key,
  customer_id            AS natural_key,
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
  _loaded_at             AS valid_from,
  CAST(NULL AS TIMESTAMP) AS valid_to,
  TRUE                   AS is_active,
  _loaded_at,
  _source_ts_ms
FROM `${PROJECT_ID}.silver.customer`
WHERE is_deleted = FALSE
  AND _loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);
