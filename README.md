# Real-Time CDC Pipeline: Cloud SQL → Kafka → BigQuery

A reference implementation of an end-to-end, serverless streaming data pipeline on Google Cloud. This demo captures transactional data changes (CDC) from a PostgreSQL database, streams them through Google Managed Kafka, and models them into a real-time BigQuery star schema using Continuous Queries and Scheduled Queries.

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────────────────────────────────┐
│  Cloud SQL   │     │   Managed    │     │                   BigQuery                   │
│  PostgreSQL  │────▶│    Kafka     │────▶│        Bronze → Silver → Gold (SCD2)         │
│  (CDC Source)│     │   (Broker)   │     │  via Continuous Queries + Scheduled Queries  │
└──────────────┘     └──────────────┘     └──────────────────────────────────────────────┘
        │                    ▲    │                               │
        │                    │    │                               │
        └── CDC Source ──────┘    ├── BQ Sink ────┘
            Connector             └── GCS Sink ──▶  gs://<project>-cdc-archive/
                                                    (long-term JSON archive)
    ┌─────────────────────────────────────────┐
    │        Managed Kafka Connect             │
    │  Source: Cloud SQL PostgreSQL (Debezium) │
    │  Sink: BigQuery (Bronze layer)           │
    │  Sink: GCS (long-term CDC archive)       │
    └─────────────────────────────────────────┘
            OR (source_connector_type = "cloudrun")
    ┌─────────────────┐
    │  Cloud Run      │
    │  connect-source │  ← Self-hosted Debezium
    │  (1 instance)   │
    └─────────────────┘
```

**Key components:**

- **Cloud SQL for PostgreSQL** — OLTP source with CDC
- **Google Managed Kafka** — Central message broker with per-table topics
- **Google Managed Kafka Connect** — Built-in connectors for CDC source, BigQuery sink, and GCS archive sink
- **Cloud Run (optional)** — Self-hosted Debezium source connector, toggle via `source_connector_type`
- **BigQuery Continuous Queries + Scheduled Queries** — Real-time and near-real-time transformations across three layers:
  - **Bronze** — Append-only raw CDC events (Debezium envelope with RECORD-typed columns)
  - **Silver** — Current-state entity tables (5 CQ-populated tables + 6 views on Bronze)
  - **Gold** — Star schema with SCD Type 2 dimensions and fact tables (Managed Apache Iceberg on GCS, populated by scheduled queries every 5 min)

## Demo Schema

The pipeline uses the [Chinook sample database](https://github.com/lerocha/chinook-database), a digital music store with the following core tables:

| Table | Description | Records |
|---|---|---|
| `customer` | Music store customers (name, email, address) | ~59 |
| `employee` | Store employees and support reps | ~8 |
| `artist` | Music artists | ~275 |
| `album` | Albums linked to artists | ~347 |
| `track` | Individual songs with pricing | ~3,503 |
| `genre` | Music genres (Rock, Jazz, etc.) | ~25 |
| `media_type` | Media formats (MPEG, AAC, etc.) | ~5 |
| `invoice` | Customer purchases | ~412 |
| `invoice_line` | Line items per invoice | ~2,240 |
| `playlist` | Curated track lists | ~18 |
| `playlist_track` | Playlist–track associations | ~8,715 |

**Star schema mapping:**
- **Dimensions:** `dim_customer`, `dim_track` (denormalized with album/artist/genre), `dim_employee`
- **Facts:** `fct_invoice`, `fct_invoice_line`

## Prerequisites

- Google Cloud project with billing enabled
- APIs enabled: Cloud SQL Admin, Managed Kafka, BigQuery, Cloud Run, Artifact Registry, Cloud Build, Compute Engine
- [Terraform](https://www.terraform.io/) >= 1.5
- CLI tools: `gcloud`, `bq`, `psql`
- [Python](https://www.python.org/) 3.11+ with [uv](https://docs.astral.sh/uv/)

> **Note:** Docker is not required locally — container images are built via Cloud Build.

## Project Structure

```
infra/              # Terraform configurations for GCP
connect/            # Kafka Connect Dockerfile and source connector config (for Cloud Run mode)
scripts/            # Deployment and teardown shell scripts
transform/          # BigQuery transformation SQL
  silver/cq/        #   Silver Continuous Queries (Bronze → Silver)
  silver/views/     #   Silver views on Bronze (auto-discovered by Terraform)
  gold/sq/          #   Gold scheduled queries (Silver → Gold)
  gold/views/       #   Gold current-state views (auto-discovered by Terraform)
