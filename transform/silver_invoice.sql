-- =============================================================================
-- Continuous Query: Bronze → Silver — invoice
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.invoice` (
  invoice_id, customer_id, invoice_date,
  billing_address, billing_city, billing_state,
  billing_country, billing_postal_code, total,
  is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.invoice_id') AS INT64)        AS invoice_id,
  CAST(JSON_VALUE(after, '$.customer_id') AS INT64)       AS customer_id,
  TIMESTAMP_MILLIS(CAST(JSON_VALUE(after, '$.invoice_date') AS INT64)) AS invoice_date,
  JSON_VALUE(after, '$.billing_address')                  AS billing_address,
  JSON_VALUE(after, '$.billing_city')                     AS billing_city,
  JSON_VALUE(after, '$.billing_state')                    AS billing_state,
  JSON_VALUE(after, '$.billing_country')                  AS billing_country,
  JSON_VALUE(after, '$.billing_postal_code')              AS billing_postal_code,
  CAST(JSON_VALUE(after, '$.total') AS FLOAT64)           AS total,
  IF(op = 'd', TRUE, FALSE)                              AS is_deleted,
  _CHANGE_TIMESTAMP                                       AS _loaded_at,
  ts_ms                                                   AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.invoice_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
