-- =============================================================================
-- Silver View: album — Current-state album records
-- =============================================================================
-- Used by: infra/bigquery_views.tf (Terraform manages the view lifecycle)
-- =============================================================================

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
