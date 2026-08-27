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
