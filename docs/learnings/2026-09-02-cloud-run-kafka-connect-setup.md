---
date: 2026-09-02
topic: Cloud Run Kafka Connect Setup
---

# Cloud Run as Kafka Connect Host — Lessons Learned

## The Problem / Context

Deploying Kafka Connect (Debezium CDC source) on Cloud Run required solving multiple issues across container runtime, networking, IAM, and tooling. This document captures the complete set of fixes applied.

## The Solution / Learning

### 1. Container Build via Terraform
Use `null_resource.build_connect_image` with `local-exec` running `gcloud builds submit`. Trigger on `filemd5()` of Dockerfile and connector config. Cloud Run service `depends_on` this resource.

### 2. Internal Kafka Connect Topics
Cloud Run mode needs 3 internal topics created conditionally:
- `source-connect-configs` (1 partition, compact)
- `source-connect-offsets` (25 partitions, compact)
- `source-connect-status` (5 partitions, compact)

### 3. Ingress + IAM for Connector Registration
- `INGRESS_TRAFFIC_INTERNAL_ONLY` blocks ALL external traffic (even `gcloud run services proxy`)
- `INGRESS_TRAFFIC_ALL` required for deploy.sh to register connectors
- Org policy `iam.allowedPolicyMemberDomains` may block `allUsers` — override at project level
- `gcloud run services proxy` adds IAM credentials but does NOT bypass ingress restrictions

### 4. bq CLI Broken — Use REST API
The `bq` CLI has a CBA/mTLS bug in some environments. Use the BigQuery REST API (`jobs.insert` with `continuous: true`) to start Continuous Queries. Also strip SQL comments (`-- ...`) before passing to `bq` to avoid flag parsing errors.

### 5. gcloud Format Compatibility
`gcloud run services describe --format="value(status.conditions.filter(type=Ready).status)"` is not supported on all gcloud versions. Use `--format="json(status.conditions)"` + python3 parsing instead.

### 6. Health Check Endpoint
The Debezium Connect image returns 404 for root path `/` but 200 for `/connectors`. Use `/connectors` for health checks (matches Cloud Run startup probe).
