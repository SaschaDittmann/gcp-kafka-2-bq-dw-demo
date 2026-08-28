-- =============================================================================
-- Silver View: media_type — Current-state media type records
-- =============================================================================
-- Deploy: bq query --use_legacy_sql=false < transform/silver_media_type.sql
-- =============================================================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.silver.media_type` AS
SELECT
  after.media_type_id                                  AS media_type_id,
  after.name                                           AS name,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  ts_ms                                                AS _source_ts_ms
FROM `${PROJECT_ID}.bronze.media_type_raw`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY after.media_type_id
  ORDER BY ts_ms DESC
) = 1;
