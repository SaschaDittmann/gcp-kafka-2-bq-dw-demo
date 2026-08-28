# PRD: Real-Time CDC Pipeline with Managed Kafka & BigQuery Continuous Queries

## 1. Introduction

This feature delivers an end-to-end, serverless streaming data pipeline on Google Cloud that captures transactional data changes (CDC) from a PostgreSQL database and models them into a real-time BigQuery star schema. The pipeline uses Cloud SQL for PostgreSQL as the OLTP source, Google Managed Service for Apache Kafka as the event broker, Google Managed Kafka Connect for CDC ingestion and sinks (with an optional Cloud Run mode for the CDC source), BigQuery Continuous Queries for real-time Bronze → Silver transformations, and BigQuery Scheduled Queries for near-real-time Silver → Gold transformations.

The problem this solves: Data Engineers need a production-grade reference implementation demonstrating how to build a real-time CDC pipeline on GCP using fully managed and serverless components — without custom application code for the streaming layer.

This is a **standalone pipeline** that operates independently from the existing dlt/dbt batch pipeline in this repository.

## 2. Goals

- **End-to-end CDC streaming:** Capture every INSERT, UPDATE, and DELETE from Cloud SQL for PostgreSQL and deliver them to BigQuery in real time via Managed Kafka.
- **Real-time star schema modeling:** Transform raw CDC events into a dimensional model (SCD Type 2 dimensions + fact tables) using BigQuery Continuous Queries, eliminating the need for batch-scheduled dbt transformations.
- **Sub-minute latency:** Changes committed to PostgreSQL appear in the BigQuery Gold layer within 60 seconds under normal operating conditions.
- **One-command provisioning:** A single `terraform apply` followed by one setup script provisions all infrastructure, seeds demo data, and starts the streaming pipeline.
- **Clean reproducibility:** The entire demo can be torn down with a scripted teardown + `terraform destroy` and re-created from scratch, producing identical results.
- **Zero custom streaming code:** All CDC extraction, filtering, field masking, and sink operations are configuration-driven via Debezium and Kafka Connect SMTs — no custom producers or consumers.

## 3. User Stories

- **As a Data Engineer**, I want to run a single provisioning command and have the entire CDC pipeline (Cloud SQL, Kafka, Kafka Connect, BigQuery datasets) deployed and running, so that I can evaluate the architecture without manual setup.
- **As a Data Engineer**, I want to insert, update, and delete rows in the source PostgreSQL database and see those changes reflected in the BigQuery Gold layer within 60 seconds, so that I can validate the real-time behavior.
- **As a Data Engineer**, I want sensitive fields (e.g., `phone`, `fax`) automatically stripped from events before they reach BigQuery, so that PII is never stored in the analytics layer.
- **As a Data Engineer**, I want the BigQuery Gold layer modeled as SCD Type 2 dimensions and point-in-time–correct fact tables, so that I can run historical and current-state analytics.
- **As a Data Engineer**, I want to tear down the demo with a single cleanup procedure (script + `terraform destroy`) that leaves no orphaned resources, so that I can avoid unexpected cloud costs.

## 4. Functional Requirements

### 4.1. Source System (Cloud SQL for PostgreSQL)

