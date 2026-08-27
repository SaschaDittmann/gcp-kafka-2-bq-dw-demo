-- =============================================================================
-- Continuous Query: Bronze → Silver — playlist
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.playlist` (
  playlist_id, name, is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.playlist_id') AS INT64)  AS playlist_id,
  JSON_VALUE(after, '$.name')                        AS name,
  IF(op = 'd', TRUE, FALSE)                          AS is_deleted,
  _CHANGE_TIMESTAMP                                   AS _loaded_at,
  ts_ms                                               AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.playlist_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);

