-- =============================================================================
-- Silver View: media_type — Current-state media type records
-- =============================================================================
-- Used by: infra/bigquery_views.tf (Terraform manages the view lifecycle)
-- =============================================================================

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