data/               # SQL schema, seed data, and database initialization scripts
tests/              # End-to-end and integration tests
docs/prds/          # Product Requirements Documents
docs/tasks/         # Task breakdowns per feature
docs/learnings/     # Documented solutions and patterns
```

## Networking Architecture

All services communicate over a private custom VPC — no public IP traffic for data plane operations.

```
                          ┌─────────────────────────────────────────┐
                          │          cdc-demo-vpc (custom)          │
                          │                                        │
  ┌────────────────┐      │  ┌──────────────┐  ┌───────────────┐   │
  │  Cloud Run     │──────┼──│  VPC Access   │  │   Subnet      │   │
  │ connect-source │      │  │  Connector    │  │  10.0.0.0/22  │   │
  ├────────────────┤      │  │ 10.8.0.0/28  │  └───────┬───────┘   │
  │  Cloud Run     │──────┤  └──────┬───────┘          │           │
  │ connect-sink   │      │         │                  │           │
  └────────────────┘      │         ▼                  ▼           │
                          │  ┌──────────────┐  ┌───────────────┐   │
                          │  │  Cloud SQL   │  │ Managed Kafka │   │
                          │  │ (Private IP) │  │  (VPC-bound)  │   │
                          │  │  via PSA     │  │               │   │
                          │  └──────────────┘  └───────────────┘   │
                          │                                        │
                          └─────────────────────────────────────────┘
                                         │
                            Private Google Access
                                         │
                                         ▼
                               ┌──────────────────┐
                               │    BigQuery       │
                               │ (Google-managed)  │
                               └──────────────────┘
```

**Key networking components:**

| Component | Resource | Purpose |
|---|---|---|
| Custom VPC | `google_compute_network` | Isolates all pipeline resources |
| Subnet (`10.0.0.0/22`) | `google_compute_subnetwork` | Primary CIDR for compute and managed services (requires /22 for Managed Kafka Connect) |
| VPC Access Connector (`10.8.0.0/28`) | `google_vpc_access_connector` | Bridges Cloud Run → VPC for private IP access |
| Private Service Access | `google_service_networking_connection` | Enables Cloud SQL private IP via VPC peering |
| Firewall (internal) | `google_compute_firewall` | Allows PostgreSQL (5432), Kafka (9092–9093), Connect (8083) |
| Firewall (health checks) | `google_compute_firewall` | Allows Google health check probes |
| Private Google Access | Subnet attribute | Allows private resources to reach BigQuery and GCP APIs |

## Database Setup (Cloud SQL PostgreSQL)

The pipeline source is a Cloud SQL for PostgreSQL instance running the [Chinook sample database](https://github.com/lerocha/chinook-database) with logical decoding enabled for CDC.

**Instance configuration:**
- PostgreSQL 15, `db-f1-micro` tier, 10 GB SSD, private IP only
- Database flag: `cloudsql.logical_decoding = on` (enables WAL-based CDC)
- Random name suffix to avoid 7-day reuse lockout after `terraform destroy`

**Initialization (`data/init_db.sh`):**

The database is initialized by the deployment script after `terraform apply`:

1. Creates a `debezium` replication user with `REPLICATION` role
2. Loads the Chinook schema (`data/chinook_schema.sql`) — 11 tables
3. Seeds sample data (`data/chinook_seed.sql`) — ~15,600 records
4. Creates the `debezium_slot` logical replication slot (`pgoutput` plugin)
5. Creates the `debezium_publication` publication for all tables

The script is idempotent — safe to re-run without errors.

**Connecting to Cloud SQL:**

```bash
# Get connection details from Terraform outputs
cd infra
export DB_HOST=$(terraform output -raw cloudsql_private_ip)
export DB_NAME=$(terraform output -raw cloudsql_database_name)
export DB_USER=$(terraform output -raw cloudsql_admin_user)
export DB_PASSWORD=$(terraform output -raw cloudsql_admin_password)

