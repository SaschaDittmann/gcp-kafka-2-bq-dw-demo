-- =============================================================================
-- Continuous Query: Bronze → Silver — playlist_track
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.playlist_track` (
  playlist_id, track_id, is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.playlist_id') AS INT64)  AS playlist_id,
  CAST(JSON_VALUE(after, '$.track_id') AS INT64)     AS track_id,
  IF(op = 'd', TRUE, FALSE)                          AS is_deleted,
  _CHANGE_TIMESTAMP                                   AS _loaded_at,
  ts_ms                                               AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.playlist_track_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
