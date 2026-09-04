-- =============================================================================
-- Gold View: v_dim_track — Current-state track dimension (denormalized)
-- =============================================================================
-- Shows only the latest active version of each track (SCD Type 2).
-- Includes denormalized album, artist, genre, and media type names.
-- =============================================================================

SELECT
  surrogate_key,
  natural_key   AS track_id,
  track_name,
  album_title,
  artist_name,
  genre_name,
  media_type_name,
  composer,
  milliseconds,
  bytes,
  unit_price,
  valid_from,
  _loaded_at,
  _source_ts_ms
FROM `${PROJECT_ID}.gold.dim_track`
WHERE is_active = TRUE
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY natural_key
  ORDER BY valid_from DESC
) = 1;
