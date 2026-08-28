-- =============================================================================
-- Silver View: playlist_track — Current-state playlist-track associations
-- =============================================================================
-- Deploy: bq query --use_legacy_sql=false < transform/silver_playlist_track.sql
-- =============================================================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.silver.playlist_track` AS
SELECT
  after.playlist_id                                    AS playlist_id,
  after.track_id                                       AS track_id,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  ts_ms                                                AS _source_ts_ms
FROM `${PROJECT_ID}.bronze.playlist_track_raw`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY after.playlist_id, after.track_id
  ORDER BY ts_ms DESC
) = 1;
