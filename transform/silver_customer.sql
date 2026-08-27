-- =============================================================================
-- Continuous Query: Bronze → Silver — customer
-- =============================================================================
-- Extracts typed fields from the Debezium CDC envelope (JSON 'after' payload)
-- and streams them into the Silver customer table.
--
-- Run with: bq query --use_legacy_sql=false --continuous=true < transform/silver_customer.sql
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.customer` (
  customer_id,
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
  is_deleted,
  _loaded_at,
  _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.customer_id') AS INT64)   AS customer_id,
  JSON_VALUE(after, '$.first_name')                    AS first_name,
  JSON_VALUE(after, '$.last_name')                     AS last_name,
  JSON_VALUE(after, '$.company')                       AS company,
  JSON_VALUE(after, '$.address')                       AS address,
  JSON_VALUE(after, '$.city')                          AS city,
  JSON_VALUE(after, '$.state')                         AS state,
  JSON_VALUE(after, '$.country')                       AS country,
  JSON_VALUE(after, '$.postal_code')                   AS postal_code,
  JSON_VALUE(after, '$.email')                         AS email,
  CAST(JSON_VALUE(after, '$.support_rep_id') AS INT64) AS support_rep_id,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  _CHANGE_TIMESTAMP                                    AS _loaded_at,
  ts_ms                                                AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.customer_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
