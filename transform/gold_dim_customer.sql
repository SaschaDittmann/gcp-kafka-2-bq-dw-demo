-- =============================================================================
-- Continuous Query: Silver → Gold — dim_customer (SCD Type 2)
-- =============================================================================
-- Streams customer changes from the Silver layer into the Gold dimension.
-- Each change creates a new active record with a new surrogate key.
--
-- NOTE: BigQuery CQs are INSERT-only. SCD Type 2 close-out (setting
-- valid_to and is_active=FALSE on the previous record) is handled by
-- a scheduled query or a view with QUALIFY ROW_NUMBER().
--
-- Run with: bq query --use_legacy_sql=false --continuous=true < transform/gold_dim_customer.sql
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
FROM APPENDS(
  TABLE `${PROJECT_ID}.silver.customer`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
)
WHERE is_deleted = FALSE;
