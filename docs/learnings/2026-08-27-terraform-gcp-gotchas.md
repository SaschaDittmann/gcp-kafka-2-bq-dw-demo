---
date: 2026-08-27
topic: Terraform GCP resource gotchas
---

# Terraform GCP Provider Resource Gotchas

## The Problem / Context
Several GCP Terraform resources have undocumented limitations or surprising behaviors that caused `terraform plan` or `terraform apply` errors during infrastructure setup.

## The Solution / Learning

### 1. `google_vpc_access_connector` does NOT support `labels`
The `google_vpc_access_connector` resource silently ignores or errors on the `labels` argument, even though other networking resources like `google_compute_global_address` do support it. Remove `labels` from VPC connectors.

### 2. Cloud SQL instance names have a 7-day reuse lockout
After `terraform destroy`, the Cloud SQL instance name cannot be reused for 7 days. Use a `random_id` suffix (e.g., `cdc-demo-pg-${random_id.db_suffix.hex}`) to avoid collisions on recreate.

### 3. Cloud SQL PSA dependency is mandatory
`google_sql_database_instance` with private IP **must** have `depends_on = [google_service_networking_connection.psa]`. Without it, Terraform may try to create the instance before the VPC peering is ready, causing a cryptic error.

### 4. `compute.restrictVpcPeering` org policy blocks PSA
If the GCP organization has `compute.restrictVpcPeering` set to deny, Cloud SQL Private Service Access (PSA) will fail. Override at the project level with `allowAll` using `gcloud org-policies set-policy`.

### 5. Managed Kafka uses `google-beta` provider
`google_managed_kafka_cluster` and `google_managed_kafka_topic` require the `google-beta` provider. Set `provider = google-beta` explicitly on these resources.
