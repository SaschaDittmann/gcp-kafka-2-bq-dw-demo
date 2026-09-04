-- =============================================================================
-- Continuous Query: Bronze → Silver — track
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.track` (
  track_id, name, album_id, media_type_id, genre_id,
  composer, milliseconds, bytes, unit_price,
  is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  after.track_id                                       AS track_id,
  after.name                                           AS name,
  after.album_id                                       AS album_id,
  after.media_type_id                                  AS media_type_id,
  after.genre_id                                       AS genre_id,
  after.composer                                       AS composer,
  after.milliseconds                                   AS milliseconds,
  after.bytes                                          AS bytes,
  after.unit_price                                     AS unit_price,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  _CHANGE_TIMESTAMP                                    AS _loaded_at,
  ts_ms                                                AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.track_raw`,
  NULL
);
