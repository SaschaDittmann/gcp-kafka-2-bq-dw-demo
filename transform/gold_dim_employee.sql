-- =============================================================================
-- Scheduled Query: Silver → Gold — dim_employee (SCD Type 2)
-- =============================================================================
-- Runs every 5 minutes.
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
FROM `${PROJECT_ID}.silver.employee`
WHERE is_deleted = FALSE
  AND _loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);
