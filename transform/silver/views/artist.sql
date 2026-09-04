-- =============================================================================
-- Silver View: artist — Current-state artist records
-- =============================================================================
-- View on Bronze that extracts the latest state per artist using
-- QUALIFY ROW_NUMBER(). No CQ needed since artists change rarely.
--
-- Used by: infra/bigquery_views.tf (Terraform manages the view lifecycle)
-- =============================================================================

SELECT
  after.artist_id                                      AS artist_id,
  after.name                                           AS name,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  ts_ms                                                AS _source_ts_ms
FROM `${PROJECT_ID}.bronze.artist_raw`
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY after.artist_id
  ORDER BY ts_ms DESC
) = 1;
