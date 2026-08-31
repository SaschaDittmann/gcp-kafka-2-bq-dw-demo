---
date: 2026-08-28
topic: BigQuery Sink Connector pre-created tables
---

# Pre-Creating Bronze Tables for BigQuery Sink Connector

## The Problem / Context

The WePay BigQuery Sink Connector (`com.wepay.kafka.connect.bigquery.BigQuerySinkConnector`) with `autoCreateTables=true` auto-creates Bronze tables when data first arrives. This caused issues with Terraform:

1. **Views couldn't be created** — Silver views reference Bronze tables that don't exist until the connector creates them, so `terraform apply` before data flows would fail.
2. **Views destroyed on apply** — If views were created outside Terraform and later added to TF config, `terraform apply` would destroy and recreate them, causing downtime.

## The Solution / Learning

### Pre-create tables in Terraform that match the connector's schema exactly

The connector will **use existing tables** if their schema matches what it would auto-create. Key requirements:

1. **DAY partitioning is required** — The connector creates tables with ingestion-time DAY partitioning. The TF definition **must** include `time_partitioning { type = "DAY" }` or `terraform apply` fails with: `"Cannot change partitioned table to non partitioned table"`.

2. **Schema must match exactly** — The Debezium envelope has `before`, `after` (RECORD type with per-table fields), `source` (RECORD), `transaction` (RECORD), `op`, and `ts_ms`. The `before`/`after` RECORD fields must list the exact columns for each entity.

3. **Use `for_each` with a locals map** — Define entity-specific fields in a `locals` block and loop with `for_each` to avoid repetitive table definitions. Shared fields (`source`, `transaction`, `op`, `ts_ms`) go in a common local.

### Use `fileset()` for views

With Bronze tables pre-created in TF, views can also be TF-managed. Using `fileset()` + `for_each` to auto-discover SQL files from `transform/silver/views/` and `transform/gold/views/` means adding a new view is just dropping a `.sql` file — no TF config changes needed.

