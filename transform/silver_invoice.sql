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
  after.invoice_id                                     AS invoice_id,
  after.customer_id                                    AS customer_id,
  after.invoice_date                                   AS invoice_date,
  after.billing_address                                AS billing_address,
  after.billing_city                                   AS billing_city,
  after.billing_state                                  AS billing_state,
  after.billing_country                                AS billing_country,
  after.billing_postal_code                            AS billing_postal_code,
  after.total                                          AS total,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  _CHANGE_TIMESTAMP                                    AS _loaded_at,
  ts_ms                                                AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.invoice_raw`,
  NULL
);
