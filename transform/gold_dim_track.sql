-- =============================================================================
-- Continuous Query: Silver → Gold — dim_track (SCD Type 2, denormalized)
-- =============================================================================
-- Denormalizes track with album, artist, genre, and media_type lookups.
--
-- NOTE: BigQuery CQs do NOT support stream-to-static JOINs. This CQ
-- streams track changes and performs lookups against Silver dimension
-- tables using scalar subqueries (which are supported in CQ context
-- as correlated scalar expressions on static tables).
--
-- If scalar subqueries are not supported in CQ, this script should be
-- run as a scheduled query (micro-batch every 1-5 minutes) instead.
--
-- Run with: bq query --use_legacy_sql=false --continuous=true < transform/gold_dim_track.sql
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
  -- Denormalization via scalar subqueries on Silver tables
  (SELECT a.title FROM `${PROJECT_ID}.silver.album` a
   WHERE a.album_id = t.album_id AND a.is_deleted = FALSE
   ORDER BY a._loaded_at DESC LIMIT 1)                     AS album_title,
  (SELECT ar.name FROM `${PROJECT_ID}.silver.artist` ar
   INNER JOIN `${PROJECT_ID}.silver.album` al
     ON ar.artist_id = al.artist_id AND al.is_deleted = FALSE
   WHERE al.album_id = t.album_id AND ar.is_deleted = FALSE
   ORDER BY ar._loaded_at DESC LIMIT 1)                    AS artist_name,
  (SELECT g.name FROM `${PROJECT_ID}.silver.genre` g
   WHERE g.genre_id = t.genre_id AND g.is_deleted = FALSE
   ORDER BY g._loaded_at DESC LIMIT 1)                     AS genre_name,
  (SELECT mt.name FROM `${PROJECT_ID}.silver.media_type` mt
   WHERE mt.media_type_id = t.media_type_id AND mt.is_deleted = FALSE
   ORDER BY mt._loaded_at DESC LIMIT 1)                    AS media_type_name,
  t.composer,
  t.milliseconds,
  t.bytes,
  t.unit_price,
  t._loaded_at           AS valid_from,
  CAST(NULL AS TIMESTAMP) AS valid_to,
  TRUE                   AS is_active,
  t._loaded_at,
  t._source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.silver.track`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
) AS t
WHERE t.is_deleted = FALSE;

