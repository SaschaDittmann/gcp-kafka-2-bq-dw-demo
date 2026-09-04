-- =============================================================================
-- Silver View: genre — Current-state genre records
-- =============================================================================
-- Used by: infra/bigquery_views.tf (Terraform manages the view lifecycle)
-- =============================================================================

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
