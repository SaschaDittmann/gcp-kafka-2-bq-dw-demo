-- =============================================================================
-- Gold View: v_dim_customer — Current-state customer dimension
-- =============================================================================
-- Shows only the latest active version of each customer (SCD Type 2).
--
-- Used by: infra/bigquery_views.tf (Terraform manages the view lifecycle)
-- =============================================================================

SELECT
  surrogate_key,
  natural_key   AS customer_id,
  first_name,
  last_name,
  company,
  address,
  city,
  state,
  country,
  postal_code,
  email,
  support_rep_id,
  valid_from,
  _loaded_at,
  _source_ts_ms
FROM `${PROJECT_ID}.gold.dim_customer`
WHERE is_active = TRUE
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY natural_key
  ORDER BY valid_from DESC
) = 1;
