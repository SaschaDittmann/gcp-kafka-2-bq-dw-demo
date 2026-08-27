---
date: 2026-08-27
topic: Cloud SQL init via gcloud sql import
---

# Cloud SQL Database Initialization Without VPC Access or psql

## The Problem / Context
Cloud SQL instances with private-IP-only networking cannot be reached from local machines or CI environments. The initial `init_db.sh` script used `psql` directly, which required either VPC access (bastion host, Auth Proxy) or the `cloud-sql-proxy` binary installed locally. Both approaches added friction to the setup.

## The Solution / Learning
Use `gcloud sql import sql` for all database initialization steps:

1. **Schema and seed data**: Upload SQL files to a GCS bucket, then import via `gcloud sql import sql --database=chinook --user=admin`.
2. **Replication setup** (user, slot, publication): Write inline SQL to a temp file, upload to GCS, import the same way.
3. **Replication slot creation** requires the `REPLICATION` role — the admin user doesn't have it. Run that step with `--user=debezium` (created with `REPLICATION` role in a prior step).

Key implementation details:
- The `run_sql()` helper creates a temp file, uploads to GCS, imports, then cleans up.
- Capture the import exit code **before** the cleanup command (`gcloud storage rm`), otherwise the cleanup masks failures.
- The Cloud SQL service account needs `roles/storage.objectViewer` on the GCS bucket.
