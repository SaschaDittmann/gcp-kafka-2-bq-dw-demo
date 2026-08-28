-- =============================================================================
-- Silver View: genre — Current-state genre records
-- =============================================================================
-- Deploy: bq query --use_legacy_sql=false < transform/silver_genre.sql
-- =============================================================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.silver.genre` AS
SELECT
  after.genre_id                                       AS genre_id,
  after.name                                           AS name,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  ts_ms                                                AS _source_ts_ms
FROM `${PROJECT_ID}.bronze.genre_raw`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY after.genre_id
  ORDER BY ts_ms DESC
) = 1;
