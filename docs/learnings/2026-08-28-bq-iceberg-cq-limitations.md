---
date: 2026-08-28
topic: BigQuery Iceberg and Continuous Query limitations
---

# BigQuery Iceberg Tables and Continuous Query Limitations

## The Problem / Context

When building the Gold layer of the CDC pipeline, the initial plan was to use BigQuery Continuous Queries (CQs) to write into Iceberg tables (for open-format portability). Several constraints were discovered through trial and error.

## The Solution / Learning

### CQs Cannot Write to Iceberg Tables

BigQuery Continuous Queries do not support Iceberg tables as targets. CQs can only write to standard BigQuery managed-storage tables. If you need Iceberg in Gold, you must use **Scheduled Queries** instead (e.g., every 5 minutes via `google_bigquery_data_transfer_config`).

### Correlated Subqueries in Iceberg INSERT

Iceberg tables do not support correlated subqueries in `INSERT ... SELECT` statements. For SCD Type 2 patterns that need to look up active dimension records, use `JOIN` syntax instead of `WHERE EXISTS (SELECT ...)`.

### CONTINUOUS vs QUERY Reservation Assignments

BigQuery reservation assignments for `CONTINUOUS` and `QUERY` job types **cannot coexist** in the same reservation. The solution is to create separate reservations: one for CQs (Silver layer) and one for scheduled queries (Gold layer), or use on-demand for scheduled queries.

### `APPENDS(TABLE t, NULL)` Starts from Beginning

The `APPENDS()` function with `NULL` as the second argument starts reading from the beginning of the table, not from the current point. This is useful for CQs that need to process all existing data on first start.

### FLEX / FLEX_FLAT_RATE Capacity Types Are Sunset

When creating BigQuery reservations, `FLEX_FLAT_RATE` and `FLEX` edition/capacity types return errors. Use `ENTERPRISE` edition with `autoscale { max_slots = N }` instead.

