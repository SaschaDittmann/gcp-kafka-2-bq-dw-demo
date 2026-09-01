---
date: 2026-08-31
topic: Fresh deployment timing issues
---

# Fresh Deployment Timing Issues

## Problem 1: Cloud SQL IAM Auth Propagation

On fresh deployments, the CDC source connector fails with:

```
FATAL: password authentication failed for user "service-...@gcp-sa-managedkafka.iam"
```

**Root cause:** The Cloud SQL IAM user (`google_sql_user.managed_kafka_iam`) is created moments before the connector tries to connect. IAM authentication takes up to 60 seconds to propagate.

**Fix:** Add a `time_sleep` resource (60s) between IAM user creation and connector creation:

```hcl
resource "time_sleep" "iam_propagation" {
  depends_on      = [google_sql_user.managed_kafka_iam]
  create_duration = "60s"
}

resource "google_managed_kafka_connector" "cdc_source" {
  depends_on = [time_sleep.iam_propagation, google_sql_database.chinook]
}
```

Requires the `hashicorp/time` provider.

## Problem 2: Gold SQ Lookback Window Misses Initial Data

Gold scheduled queries use a 10-minute lookback filter:

```sql
WHERE _loaded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
```

On fresh deployments, by the time the SQs first run, Silver data may already be older than 10 minutes — resulting in empty Gold tables.

**Fix:** `deploy.sh` step 8 runs each Gold SQ once without the lookback filter to backfill initial data. The `TIMESTAMP_SUB` line is stripped via `grep -v` before executing.
