# Real-Time CDC Pipeline: Cloud SQL → Kafka → BigQuery

A reference implementation of an end-to-end, serverless streaming data pipeline on Google Cloud. This demo captures transactional data changes (CDC) from a PostgreSQL database, streams them through Google Managed Kafka, and models them into a real-time BigQuery star schema using Continuous Queries.

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────────────────────┐
│  Cloud SQL   │     │   Managed    │     │           BigQuery               │
│  PostgreSQL  │────▶│    Kafka     │────▶│  Bronze → Silver → Gold (SCD2)  │
│  (CDC Source)│     │   (Broker)   │     │  via Continuous Queries          │
└──────────────┘     └──────────────┘     └──────────────────────────────────┘
        │                    ▲    │
        │                    │    │
        └──── Debezium ──────┘    └──── BQ Sink ────┐
              Source Connector         Connector     │
        ┌─────────────────┐    ┌─────────────────┐  │
        │  Cloud Run      │    │  Cloud Run      │──┘
        │  connect-source │    │  connect-sink   │
        │  (1 instance)   │    │  (1-4 instances)│
        └─────────────────┘    └─────────────────┘
```

**Key components:**

- **Cloud SQL for PostgreSQL** — OLTP source with logical decoding enabled for CDC
- **Google Managed Service for Apache Kafka** — Central message broker with per-table topics
- **Kafka Connect on Cloud Run (split architecture):**
  - **Source service** — Debezium CDC connector, fixed at 1 instance (1 replication slot)
  - **Sink service** — BigQuery Sink connector, scalable 1–4 instances
- **BigQuery Continuous Queries** — Real-time transformations across three layers:
  - **Bronze** — Append-only raw CDC events (Debezium envelope)
  - **Silver** — Current-state entity tables with soft-delete handling
  - **Gold** — Star schema with SCD Type 2 dimensions and point-in-time–correct fact tables

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
connect/            # Kafka Connect Dockerfile and connector configs
scripts/            # Deployment and teardown shell scripts
transform/          # BigQuery Continuous Query SQL scripts
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
  │ connect-source │      │  │  Connector    │  │  10.0.1.0/24  │   │
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
| Subnet (`10.0.1.0/24`) | `google_compute_subnetwork` | Primary CIDR for compute and managed services |
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
| `chinook.public.customer` | `customer` |
| `chinook.public.employee` | `employee` |
| `chinook.public.artist` | `artist` |
| `chinook.public.album` | `album` |
| `chinook.public.track` | `track` |
| `chinook.public.genre` | `genre` |
| `chinook.public.media_type` | `media_type` |
| `chinook.public.invoice` | `invoice` |
| `chinook.public.invoice_line` | `invoice_line` |
| `chinook.public.playlist` | `playlist` |
| `chinook.public.playlist_track` | `playlist_track` |

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

## Kafka Connect (Cloud Run — Split Architecture)

Two independent Kafka Connect services run on Cloud Run for production-like isolation and scalability:

| Service | Cloud Run Name | Scaling | Description |
|---|---|---|---|
| **Source** | `cdc-demo-connect-source` | Fixed: 1 instance | Debezium CDC from Cloud SQL → Kafka |
| **Sink** | `cdc-demo-connect-sink` | 1–4 instances | Kafka → BigQuery bronze layer |

**Why split?** The source connector is bound to a single PostgreSQL replication slot (can't parallelize), while the sink can scale independently based on throughput. Separate services provide independent failure domains, scaling, and deployment.

**Docker image contents (`connect/Dockerfile`):**
- Base: `confluentinc/cp-kafka-connect:7.7.1`
- Debezium PostgreSQL Source Connector (v2.7.3.Final)
- BigQuery Sink Connector (v2.6.3)
- Google Managed Kafka auth library (v1.0.6) for SASL/OAUTHBEARER

**SMT (Single Message Transforms) on the BigQuery Sink:**
- `ReplaceField$Value` — drops `phone` and `fax` fields from all records
- `Filter` with `RecordIsTombstone` predicate — filters out tombstone delete markers

**Registering connectors:**

```bash
# Set env vars, then run:
./connect/register-connectors.sh
```

**Verifying connector status:**

```bash
# Source service
SOURCE_URL=$(gcloud run services describe cdc-demo-connect-source \
  --region=europe-west1 --format="value(status.url)")
curl ${SOURCE_URL}/connectors/debezium-source/status

