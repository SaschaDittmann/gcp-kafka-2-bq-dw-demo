-- =============================================================================
-- Silver View: playlist — Current-state playlist records
-- =============================================================================
-- Used by: infra/bigquery_views.tf (Terraform manages the view lifecycle)
-- =============================================================================

SELECT
  after.playlist_id                                    AS playlist_id,
  after.name                                           AS name,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  ts_ms                                                AS _source_ts_ms
FROM `${PROJECT_ID}.bronze.playlist_raw`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY after.playlist_id
  ORDER BY ts_ms DESC
) = 1;
