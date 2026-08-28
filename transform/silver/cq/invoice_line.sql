-- =============================================================================
-- Continuous Query: Bronze → Silver — invoice_line
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.invoice_line` (
  invoice_line_id, invoice_id, track_id,
  unit_price, quantity,
  is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  after.invoice_line_id                                AS invoice_line_id,
  after.invoice_id                                     AS invoice_id,
  after.track_id                                       AS track_id,
  after.unit_price                                     AS unit_price,
  after.quantity                                       AS quantity,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  _CHANGE_TIMESTAMP                                    AS _loaded_at,
  ts_ms                                                AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.invoice_line_raw`,
  NULL
);
