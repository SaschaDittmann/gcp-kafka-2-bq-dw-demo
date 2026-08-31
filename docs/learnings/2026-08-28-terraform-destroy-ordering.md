---
date: 2026-08-28
topic: Terraform destroy dependency ordering
---

# Terraform Destroy Fails Due to Runtime Dependencies

## The Problem / Context

Running `terraform destroy` on the CDC pipeline failed with two errors:
1. **Database deletion blocked**: `database "chinook" is used by an active logical replication slot` — the CDC connector creates a replication slot that prevents `DROP DATABASE`.
2. **User deletion blocked**: `role cannot be dropped because some objects depend on it` — the Managed Kafka IAM user owns objects in the chinook database (created by the connector at runtime).

These resources are created by Terraform but have **runtime dependencies** that Terraform doesn't know about. Without explicit ordering, TF tries to delete them in parallel with the connectors.

## The Solution / Learning

### `depends_on` Does NOT Work Here

The initial fix attempted was adding `depends_on` to reverse the destroy order:

```hcl
# ❌ BROKEN — this reverses the CREATE order too!
resource "google_sql_database" "chinook" {
  depends_on = [google_managed_kafka_connector.cdc_source]
}
```

**`depends_on` applies the same ordering to both create and destroy.** This means during create, Terraform tries to create the connector *before* the database — which fails because the connector needs the database to connect to.

### Correct Approach: Teardown Script

Since create and destroy need **opposite** orderings, Terraform alone cannot solve this. Use a **teardown script** that runs before `terraform destroy`:

```bash
# scripts/teardown.sh handles:
# 1. Cancel running CQs
# 2. Drop the replication slot (pg_drop_replication_slot)
# 3. Drop the publication
```

**Workflow:**
```
./scripts/teardown.sh   # Clean up runtime state
terraform destroy       # Now safe to destroy all resources
```

**Key insight:** When resources create runtime state that Terraform doesn't manage (replication slots, object ownership, connections), cleanup must happen in a script before `terraform destroy`, not via `depends_on`.

