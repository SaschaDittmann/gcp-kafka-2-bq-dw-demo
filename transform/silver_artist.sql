-- =============================================================================
-- Continuous Query: Bronze → Silver — artist
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.artist` (
  artist_id, name, is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.artist_id') AS INT64)  AS artist_id,
  JSON_VALUE(after, '$.name')                      AS name,
  IF(op = 'd', TRUE, FALSE)                        AS is_deleted,
  _CHANGE_TIMESTAMP                                 AS _loaded_at,
  ts_ms                                             AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.artist_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
