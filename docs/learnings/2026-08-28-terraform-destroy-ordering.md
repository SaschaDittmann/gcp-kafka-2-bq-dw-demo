---
date: 2026-08-28
topic: Terraform destroy dependency ordering
---

# Terraform Destroy Fails Due to Missing Dependencies

## The Problem / Context

Running `terraform destroy` on the CDC pipeline failed with two errors:
1. **Database deletion blocked**: `database "chinook" is used by an active logical replication slot` — the CDC connector creates a replication slot that prevents `DROP DATABASE`.
2. **User deletion blocked**: `role cannot be dropped because some objects depend on it` — the Managed Kafka IAM user owns objects in the chinook database (created by the connector at runtime).

These resources are created by Terraform but have **runtime dependencies** that Terraform doesn't know about. Without explicit ordering, TF tries to delete them in parallel with the connectors.

## The Solution / Learning

Add `depends_on` to enforce a **destroy chain**:

```
1. CDC connector destroyed    → releases replication slot
2. chinook database destroyed → drops all owned objects
3. IAM user destroyed         → no more object dependencies
```

In Terraform:

```hcl
# cloudsql.tf
resource "google_sql_database" "chinook" {
  # ...
  depends_on = [google_managed_kafka_connector.cdc_source]
}

# iam.tf
resource "google_sql_user" "managed_kafka_iam" {
  # ...
  depends_on = [google_sql_database.chinook]
}
```

**Key insight**: `depends_on` affects **both** create and destroy ordering. During create, it ensures the dependency is built first. During destroy, it ensures the dependent is destroyed **before** the dependency. Think about what runtime state (replication slots, object ownership, connections) your resources create outside of Terraform's knowledge.

