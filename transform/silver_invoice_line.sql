-- =============================================================================
-- Continuous Query: Bronze → Silver — invoice_line
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.invoice_line` (
  invoice_line_id, invoice_id, track_id,
  unit_price, quantity,
  is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.invoice_line_id') AS INT64)  AS invoice_line_id,
  CAST(JSON_VALUE(after, '$.invoice_id') AS INT64)       AS invoice_id,
  CAST(JSON_VALUE(after, '$.track_id') AS INT64)         AS track_id,
  CAST(JSON_VALUE(after, '$.unit_price') AS FLOAT64)     AS unit_price,
  CAST(JSON_VALUE(after, '$.quantity') AS INT64)          AS quantity,
  IF(op = 'd', TRUE, FALSE)                             AS is_deleted,
  _CHANGE_TIMESTAMP                                      AS _loaded_at,
  ts_ms                                                  AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.invoice_line_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