# Connect via Cloud SQL Auth Proxy or psql (requires VPC access)
gcloud sql connect $(terraform output -raw cloudsql_instance_name) --user=$DB_USER --database=$DB_NAME
```

**Re-initializing the database:**

```bash
# Re-run the init script (idempotent — skips existing slots/publications)
./data/init_db.sh
```

## Kafka Cluster (Google Managed Kafka)

A Google Managed Service for Apache Kafka cluster handles CDC event streaming between Cloud SQL and BigQuery.

**Cluster configuration:**
- 3 vCPUs, 3 GiB memory (minimum size for demo)
- VPC-attached via the pipeline subnet
- IAM authentication (SASL/OAUTHBEARER) — no static credentials
- Provisioning takes **15–30 minutes** on first `terraform apply`

**Topic naming convention (Debezium):**

| Topic Name | Source Table |
|---|---|
| `cdc.public.customer` | `customer` |
| `cdc.public.employee` | `employee` |
| `cdc.public.artist` | `artist` |
| `cdc.public.album` | `album` |
| `cdc.public.track` | `track` |
| `cdc.public.genre` | `genre` |
| `cdc.public.media_type` | `media_type` |
| `cdc.public.invoice` | `invoice` |
| `cdc.public.invoice_line` | `invoice_line` |
| `cdc.public.playlist` | `playlist` |
| `cdc.public.playlist_track` | `playlist_track` |

Each topic has 1 partition and replication factor 3 (across availability zones).

**Verifying cluster health:**

```bash
# Check cluster state
gcloud managed-kafka clusters describe cdc-demo-kafka \
  --location=europe-west1 --project=kafka-2-bq-streaming-demo

# List topics
gcloud managed-kafka topics list \
  --cluster=cdc-demo-kafka --location=europe-west1 \
  --project=kafka-2-bq-streaming-demo
```

## Kafka Connect (Managed + Cloud Run)

By default, **ALL connectors run on Google Managed Kafka Connect** (fully managed, no Docker required):
- **CDC Source Connector** — Built-in Cloud SQL PostgreSQL connector
- **BigQuery Sink Connector** — Built-in sink connector
- **GCS Archive Sink Connector** — Built-in sink connector (long-term JSON archive)

**Self-hosted option:**
You can toggle `source_connector_type = "cloudrun"` in Terraform to use a self-hosted Debezium source connector on Cloud Run instead.
When `cloudrun` is selected, it requires building a Docker image first (`gcloud builds submit connect/ --tag=...`).
The Docker image (`connect/Dockerfile`) contains only Debezium and the Managed Kafka auth library (no BigQuery sink).

**SMT (Single Message Transforms) on the BigQuery Sink:**
- `ReplaceField$Value` — drops `phone` and `fax` fields from all records
- `Filter` with `RecordIsTombstone` predicate — filters out tombstone delete markers

## BigQuery Data Warehouse (Bronze / Silver / Gold)

Three-layer **medallion architecture** for CDC data processing:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     Bronze      │     │     Silver      │     │      Gold       │
│  (Raw CDC)      │────▶│  (Current State)│────▶│  (Star Schema)  │
│                 │ CQ  │                 │ SQ  │  Apache Iceberg │
│  11 tables      │     │  11 tables      │     │  3 dims + 2 fct │
│  RECORD structs │     │  Typed columns  │     │  Parquet on GCS │
└─────────────────┘     └─────────────────┘     └─────────────────┘

> CQ = Continuous Query (streaming), SQ = Scheduled Query (every 5 min)
```

**Bronze layer** (`bronze` dataset) — 11 `*_raw` tables with Debezium envelope columns:
`before`, `after` (RECORD/struct), `source` (RECORD), `op` (c/u/d/r), `ts_ms`, `ts_us`, `ts_ns`, `transaction`

**Silver layer** (`silver` dataset) — hybrid approach:
- **5 persistent tables** (customer, employee, track, invoice, invoice_line) — populated by CQs, used as sources for Gold scheduled queries
- **6 views on Bronze** (artist, album, genre, media_type, playlist, playlist_track) — reference/lookup data that rarely changes, uses `QUALIFY ROW_NUMBER()` for current-state dedup
- All expose: `is_deleted`, `_source_ts_ms` (views) or `_loaded_at`, `_source_ts_ms` (tables)

