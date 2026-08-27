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
              ┌────────────────────────────────┐     │
              │    Kafka Connect on Cloud Run  │─────┘
              │    (CPU always allocated)      │
              └────────────────────────────────┘
```

**Key components:**

- **Cloud SQL for PostgreSQL** — OLTP source with logical decoding enabled for CDC
- **Google Managed Service for Apache Kafka** — Central message broker with per-table topics
- **Kafka Connect on Cloud Run** — Runs Debezium (source) and BigQuery Sink connectors in a custom Docker container
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
  │   Cloud Run    │──────┼──│  VPC Access   │  │   Subnet      │   │
  │ (Kafka Connect)│      │  │  Connector    │  │  10.0.1.0/24  │   │
  └────────────────┘      │  │ 10.8.0.0/28  │  └───────┬───────┘   │
                          │  └──────┬───────┘          │           │
                          │         │                  │           │
                          │         ▼                  ▼           │
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
