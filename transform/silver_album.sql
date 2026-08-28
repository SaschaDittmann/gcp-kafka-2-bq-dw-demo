-- =============================================================================
-- Silver View: album — Current-state album records
-- =============================================================================
-- Deploy: bq query --use_legacy_sql=false < transform/silver_album.sql
-- =============================================================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.silver.album` AS
SELECT
  after.album_id                                       AS album_id,
  after.title                                          AS title,
  after.artist_id                                      AS artist_id,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  ts_ms                                                AS _source_ts_ms
FROM `${PROJECT_ID}.bronze.album_raw`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY after.album_id
  ORDER BY ts_ms DESC
) = 1;
