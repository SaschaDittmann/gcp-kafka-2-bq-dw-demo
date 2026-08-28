-- =============================================================================
-- Continuous Query: Bronze → Silver — customer
-- =============================================================================
-- Extracts typed fields from the Debezium CDC envelope (RECORD 'after' struct)
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
  after.customer_id                                    AS customer_id,
  after.first_name                                     AS first_name,
  after.last_name                                      AS last_name,
  after.company                                        AS company,
  after.address                                        AS address,
  after.city                                           AS city,
  after.state                                          AS state,
  after.country                                        AS country,
  after.postal_code                                    AS postal_code,
  after.email                                          AS email,
  after.support_rep_id                                 AS support_rep_id,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  _CHANGE_TIMESTAMP                                    AS _loaded_at,
  ts_ms                                                AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.customer_raw`,
  NULL
);
