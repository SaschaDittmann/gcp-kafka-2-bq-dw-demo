-- =============================================================================
-- Continuous Query: Bronze → Silver — album
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.album` (
  album_id, title, artist_id, is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.album_id') AS INT64)   AS album_id,
  JSON_VALUE(after, '$.title')                     AS title,
  CAST(JSON_VALUE(after, '$.artist_id') AS INT64)  AS artist_id,
  IF(op = 'd', TRUE, FALSE)                        AS is_deleted,
  _CHANGE_TIMESTAMP                                 AS _loaded_at,
  ts_ms                                             AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.album_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
