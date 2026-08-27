-- =============================================================================
-- Continuous Query: Bronze → Silver — track
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.track` (
  track_id, name, album_id, media_type_id, genre_id,
  composer, milliseconds, bytes, unit_price,
  is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.track_id') AS INT64)       AS track_id,
  JSON_VALUE(after, '$.name')                          AS name,
  CAST(JSON_VALUE(after, '$.album_id') AS INT64)       AS album_id,
  CAST(JSON_VALUE(after, '$.media_type_id') AS INT64)  AS media_type_id,
  CAST(JSON_VALUE(after, '$.genre_id') AS INT64)       AS genre_id,
  JSON_VALUE(after, '$.composer')                      AS composer,
  CAST(JSON_VALUE(after, '$.milliseconds') AS INT64)   AS milliseconds,
  CAST(JSON_VALUE(after, '$.bytes') AS INT64)          AS bytes,
  CAST(JSON_VALUE(after, '$.unit_price') AS FLOAT64)   AS unit_price,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  _CHANGE_TIMESTAMP                                    AS _loaded_at,
  ts_ms                                                AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.track_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
