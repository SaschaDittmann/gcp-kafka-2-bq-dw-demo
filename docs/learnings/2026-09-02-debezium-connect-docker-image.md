---
date: 2026-09-02
topic: Debezium Connect Docker Image
---

# Debezium vs Confluent Kafka Connect Docker Images

## The Problem / Context

Running a self-hosted CDC source connector on Cloud Run required a Kafka Connect Docker image with the Debezium PostgreSQL connector and GCP auth libraries. The initial approach used `confluentinc/cp-kafka-connect:7.7.1` but the Confluent image has a preflight check (CUB — Confluent Utility Belt) that runs `cub kafka-ready` before starting Connect. This check uses its own internal classpath that cannot be extended, making it impossible to add the `GcpLoginCallbackHandler` class needed for Managed Kafka IAM auth.

## The Solution / Learning

Switch to `debezium/connect:2.5` which:
- **No preflight check** — starts Kafka Connect directly
- **Debezium PG connector pre-installed** — no need to download plugins
- **GCP auth JARs go to `/kafka/libs/`** — on the classpath by default
- **Runs as user `kafka`** (not `appuser` like Confluent)
- **Plugin path** is `/kafka/connect/` by default
- Dockerfile reduced from ~88 lines to ~40 lines

### Key Debezium env vars (no prefix):
`BOOTSTRAP_SERVERS`, `GROUP_ID`, `CONFIG_STORAGE_TOPIC`, `OFFSET_STORAGE_TOPIC`, `STATUS_STORAGE_TOPIC`, `KEY_CONVERTER`, `VALUE_CONVERTER`

### Additional properties use `CONNECT_` prefix:
`CONNECT_SECURITY_PROTOCOL` → `security.protocol`, `CONNECT_LISTENERS` → `listeners`

### Critical: Use `listeners` not `rest.host.name`
In Kafka 3.x+ (Debezium 2.5 uses Kafka 3.7), the `listeners` property supersedes the deprecated `rest.host.name` and `rest.port`. Set `CONNECT_LISTENERS=http://0.0.0.0:8083` for Cloud Run.

