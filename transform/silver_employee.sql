-- =============================================================================
-- Continuous Query: Bronze → Silver — employee
-- =============================================================================

INSERT INTO `${PROJECT_ID}.silver.employee` (
  employee_id, last_name, first_name, title, reports_to,
  birth_date, hire_date, address, city, state, country,
  postal_code, email, is_deleted, _loaded_at, _source_ts_ms
)
SELECT
  CAST(JSON_VALUE(after, '$.employee_id') AS INT64)  AS employee_id,
  JSON_VALUE(after, '$.last_name')                   AS last_name,
  JSON_VALUE(after, '$.first_name')                  AS first_name,
  JSON_VALUE(after, '$.title')                       AS title,
  CAST(JSON_VALUE(after, '$.reports_to') AS INT64)   AS reports_to,
  TIMESTAMP_MILLIS(CAST(JSON_VALUE(after, '$.birth_date') AS INT64)) AS birth_date,
  TIMESTAMP_MILLIS(CAST(JSON_VALUE(after, '$.hire_date') AS INT64))  AS hire_date,
  JSON_VALUE(after, '$.address')                     AS address,
  JSON_VALUE(after, '$.city')                        AS city,
  JSON_VALUE(after, '$.state')                       AS state,
  JSON_VALUE(after, '$.country')                     AS country,
  JSON_VALUE(after, '$.postal_code')                 AS postal_code,
  JSON_VALUE(after, '$.email')                       AS email,
  IF(op = 'd', TRUE, FALSE)                          AS is_deleted,
  _CHANGE_TIMESTAMP                                   AS _loaded_at,
  ts_ms                                               AS _source_ts_ms
FROM APPENDS(
  TABLE `${PROJECT_ID}.bronze.employee_raw`,
  CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
);
