-- =============================================================================
-- Continuous Query: Bronze → Silver — employee
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.employee` (
  employee_id, last_name, first_name, title, reports_to,
  birth_date, hire_date, address, city, state, country,
  postal_code, email, is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  after.employee_id                                    AS employee_id,
  after.last_name                                      AS last_name,
  after.first_name                                     AS first_name,
  after.title                                          AS title,
  after.reports_to                                     AS reports_to,
  after.birth_date                                     AS birth_date,
  after.hire_date                                      AS hire_date,
  after.address                                        AS address,
  after.city                                           AS city,
  after.state                                          AS state,
  after.country                                        AS country,
  after.postal_code                                    AS postal_code,
  after.email                                          AS email,
  IF(op = 'd', TRUE, FALSE)                           AS is_deleted,
  _CHANGE_TIMESTAMP                                    AS _loaded_at,
  ts_ms                                                AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.employee_raw`,
  NULL
);