# Sink service
SINK_URL=$(gcloud run services describe cdc-demo-connect-sink \
  --region=europe-west1 --format="value(status.url)")
curl ${SINK_URL}/connectors/bigquery-sink/status
```

## BigQuery Data Warehouse (Bronze / Silver / Gold)

Three-layer **medallion architecture** for CDC data processing:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     Bronze      │     │     Silver      │     │      Gold       │
│  (Raw CDC)      │────▶│  (Current State)│────▶│  (Star Schema)  │
│                 │ CQ  │                 │ CQ  │  Apache Iceberg │
│  11 tables      │     │  11 tables      │     │  3 dims + 2 fct │
│  Debezium JSON  │     │  Typed columns  │     │  Parquet on GCS │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Bronze layer** (`bronze` dataset) — 11 `*_raw` tables with Debezium envelope columns:
`before`, `after` (JSON), `op` (c/u/d/r), `ts_ms`, `source`

**Silver layer** (`silver` dataset) — hybrid approach:
- **5 persistent tables** (customer, employee, track, invoice, invoice_line) — populated by CQs, used as Gold CQ streaming sources
- **6 views on Bronze** (artist, album, genre, media_type, playlist, playlist_track) — reference/lookup data that rarely changes, uses `QUALIFY ROW_NUMBER()` for current-state dedup without CQ overhead
- All expose: `is_deleted`, `_loaded_at`, `_source_ts_ms`

**Gold layer** (`gold` dataset) — **Managed Apache Iceberg** tables (Parquet on GCS):
- **Dimensions (SCD Type 2):** `dim_customer`, `dim_track` (denormalized with album/artist/genre/media_type), `dim_employee`
  - Each change creates a new row with `surrogate_key` (UUID), `valid_from`, `valid_to`, `is_active`
- **Facts:** `fct_invoice`, `fct_invoice_line` with surrogate key references and computed `line_total`
- **Interoperability:** Data stored as Parquet in GCS (`gs://<project>-iceberg-gold/`) — queryable by Spark, Trino, Flink, or any Iceberg-compatible engine

**Continuous Queries** (`transform/*.sql`) — Launched via `bq query --continuous=true`:
- **5 Bronze → Silver CQs** for core entities (reference tables use views instead)
- **5 Silver → Gold CQs** for dimensions and facts
- BigQuery CQs are **INSERT-only** using `APPENDS()` — no MERGE support
- Requires BigQuery **Enterprise edition** with slot reservations

## Getting Started

### 1. Configure

```bash
cp .env.example .env
# Edit .env with your GCP project ID, region, and other settings
```

### 2. Provision Infrastructure

```bash
cd infra
terraform init
terraform apply
```

### 3. Deploy Pipeline

```bash
# Build and push Kafka Connect image, initialize database, start Continuous Queries
./scripts/deploy.sh
```

### 4. Verify

Insert, update, or delete rows in the PostgreSQL database and query BigQuery to see changes reflected in the Gold layer within ~60 seconds.

```bash
# Connect to Cloud SQL
gcloud sql connect <instance-name> --user=<replication-user> --database=<database>

# Query BigQuery Gold layer
bq query --use_legacy_sql=false 'SELECT * FROM gold.dim_customer WHERE is_active = TRUE LIMIT 10'
```

### 5. Teardown

```bash
# Cancel Continuous Queries and clean up stateful resources
./scripts/teardown.sh

# Destroy all infrastructure
cd infra
terraform destroy
```

> **Important:** Always run `teardown.sh` before `terraform destroy` to avoid orphaned Continuous Queries and locked replication slots.

## Testing

```bash
uv run pytest tests/ -v
```

## Tech Stack

| Component | Technology |
|---|---|
| Source Database | Cloud SQL for PostgreSQL |
| CDC | Debezium PostgreSQL Source Connector |
| Message Broker | Google Managed Service for Apache Kafka |
| Ingestion Runtime | Kafka Connect on Cloud Run |
| Sink | BigQuery Kafka Sink Connector |
| In-Flight Processing | Kafka Connect SMTs (ReplaceField, Filter) |
| Transformations | BigQuery Continuous Queries |
| Data Warehouse | Google BigQuery (Bronze / Silver / Gold) |
| Infrastructure | Terraform (google / google-beta providers) |
| Containerization | Cloud Build + Artifact Registry |
| Testing | pytest |

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