**Gold layer** (`gold` dataset) — **Managed Apache Iceberg** tables (Parquet on GCS):
- **Dimensions (SCD Type 2):** `dim_customer`, `dim_track` (denormalized with album/artist/genre/media_type), `dim_employee`
  - Each change creates a new row with `surrogate_key` (UUID), `valid_from`, `valid_to`, `is_active`
- **Facts:** `fct_invoice`, `fct_invoice_line` with surrogate key references and computed `line_total`
- **Interoperability:** Data stored as Parquet in GCS (`gs://<project>-iceberg-gold/`) — queryable by Spark, Trino, Flink, or any Iceberg-compatible engine

**Transformations** (`transform/*.sql`):
- **5 Silver CQs** (Bronze → Silver) — Continuous Queries using `APPENDS(TABLE, NULL)` for streaming, launched via `bq query --continuous=true`
- **5 Gold Scheduled Queries** (Silver → Gold) — BigQuery Data Transfer scheduled queries running every 5 minutes, managed by Terraform
- **5 Gold current-state views** (`v_dim_customer`, `v_dim_employee`, `v_dim_track`, `v_fct_invoice`, `v_fct_invoice_line`) — provide easy access to current dim values and fact tables with resolved dimension names
- Requires BigQuery **Enterprise edition** with slot reservations (autoscale, CONTINUOUS assignment)

## Getting Started

### 1. Configure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project ID and region
```

### 2. Provision Infrastructure

```bash
cd infra
terraform init
terraform apply
```

> **Note:** The Managed Kafka cluster takes **15–30 minutes** to provision on first apply.
> You can toggle `source_connector_type` between `"managed"` (default) and `"cloudrun"` in your `terraform.tfvars`.
> If using Cloud Run, services will show "image not found" errors until `deploy.sh` builds the Docker image.

### 3. Deploy Pipeline

```bash
./scripts/deploy.sh
```

This orchestrates the full post-Terraform deployment:

| Step | Description | Duration |
|------|-------------|----------|
| 1 | Initialize Chinook database (schema, seed, replication) | ~2 min |
| 2 | Build & push Docker image (only if using Cloud Run source) | ~5 min |
| 3 | Update Cloud Run services (only if using Cloud Run source) | ~1 min |
| 4 | Wait for Cloud Run services (only if using Cloud Run source) | ~2 min |
| 5 | Start 5 Silver Continuous Queries (Bronze → Silver) | ~1 min |

Note: Bronze tables, Silver/Gold views, and Gold scheduled queries are all managed by Terraform (auto-deployed on `terraform apply`).

**Skip flags** (useful for re-runs):
```bash
SKIP_DB_INIT=true ./scripts/deploy.sh       # Skip database initialization
SKIP_IMAGE_BUILD=true ./scripts/deploy.sh   # Skip Docker image build
SKIP_CQ_START=true ./scripts/deploy.sh      # Skip Continuous Query startup
```

### 4. Verify

**Check connector status:**
```bash
# Proxy into Cloud Run source service
gcloud run services proxy cdc-demo-connect-source --region=europe-west1 --port=8083 &

# Check connectors
curl http://localhost:8083/connectors
curl http://localhost:8083/connectors/debezium-source/status | python3 -m json.tool
```

**Query BigQuery layers:**
```bash
# Bronze — raw CDC events
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) as row_count FROM `bronze.customer_raw`'

# Silver — current-state entities
bq query --use_legacy_sql=false \
  'SELECT customer_id, first_name, last_name, email
   FROM `silver.customer`
   WHERE is_deleted = FALSE
   LIMIT 10'

# Gold — current-state dimensions (via views)
bq query --use_legacy_sql=false \
  'SELECT customer_id, first_name, last_name, city, country
   FROM `gold.v_dim_customer`
   LIMIT 10'

# Gold — fact tables with resolved dimension names
bq query --use_legacy_sql=false \
  'SELECT invoice_id, total, customer_first_name, customer_last_name
   FROM `gold.v_fct_invoice`
   LIMIT 10'
```

**Test CDC by inserting a new customer:**
```bash
gcloud sql connect <instance-name> --user=admin --database=chinook

