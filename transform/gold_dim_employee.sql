-- =============================================================================
-- Continuous Query: Silver → Gold — dim_employee (SCD Type 2)
-- =============================================================================

INSERT INTO `${PROJECT_ID}.gold.dim_employee` (
  surrogate_key, natural_key,
  first_name, last_name, title, reports_to,
  birth_date, hire_date, address, city,
  state, country, postal_code, email,
  valid_from, valid_to, is_active,
  _loaded_at, _source_ts_ms
)
SELECT
  GENERATE_UUID()        AS surrogate_key,
  employee_id            AS natural_key,
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
  _loaded_at             AS valid_from,
  CAST(NULL AS TIMESTAMP) AS valid_to,
  TRUE                   AS is_active,
  _loaded_at,
  _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.silver.employee`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
)
WHERE is_deleted = FALSE;