1. Provision a Cloud SQL for PostgreSQL instance with logical decoding enabled (`cloudsql.logical_decoding=on`, `wal_level=logical`).
2. Create a dedicated replication user with the `REPLICATION` role.
3. Initialize the database using the [Chinook sample database](https://github.com/lerocha/chinook-database) (digital music store). The schema includes the following core tables for CDC:
   - `customer` (customer_id, first_name, last_name, company, address, city, state, country, postal_code, phone, fax, email, support_rep_id)
   - `employee` (employee_id, last_name, first_name, title, reports_to, birth_date, hire_date, address, city, state, country, postal_code, phone, fax, email)
   - `artist` (artist_id, name)
   - `album` (album_id, title, artist_id)
   - `track` (track_id, name, album_id, media_type_id, genre_id, composer, milliseconds, bytes, unit_price)
   - `genre` (genre_id, name)
   - `media_type` (media_type_id, name)
   - `invoice` (invoice_id, customer_id, invoice_date, billing_address, billing_city, billing_state, billing_country, billing_postal_code, total)
   - `invoice_line` (invoice_line_id, invoice_id, track_id, unit_price, quantity)
   - `playlist` (playlist_id, name)
   - `playlist_track` (playlist_id, track_id)
4. Seed the database with the Chinook sample data (~59 customers, 8 employees, 275 artists, 347 albums, 3,503 tracks, 25 genres, 412 invoices, 2,240 invoice lines).
   > **Note:** The Chinook schema does not include `created_at` / `updated_at` timestamp columns. The pipeline relies on Debezium's `ts_ms` field (from the WAL event) for event ordering and change tracking throughout Bronze, Silver, and Gold layers.
5. Create a logical replication slot using the `pgoutput` plugin for Debezium.

### 4.2. Streaming Broker (Google Managed Service for Apache Kafka)

6. Provision a Google Managed Kafka cluster.
7. Configure dedicated Kafka topics per source table following the Debezium naming convention (e.g., `cdc.public.customer`, `cdc.public.invoice`, `cdc.public.track`).
8. Use IAM-based authentication — the Kafka Connect service account must have the `roles/managedkafka.client` role.

### 4.3. CDC Ingestion & Sink (Managed & Cloud Run Dual-Mode)

9. Support a **dual-mode architecture** for the CDC source ingestion:
   - **Default:** Google Managed Kafka Connect with the built-in Debezium PostgreSQL connector.
   - **Optional:** Cloud Run self-hosted Debezium source (toggled via `source_connector_type` in Terraform).
10. Sinks are **always managed**: The BigQuery sink and GCS archive sink both run on Google Managed Kafka Connect.
11. **Secret Manager** is required for storing the PostgreSQL database password when using the managed connectors.
12. For the Cloud Run self-hosted source option, build a custom Docker image based on the official Kafka Connect image, bundling:
    - Debezium PostgreSQL Source Connector
    - Google Managed Kafka auth library (GcpLoginCallbackHandler) for SASL/OAUTHBEARER
    - *Note: No BigQuery connector is needed in the image since sinks are fully managed.*
13. Use **JSON** as the serialization format with schemas enabled (`value.converter.schemas.enable=true`). The Debezium source produces a typed schema envelope that the BigQuery sink uses to create properly typed RECORD columns. No schema registry is required.
14. Configure the Debezium Source Connector to capture CDC events from all Chinook source tables.
15. Configure the BigQuery Sink Connector to write CDC events to the Bronze layer tables.
16. **GCS CDC Archive Sink:** Configure a GCS sink connector to archive all CDC events as JSON (uncompressed, readable format) to GCS for long-term storage and replay.

### 4.4. In-Flight Processing (SMTs)

17. SMTs are configured entirely in Terraform (`kafka_connect.tf`) for the managed BigQuery sink connector, rather than in a separate JSON config file.
18. Configure the `ReplaceField$Value` SMT on the sink connector to exclude sensitive fields (`phone`, `fax`) from customer and employee events before writing to BigQuery.
19. Optionally configure the `Filter` SMT to exclude specific message types (e.g., tombstone records or specific status updates) from the sink.

### 4.5. BigQuery Data Warehouse (Bronze / Silver / Gold)

18. Create three BigQuery datasets: `bronze`, `silver`, `gold`.
19. **Bronze Layer:** Create append-only tables mirroring each Kafka topic (one per source table), containing the full Debezium envelope (`before`, `after`, `op`, `ts_ms`).
20. **Silver Layer:** Implement a hybrid current-state approach:
    - **5 CQ-populated tables** (customer, employee, track, invoice, invoice_line) — BigQuery Continuous Queries using `APPENDS(TABLE, NULL)` that INSERT typed fields from the Bronze CDC envelope into Silver tables. These tables serve as streaming sources for Gold scheduled queries.
    - **6 views on Bronze** (artist, album, genre, media_type, playlist, playlist_track) — reference/lookup data that rarely changes. Views use `QUALIFY ROW_NUMBER()` for current-state dedup without CQ overhead.
    - All entities expose: `is_deleted` flag, `_source_ts_ms` (from Debezium `ts_ms`)
21. **Gold Layer — Dimensions (SCD Type 2, Managed Apache Iceberg):** Create Iceberg-backed dimension tables stored as Parquet on GCS. Implement **scheduled queries** (every 5 minutes) instead of CQs because Iceberg tables do not support CQ destinations. Dimensions use JOINs instead of correlated subqueries (Iceberg limitation). `dim_track` denormalizes album, artist, genre, and media_type via LEFT JOINs.
22. **Gold Layer — Facts (Managed Apache Iceberg):** Create Iceberg-backed fact tables. Implement scheduled queries that JOIN against current-state dimension subqueries for surrogate key resolution.
22b. **Gold Layer — Current-State Views:** Create 5 views (`v_dim_customer`, `v_dim_employee`, `v_dim_track`, `v_fct_invoice`, `v_fct_invoice_line`) that provide current-state access to SCD2 dimensions and fact tables with resolved dimension names.

### 4.6. Infrastructure as Code (Terraform)

23. Define all foundational GCP resources in Terraform:
    - Networking: VPC, subnets, firewall rules, VPC connectors
    - Cloud SQL instance and database
    - Managed Kafka cluster and topics
    - BigQuery datasets and table schemas
    - Managed Kafka Connect clusters (Source, BQ Sink, GCS Sink)
    - Secret Manager secret for database password
    - GCS archive bucket
    - Optional Cloud Run service and Artifact Registry repository (if self-hosted source is toggled)
    - IAM bindings
    - BigQuery Enterprise reservation (autoscale, CONTINUOUS job type)
    - BigQuery Data Transfer scheduled queries for Gold layer
24. All Terraform configuration must reside in the `infra/` directory.
25. Use **local state** (`terraform.tfstate` file) — no remote backend required for the demo.

### 4.7. Post-Provisioning & Lifecycle Scripts

26. Provide a deployment script (`scripts/deploy.sh` or similar) that:
    - Creates the logical replication slot in PostgreSQL
    - Initializes the Chinook schema and seeds demo data
    - Builds and pushes the Kafka Connect Docker image to Artifact Registry via `gcloud builds submit`
    - Registers the Debezium Source and BigQuery Sink connectors via the Kafka Connect REST API
    - Starts the BigQuery Continuous Queries for Silver and Gold layers
27. Provide a teardown script (`scripts/teardown.sh` or similar) that:
    - Cancels all running BigQuery Continuous Queries
    - Drops the logical replication slot in PostgreSQL
    - Is run **before** `terraform destroy`

## 5. Non-Goals

- **No authentication or multi-tenant support.** This is a single-user demo environment.
- **No CI/CD pipeline.** Deployment is manual via Terraform + scripts.
- **No monitoring or alerting infrastructure.** No Prometheus, Grafana, Cloud Monitoring dashboards, or alerting policies.
- **No dashboard or visualization layer.** This pipeline produces data in BigQuery; visualization tools (Looker, Data Studio) are out of scope.
- **No integration with the existing dlt/dbt batch pipeline.** This is a standalone streaming pipeline with its own datasets.
- **No production hardening.** No HA configuration, auto-scaling policies, dead-letter queues, or retry mechanisms beyond defaults.
- **No schema evolution handling.** The demo assumes a fixed schema; Debezium schema registry integration is out of scope.

## 6. Design Considerations

- **No UI component.** This is an infrastructure and data pipeline feature. Verification is done by querying BigQuery directly (e.g., via the BigQuery console or `bq` CLI).
- **Chinook schema:** Uses the open-source [Chinook database](https://github.com/lerocha/chinook-database), a digital music store model (customers, invoices, tracks, albums, artists) that is widely recognized in the PostgreSQL community and easy for Data Engineers to understand.
- **Naming conventions:**
  - BigQuery datasets: `bronze`, `silver`, `gold`
  - Bronze tables: match Kafka topic names (e.g., `customer_raw`, `invoice_raw`, `track_raw`)
  - Silver tables: `customer`, `employee`, `artist`, `album`, `track`, `genre`, `invoice`, `invoice_line` (current-state, no prefix)
  - Gold dimensions: `dim_customer`, `dim_track`, `dim_employee`
  - Gold facts: `fct_invoice`, `fct_invoice_line`

## 7. Technical Considerations

### Dependencies
- Google Cloud project with billing enabled
- APIs enabled: Cloud SQL Admin, Managed Kafka, Secret Manager, BigQuery, Cloud Run, Artifact Registry, Cloud Build, Compute Engine (for VPC)
- Terraform >= 1.5 with the `google` and `google-beta` providers
- `gcloud`, `bq`, `psql` CLI tools available locally
- Docker is **not** required locally — container images are built via Cloud Build

### Region & Sizing
- **GCP Region:** `europe-west1` (Belgium). All services (Cloud SQL, Managed Kafka, Cloud Run, BigQuery) must be deployed in this region.
- **Cloud SQL:** Minimal instance — `db-f1-micro` or `db-g1-small`, 10 GB SSD storage, PostgreSQL 15+. This is a demo; no HA or read replicas.
- **Managed Kafka:** Smallest available cluster configuration (e.g., 1 broker, minimal storage). Exact sizing depends on the Managed Kafka offering's minimum requirements.
- **Terraform State:** Local `terraform.tfstate` file. No remote backend (GCS bucket) is needed for the demo.

### Constraints
- **Managed Apache Iceberg tables** do not support BigQuery CQs as destinations, nor correlated subqueries in INSERT statements. Gold layer uses scheduled queries with JOIN-based SQL instead.
- **BigQuery Continuous Queries** are a relatively new feature. CQ support for `MERGE` statements may be limited; the implementation may need to fall back to `INSERT`-based patterns with deduplication.
- **Managed Kafka** and **Managed Kafka Connect** cluster provisioning can take 15–20 minutes. The deployment script must account for this.
- **Cloud Run with "CPU always allocated"** is required because Kafka Connect is a long-running process, not a request-driven service.
- **VPC networking** is required for private connectivity between Cloud Run, Cloud SQL, and Managed Kafka. This adds complexity to the Terraform configuration.
- **Chinook schema lacks timestamps.** All event ordering relies on Debezium's `ts_ms` field, not source-table columns.

### Performance
- Target end-to-end latency: < 60 seconds from PostgreSQL commit to BigQuery Gold layer availability.
- The demo is designed for low-throughput workloads (< 100 events/second). No performance tuning for high-throughput scenarios is required.

## 8. Success Metrics

| Metric | Target |
|---|---|
| **Provisioning time** | Full pipeline deployed and streaming within 30 minutes of `terraform apply` + setup script |
| **End-to-end latency** | PostgreSQL change visible in BigQuery Gold layer in < 60 seconds |
| **CDC completeness** | 100% of INSERTs, UPDATEs, and DELETEs captured and reflected in Silver/Gold layers |
| **PII masking** | Zero rows in BigQuery containing `phone` or `fax` field values |
| **Clean teardown** | `teardown.sh` + `terraform destroy` removes all resources; no orphaned GCP resources remain |
| **Reproducibility** | Pipeline can be destroyed and re-created from scratch at least 3 times without errors |
| **SCD Type 2 correctness** | Dimension updates produce correct `valid_from`/`valid_to` ranges; fact table joins resolve to the correct surrogate key |

## 9. Open Questions

1. **BigQuery CQ + MERGE support:** Does BigQuery Continuous Queries currently support `MERGE` statements, or must the Silver layer use an `INSERT`-based pattern with a view that deduplicates? This needs validation during implementation.
2. **Managed Kafka Terraform provider:** Is the `google_managed_kafka_cluster` resource stable in the `google` or `google-beta` Terraform provider, or does it need to be provisioned via `gcloud` commands?
3. **BigQuery Sink Connector choice:** Should we use the Confluent BigQuery Sink Connector or the Google-maintained equivalent? The choice affects licensing, configuration syntax, and SMT compatibility.
4. **Surrogate key strategy:** Should the Gold layer use deterministic keys (`FARM_FINGERPRINT`) or random keys (`GENERATE_UUID`)? Deterministic keys simplify debugging but may collide; UUIDs are safer but harder to trace.
5. **Demo data generator:** Should the seed script also include a "data generator" mode that continuously inserts/updates/deletes rows to demonstrate the pipeline in motion, or is manual SQL sufficient?