-- In psql:
INSERT INTO customer (customer_id, first_name, last_name, email)
VALUES (100, 'Test', 'Customer', 'test@example.com');
```

Then check BigQuery within ~60 seconds:
```bash
bq query --use_legacy_sql=false \
  'SELECT * FROM `silver.customer` WHERE customer_id = 100'
```

### 5. Teardown

```bash
# Step 1: Cancel Continuous Queries and clean up stateful resources
./scripts/teardown.sh

# Step 2: Destroy all infrastructure
cd infra
terraform destroy
```

> [!WARNING]
> Always run `teardown.sh` before `terraform destroy` to avoid orphaned Continuous Queries and locked replication slots.

## Testing

```bash
uv run pytest tests/ -v
```

| Test File | What It Validates |
|---|---|
| `test_deploy.py` | Deploy script structure, steps, prerequisites, CQ references |
| `test_teardown.py` | Teardown script structure, CQ cancellation, slot cleanup |
| `test_pii_masking.py` | No phone/fax columns in schemas, SMT exclusion config |
| `test_cdc_pipeline.py` | E2E: insert/update/delete → Bronze/Silver/Gold (requires live pipeline) |
| `test_scd2.py` | SCD Type 2 dimension correctness (requires live pipeline) |
| `test_bigquery_schemas.py` | Dataset/table/column validation against Terraform |
| `test_continuous_queries.py` | CQ SQL file structure, source/target references |
| `test_connector_configs.py` | Connector JSON syntax, required fields, SMT config |
| `test_infra_networking.py` | Terraform validate/plan for networking |
| `test_infra_kafka.py` | Terraform plan for Kafka resources |
| `test_database_init.py` | Database init script structure and content |

## Troubleshooting

### Cloud Run: "Image not found"

*(Only relevant when `source_connector_type = "cloudrun"`)*
The Docker image hasn't been built yet. Build it manually:
```bash
gcloud builds submit connect/ \
  --tag=europe-west1-docker.pkg.dev/<project-id>/cdc-demo-docker/kafka-connect:latest
```

### Cloud Run: `deletion_protection` errors

*(Only relevant when `source_connector_type = "cloudrun"`)*
If Terraform can't destroy Cloud Run services:
```bash
cd infra
terraform untaint google_cloud_run_v2_service.kafka_connect_source
terraform apply --auto-approve
```

### Managed Kafka: Provisioning timeout

Kafka clusters can take >1 hour. The Terraform timeout is set to 2 hours.
If it times out, just re-run `terraform apply` — it will pick up where it left off.

### BigQuery CQs: "Enterprise edition required"

Continuous Queries require BigQuery Enterprise edition with slot reservations.
The Terraform configuration creates an autoscale reservation (up to 100 slots) with CONTINUOUS job type assignment.
If you see this error, ensure `terraform apply` has been run to create the reservation.

### Cloud Build: Permission denied

Grant the Compute Engine default SA the required roles:
```bash
gcloud projects add-iam-policy-binding <project-id> \
  --member="serviceAccount:<project-number>-compute@developer.gserviceaccount.com" \
  --role="roles/storage.admin"
```

### Database: Re-initialize

The init script is idempotent:
```bash
SKIP_IMAGE_BUILD=true SKIP_CQ_START=true ./scripts/deploy.sh
```

## Tech Stack

| Component | Technology |
|---|---|
| Source Database | Cloud SQL for PostgreSQL |
| CDC | Debezium PostgreSQL Source Connector (Managed or Cloud Run) |
| Message Broker | Google Managed Service for Apache Kafka |
| Ingestion Runtime | Google Managed Kafka Connect (built-in) / Cloud Run (optional) |
| CDC Archive | Google Cloud Storage (JSON on GCS) |
| Sink | BigQuery Sink Connector (Managed Kafka Connect) |
| In-Flight Processing | Kafka Connect SMTs (ReplaceField, Filter) |
| Transformations | BigQuery Continuous Queries + Scheduled Queries |
| Data Warehouse | Google BigQuery (Bronze / Silver / Gold) |
| Gold Table Format | Apache Iceberg (Managed) on GCS |
| Infrastructure | Terraform (google / google-beta providers) |
| Containerization | Cloud Build + Artifact Registry |
| Testing | pytest |

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

