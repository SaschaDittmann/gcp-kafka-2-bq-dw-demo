---
date: 2026-08-27
topic: Managed Kafka Connect — Cloud SQL Source Connector
---

# Managed Kafka Connect: Cloud SQL Source Connector Setup

## The Problem / Context

Setting up a Cloud SQL for PostgreSQL CDC source connector on Google Managed Kafka Connect. The connector failed with a persistent `403 Forbidden` error from the Cloud SQL Admin API `connectSettings` endpoint, even after granting `roles/owner` to the Managed Kafka service agent SA.

## The Solution / Learning

### 1. `driver.ipTypes` must be `PRIVATE,PUBLIC` (not just `PRIVATE`)

The Cloud SQL JDBC Socket Factory requires `driver.ipTypes=PRIVATE,PUBLIC` even when the Cloud SQL instance only has a private IP. Using just `PRIVATE` causes the socket factory to use a code path that triggers a 403 from the `connectSettings` API. The GCP Console wizard defaults to `PRIVATE,PUBLIC` — match that.

```yaml
# ❌ Fails with 403
driver.ipTypes: PRIVATE

# ✅ Works
driver.ipTypes: PRIVATE,PUBLIC
```

### 2. All connectors use the Managed Kafka SA — not a custom SA

The managed Connect cluster uses `service-PROJECT_NUMBER@gcp-sa-managedkafka.iam.gserviceaccount.com` for ALL connector API calls (source AND sinks). A custom service account created via `google_service_account` is NOT used by the managed service. Grant ALL needed roles to the Managed Kafka SA:

- `roles/cloudsql.client` + `roles/cloudsql.instanceUser` + `roles/cloudsql.viewer` (source)
- `roles/bigquery.dataEditor` + `roles/bigquery.jobUser` (BigQuery sink)
- `roles/storage.objectCreator` (GCS archive sink)

### 3. Terraform provider bug: `task_restart_policy`

GCP auto-sets `task_restart_policy` on connectors. On subsequent `terraform apply`, the provider tries to reconcile this field and fails with `update_mask must contain "configs" or "*"`. Fix with lifecycle ignore on ALL connector resources:

```hcl
lifecycle {
  ignore_changes = [task_restart_policy]
}
```

### 4. Cloud SQL IAM user naming

The `.gserviceaccount.com` suffix is truncated for the PostgreSQL username:
```
service-PROJECT_NUMBER@gcp-sa-managedkafka.iam
```

### 5. Database prerequisites (via `gcloud sql import sql`)

Before the connector can start CDC, the database needs:
- `cloudsql.logical_decoding = on` (database flag)
- `cloudsql.iam_authentication = on` (database flag)
- `ALTER USER "service-PROJECT_NUMBER@gcp-sa-managedkafka.iam" WITH REPLICATION;`
- `GRANT SELECT ON ALL TABLES IN SCHEMA public TO "service-PROJECT_NUMBER@gcp-sa-managedkafka.iam";`
- `CREATE PUBLICATION debezium_publication FOR ALL TABLES;`
- Logical replication slot created via `pg_create_logical_replication_slot()`

## Debugging the BQ Sink Pipeline (2026-08-28)

### Root Cause: `value.converter.schemas.enable`
- The WePay BigQuery Sink Connector REQUIRES `value.converter.schemas.enable=true` on BOTH the CDC source AND the sink
- Without it, the connector treats all records as 'tombstones' and throws `Could not convert to BigQuery schema with a batch of tombstone records`
- The Google Cloud Console UI default for CDC source has `schemas.enable=true` — always match this
- With `schemas.enable=true`, the BQ connector auto-creates tables with proper RECORD types for `before`, `after`, and `source` fields

### Bronze Table Schema: RECORD vs STRING
- With `schemas.enable=true`, bronze tables use RECORD types (e.g., `after.customer_id` is INTEGER, not JSON string)
- CQ transforms must use struct access (`after.field`) instead of `JSON_VALUE(after, '$.field')`
- Date/timestamp fields are already TIMESTAMP type — no need for `TIMESTAMP_MILLIS()`

### Connect Offsets and Topic Prefix
- Debezium source connector offsets are keyed by `topic.prefix`, NOT by connector name
- Changing connector name alone does NOT trigger a new snapshot
- To force a fresh snapshot: change `topic.prefix` (e.g., from `chinook` to `cdc`) to get new offset keys
- The Connect internal topics (configs, offsets, status) should NEVER be deleted — it corrupts the Connect worker state permanently
- If Connect worker gets stuck with 'Timeout while reading log to end for topic connect-offsets-...', the Connect cluster must be recreated

### Managed Kafka Connect Gotchas
- Topics must be pre-created; auto.create.topics.enable may be disabled
- `consumer.override.auto.offset.reset` may not be supported by the managed service
- The managed service auto-recreates deleted internal topics but the worker may not recover
- `task_restart_policy` is auto-set by GCP; use `lifecycle { ignore_changes }` in Terraform

## BigQuery Reservation & Gold Layer (2026-08-28)

### BigQuery Enterprise Reservation for CQs
- CQs require BigQuery Enterprise edition with slot reservations
- Use autoscaling reservation: `slot_capacity = 0` + `autoscale { max_slots = 100 }` — no upfront commitment
- The reservation assignment must use `job_type = "CONTINUOUS"` (not `QUERY`) — can't mix both in one reservation
- `FLEX_FLAT_RATE` plan is sunset — use autoscale instead of capacity commitments

### Managed Apache Iceberg Limitations
- Iceberg tables (BigLake with `biglake_configuration`) do NOT support CQs as destinations: 'BigQuery tables for Apache Iceberg do not support as destinations for continuous queries'
- Iceberg tables do NOT support correlated subqueries in INSERT statements — rewrite using JOINs
- Solution: Use BigQuery Data Transfer scheduled queries (every 5 min) instead of CQs for Silver → Gold

### Silver Layer: CQ `APPENDS()` Start Timestamp
- `APPENDS(TABLE, CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE)` only captures rows from the last 10 minutes
- On fresh deploy, initial CDC snapshot data is missed because it loads before CQs start
- Fix: Use `APPENDS(TABLE, NULL)` — processes ALL existing data + streams new data
- CQs maintain internal watermarks, so they won't reprocess on restart

### Bronze Table Schema (Auto-Created)
- Auto-created bronze tables have NO `_loaded_at` column (it was a Terraform-managed addition)
- Actual columns: `before` (RECORD), `after` (RECORD), `source` (RECORD), `transaction` (RECORD), `op` (STRING), `ts_ms`, `ts_us`, `ts_ns` (INTEGER)
- Silver views must use `ts_ms` for ordering, not `_loaded_at`

### Gold Current-State Views
- Created 5 views for easy querying of current state: `v_dim_customer`, `v_dim_employee`, `v_dim_track`, `v_fct_invoice`, `v_fct_invoice_line`
- Dimension views: filter `WHERE is_active = TRUE` + `QUALIFY ROW_NUMBER()` for latest SCD2 version
- Fact views: JOIN with dim views to resolve surrogate keys to human-readable names
