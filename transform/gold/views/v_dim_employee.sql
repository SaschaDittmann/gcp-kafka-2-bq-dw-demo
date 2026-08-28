-- =============================================================================
-- Gold View: v_dim_employee — Current-state employee dimension
-- =============================================================================
-- Shows only the latest active version of each employee (SCD Type 2).
-- =============================================================================

SELECT
  surrogate_key,
  natural_key   AS employee_id,
  first_name,
  last_name,
  title,
  reports_to,
  birth_date,
  hire_date,
  address,
  city,
  state,
  country,
  postal_code,
  email,
  valid_from,
  _loaded_at,
  _source_ts_ms
FROM `${PROJECT_ID}.gold.dim_employee`
WHERE is_active = TRUE
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY natural_key
  ORDER BY valid_from DESC
) = 1;
