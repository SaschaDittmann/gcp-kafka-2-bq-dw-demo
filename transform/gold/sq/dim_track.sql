-- =============================================================================
-- Scheduled Query: Silver → Gold — dim_track (SCD Type 2, denormalized)
-- =============================================================================
-- Denormalizes track with album, artist, genre, and media_type via JOINs.
-- Runs every 5 minutes.
--
-- NOTE: Iceberg tables do not support correlated subqueries in INSERT.
-- Use JOINs instead.
-- =============================================================================

INSERT INTO `${PROJECT_ID}.gold.dim_track` (
  surrogate_key, natural_key,
  track_name, album_title, artist_name,
  genre_name, media_type_name,
  composer, milliseconds, bytes, unit_price,
  valid_from, valid_to, is_active,
  _loaded_at, _source_ts_ms
)
SELECT
  GENERATE_UUID()        AS surrogate_key,
  t.track_id             AS natural_key,
  t.name                 AS track_name,
  al.title               AS album_title,
  ar.name                AS artist_name,
  g.name                 AS genre_name,
  mt.name                AS media_type_name,
  t.composer,
  t.milliseconds,
  t.bytes,
  t.unit_price,
  t._loaded_at           AS valid_from,
  CAST(NULL AS TIMESTAMP) AS valid_to,
  TRUE                   AS is_active,
  t._loaded_at,
  t._source_ts_ms
FROM `${PROJECT_ID}.silver.track` AS t
LEFT JOIN `${PROJECT_ID}.silver.album` al
  ON t.album_id = al.album_id AND al.is_deleted = FALSE
LEFT JOIN `${PROJECT_ID}.silver.artist` ar
  ON al.artist_id = ar.artist_id AND ar.is_deleted = FALSE
LEFT JOIN `${PROJECT_ID}.silver.genre` g
  ON t.genre_id = g.genre_id AND g.is_deleted = FALSE
LEFT JOIN `${PROJECT_ID}.silver.media_type` mt
  ON t.media_type_id = mt.media_type_id AND mt.is_deleted = FALSE
WHERE t.is_deleted = FALSE
  AND t._loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);
