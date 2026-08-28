-- =============================================================================
-- Gold View: v_fct_invoice — Invoices with resolved customer names
-- =============================================================================
-- Joins fact invoices with the current customer dimension for readability.
-- =============================================================================

SELECT
  f.invoice_id,
  f.customer_key,
  c.customer_id,
  c.first_name    AS customer_first_name,
  c.last_name     AS customer_last_name,
  c.company       AS customer_company,
  f.invoice_date,
  f.billing_address,
  f.billing_city,
  f.billing_state,
  f.billing_country,
  f.billing_postal_code,
  f.total,
  f._loaded_at,
  f._source_ts_ms
FROM `${PROJECT_ID}.gold.fct_invoice` f
LEFT JOIN `${PROJECT_ID}.gold.v_dim_customer` c
  ON f.customer_key = c.surrogate_key;
