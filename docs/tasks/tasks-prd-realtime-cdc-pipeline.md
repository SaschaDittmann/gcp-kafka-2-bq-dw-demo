# Tasks: Real-Time CDC Pipeline with Managed Kafka & BigQuery Continuous Queries

## Relevant Files

- `infra/main.tf` - Root Terraform module, provider configuration, and API enablement
- `infra/variables.tf` - Input variables (project, region, naming prefixes)
- `infra/outputs.tf` - Terraform outputs (IPs, connection strings, service URLs)
- `infra/terraform.tfvars.example` - Example variable values for users
- `infra/network.tf` - VPC, subnets, firewall rules, VPC connectors
- `infra/iam.tf` - Service accounts and IAM role bindings
- `infra/cloudsql.tf` - Cloud SQL instance, database, and users
- `infra/kafka.tf` - Managed Kafka cluster and topic definitions
- `infra/bigquery.tf` - BigQuery datasets and all table schemas (bronze, silver, gold)
- `infra/artifact_registry.tf` - Artifact Registry repository
- `infra/cloudrun.tf` - Cloud Run service for Kafka Connect
- `data/chinook_schema.sql` - Chinook database DDL (tables, constraints)
- `data/chinook_seed.sql` - Chinook sample data INSERT statements
- `data/init_db.sh` - Database initialization script (schema, seed, replication slot)
- `connect/Dockerfile` - Custom Kafka Connect image with Debezium + BQ Sink
- `connect/debezium-source.json` - Debezium PostgreSQL Source Connector configuration
- `connect/bigquery-sink.json` - BigQuery Sink Connector configuration (including SMTs)
- `connect/register-connectors.sh` - Script to register connectors via REST API
- `transform/silver_customer.sql` - CQ: Bronze → Silver for customer
- `transform/silver_employee.sql` - CQ: Bronze → Silver for employee
- `transform/silver_artist.sql` - CQ: Bronze → Silver for artist
- `transform/silver_album.sql` - CQ: Bronze → Silver for album
- `transform/silver_track.sql` - CQ: Bronze → Silver for track
- `transform/silver_genre.sql` - CQ: Bronze → Silver for genre
- `transform/silver_media_type.sql` - CQ: Bronze → Silver for media_type
- `transform/silver_invoice.sql` - CQ: Bronze → Silver for invoice
- `transform/silver_invoice_line.sql` - CQ: Bronze → Silver for invoice_line
- `transform/silver_playlist.sql` - CQ: Bronze → Silver for playlist
- `transform/silver_playlist_track.sql` - CQ: Bronze → Silver for playlist_track
- `transform/gold_dim_customer.sql` - CQ: Silver → Gold SCD2 dim_customer
- `transform/gold_dim_track.sql` - CQ: Silver → Gold SCD2 dim_track (denormalized with album, artist, genre, media_type)
- `transform/gold_dim_employee.sql` - CQ: Silver → Gold SCD2 dim_employee
- `transform/gold_fct_invoice.sql` - CQ: Silver → Gold fct_invoice (with dimension surrogate key lookups)
- `transform/gold_fct_invoice_line.sql` - CQ: Silver → Gold fct_invoice_line (with dimension surrogate key lookups)
- `scripts/deploy.sh` - Full deployment orchestration script
- `scripts/teardown.sh` - Full teardown and cleanup script
- `tests/test_deploy.py` - End-to-end tests for deploy script
- `tests/test_teardown.py` - End-to-end tests for teardown script
- `tests/test_cdc_pipeline.py` - End-to-end CDC flow, latency, and correctness tests
- `tests/test_pii_masking.py` - Tests verifying phone/fax fields are excluded from BigQuery
- `tests/test_scd2.py` - Tests verifying SCD Type 2 dimension correctness
- `README.md` - Updated project README with architecture overview, setup, and usage

### Notes

- Each parent task represents a complete vertical slice (code + tests + observability + docs)
- Tasks are ordered by dependency: networking → Cloud SQL → Kafka → Kafka Connect → BigQuery → scripts
- The Chinook database schema and seed data should be sourced from the [official Chinook repository](https://github.com/lerocha/chinook-database)
- BigQuery Continuous Query syntax should be validated against current documentation before implementation
- Managed Kafka Terraform resource (`google_managed_kafka_cluster`) stability should be verified via Context7 / provider docs

## Tasks

- [x] 1.0 Networking & Foundational Terraform Infrastructure (Complete Vertical Slice)
  - [x] 1.1 Create Terraform project scaffolding: `infra/main.tf` with `google` and `google-beta` provider configuration, required API enablement (`sqladmin.googleapis.com`, `managedkafka.googleapis.com`, `bigquery.googleapis.com`, `run.googleapis.com`, `artifactregistry.googleapis.com`, `cloudbuild.googleapis.com`, `compute.googleapis.com`, `vpcaccess.googleapis.com`), local backend, and `infra/variables.tf` with inputs for `project_id`, `region` (default `europe-west1`), and naming prefixes
  - [x] 1.2 Define VPC and subnets in `infra/network.tf`: create a custom VPC with a single subnet in `europe-west1`, including secondary ranges if needed for Cloud Run Direct VPC Egress; add firewall rules allowing internal communication between Cloud Run, Cloud SQL, and Managed Kafka
  - [x] 1.3 Define a Serverless VPC Access Connector (or configure Direct VPC Egress) in `infra/network.tf` to enable Cloud Run to reach private Cloud SQL and Managed Kafka endpoints
  - [x] 1.4 Define service accounts and IAM bindings in `infra/iam.tf`: create a dedicated service account for Cloud Run/Kafka Connect with roles `roles/managedkafka.client`, `roles/cloudsql.client`, `roles/bigquery.dataEditor`, `roles/bigquery.jobUser`, and `roles/artifactregistry.reader`
  - [x] 1.5 Create `infra/outputs.tf` exporting VPC ID, subnet self-links, service account email, and VPC connector name; create `infra/terraform.tfvars.example` with placeholder values
  - [x] 1.6 Write tests in `tests/test_infra_networking.py` to validate Terraform configuration: run `terraform validate` and `terraform plan` and assert no errors; verify expected resource counts
  - [x] 1.7 Add logging annotations and labels to all Terraform resources for traceability (e.g., `labels = { managed_by = "terraform", project = "cdc-pipeline-demo" }`)
  - [x] 1.8 Document the networking architecture in `README.md` including a diagram of VPC topology and connectivity between services

- [x] 2.0 Cloud SQL for PostgreSQL & Database Initialization (Complete Vertical Slice)
  - [x] 2.1 Define Cloud SQL instance in `infra/cloudsql.tf`: `google_sql_database_instance` with PostgreSQL 15+, `db-f1-micro` tier, 10 GB SSD, `europe-west1`, private IP on the VPC, and database flags `cloudsql.logical_decoding=on`
  - [x] 2.2 Define `google_sql_database` (database name: `chinook`) and `google_sql_user` (replication user) in `infra/cloudsql.tf`; output the instance connection name and private IP in `infra/outputs.tf`
  - [x] 2.3 Create `data/chinook_schema.sql` with the full Chinook DDL: all 11 tables (`customer`, `employee`, `artist`, `album`, `track`, `genre`, `media_type`, `invoice`, `invoice_line`, `playlist`, `playlist_track`) with primary keys, foreign keys, and constraints; source from the official Chinook repository and adapt for PostgreSQL
  - [x] 2.4 Create `data/chinook_seed.sql` with INSERT statements for all Chinook sample data (~59 customers, 8 employees, 275 artists, 347 albums, 3,503 tracks, 25 genres, 5 media types, 412 invoices, 2,240 invoice lines, 18 playlists); source from the official Chinook repository
  - [x] 2.5 Create `data/init_db.sh` that: connects to Cloud SQL via `psql`, grants the replication user the `REPLICATION` role, runs `chinook_schema.sql`, runs `chinook_seed.sql`, creates the logical replication slot via `SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput')`, and creates a publication for all tables via `CREATE PUBLICATION debezium_publication FOR ALL TABLES`; add error handling and logging throughout
  - [x] 2.6 Write end-to-end tests in `tests/test_database_init.py`: verify the schema exists (table count = 11), seed data row counts match expectations, replication slot exists, and publication exists; include failure case for invalid connection and edge case for idempotent re-runs
  - [x] 2.7 Add structured logging to `data/init_db.sh` (timestamped output for each step, exit codes on failure)
  - [x] 2.8 Document the database setup in `README.md` including the Chinook schema, how to connect to Cloud SQL, and how to re-initialize

- [x] 3.0 Google Managed Kafka Cluster & Topics (Complete Vertical Slice)
  - [x] 3.1 Define Managed Kafka cluster in `infra/kafka.tf` using `google_managed_kafka_cluster` (verify resource availability in `google` or `google-beta` provider via Context7); configure smallest available cluster size, `europe-west1`, VPC connectivity, and IAM authentication
  - [x] 3.2 Define Kafka topics in `infra/kafka.tf` using `google_managed_kafka_topic` for all 11 source tables following the naming convention `chinook.public.<table_name>` (e.g., `chinook.public.customer`, `chinook.public.invoice`, `chinook.public.track`, etc.); configure appropriate partition count (1 for demo) and replication factor
  - [x] 3.3 Add Kafka cluster ID, bootstrap server endpoint, and topic names to `infra/outputs.tf`
  - [x] 3.4 Write tests in `tests/test_infra_kafka.py`: validate Terraform plan includes the Kafka cluster and all 11 topics; verify topic naming convention matches Debezium defaults
  - [x] 3.5 Add labels and descriptions to all Kafka Terraform resources for observability
  - [x] 3.6 Document the Kafka cluster setup in `README.md` including topic naming convention, expected provisioning time (15–30 min), and how to verify cluster health

- [ ] 4.0 Kafka Connect on Cloud Run — Debezium Source & BigQuery Sink (Complete Vertical Slice)
  - [ ] 4.1 Create `connect/Dockerfile` based on the official Kafka Connect image; install Debezium PostgreSQL Source Connector and BigQuery Kafka Sink Connector JARs into the plugin path; configure `CONNECT_BOOTSTRAP_SERVERS`, `CONNECT_GROUP_ID`, `CONNECT_KEY_CONVERTER`, `CONNECT_VALUE_CONVERTER` (JSON, no schema registry) via environment variables
  - [ ] 4.2 Define Artifact Registry repository in `infra/artifact_registry.tf` (`google_artifact_registry_repository`, Docker format, `europe-west1`)
  - [ ] 4.3 Define Cloud Run service in `infra/cloudrun.tf` (`google_cloud_run_v2_service`): reference the Artifact Registry image, set `cpu_always_allocated = true`, `min_instance_count = 1`, attach the service account from Task 1.4, configure VPC egress via the connector from Task 1.3, and set environment variables for Kafka bootstrap servers and connector configuration
  - [ ] 4.4 Create `connect/debezium-source.json` with the Debezium PostgreSQL Source Connector configuration: `connector.class`, `database.hostname` (Cloud SQL private IP), `database.port`, `database.user`, `database.password`, `database.dbname=chinook`, `topic.prefix=chinook`, `table.include.list=public.*`, `plugin.name=pgoutput`, `slot.name=debezium_slot`, `publication.name=debezium_publication`, JSON converter settings
  - [ ] 4.5 Create `connect/bigquery-sink.json` with the BigQuery Sink Connector configuration: `connector.class`, `topics.regex=chinook\\.public\\..*`, `project`, `datasets=bronze`, `autoCreateTables=false`, JSON converter settings; add SMTs: `ReplaceField$Value` to exclude `phone` and `fax` fields from all topics; optionally add `Filter` SMT for tombstone records
  - [ ] 4.6 Create `connect/register-connectors.sh` that waits for the Kafka Connect REST API to become healthy (`GET /`), then registers the source connector (`POST /connectors` with `debezium-source.json`) and sink connector (`POST /connectors` with `bigquery-sink.json`); include retry logic, error handling, and logging
  - [ ] 4.7 Write tests in `tests/test_connector_configs.py`: validate JSON syntax of both connector configs; verify required fields are present; verify SMT configuration excludes `phone` and `fax`; verify topic regex matches expected Debezium topic names
  - [ ] 4.8 Add structured logging to `connect/register-connectors.sh` (timestamped output, HTTP response codes, connector status checks)
  - [ ] 4.9 Document the Kafka Connect setup in `README.md` including the Dockerfile contents, connector configuration details, SMT behavior, and how to verify connector status via the REST API

- [ ] 5.0 BigQuery Data Warehouse — Bronze, Silver & Gold Layers (Complete Vertical Slice)
  - [ ] 5.1 Define BigQuery datasets in `infra/bigquery.tf`: create `google_bigquery_dataset` for `bronze`, `silver`, and `gold` datasets in `europe-west1`
  - [ ] 5.2 Define Bronze layer tables in `infra/bigquery.tf`: create `google_bigquery_table` for each of the 11 source tables (e.g., `customer_raw`, `invoice_raw`, `track_raw`) with schema columns matching the Debezium envelope structure (`before` as JSON/STRING, `after` as JSON/STRING, `op` as STRING, `ts_ms` as INTEGER, `source` as JSON/STRING)
  - [ ] 5.3 Define Silver layer tables in `infra/bigquery.tf`: create `google_bigquery_table` for all 11 entities (`customer`, `employee`, `artist`, `album`, `track`, `genre`, `media_type`, `invoice`, `invoice_line`, `playlist`, `playlist_track`) with entity-specific columns plus `is_deleted` BOOLEAN and `_loaded_at` TIMESTAMP
  - [ ] 5.4 Define Gold layer tables in `infra/bigquery.tf`: create dimension tables (`dim_customer`, `dim_track`, `dim_employee`) with columns `surrogate_key`, `natural_key`, `valid_from`, `valid_to`, `is_active`, plus entity attributes; `dim_track` denormalizes album, artist, genre, and media_type; create fact tables (`fct_invoice`, `fct_invoice_line`) with surrogate key references and measures
  - [ ] 5.5 Write Bronze → Silver Continuous Query SQL scripts in `transform/`: one file per entity (e.g., `silver_customer.sql`, `silver_employee.sql`, ..., `silver_playlist_track.sql`); each CQ reads from the corresponding Bronze table, extracts fields from the `after` payload, applies deduplication per primary key ordered by `ts_ms`, converts `op='d'` to `is_deleted=TRUE`, and MERGEs or INSERTs into the Silver table
  - [ ] 5.6 Write Silver → Gold dimension CQ SQL scripts in `transform/`: `gold_dim_customer.sql`, `gold_dim_track.sql` (joining silver track + album + artist + genre + media_type), `gold_dim_employee.sql`; each CQ reads from the Silver layer, closes the existing active record on change (`valid_to = CURRENT_TIMESTAMP()`, `is_active = FALSE`), and inserts a new active record with a new surrogate key (`GENERATE_UUID()` or `FARM_FINGERPRINT`)
  - [ ] 5.7 Write Silver → Gold fact CQ SQL scripts in `transform/`: `gold_fct_invoice.sql` and `gold_fct_invoice_line.sql`; each CQ reads from the Silver layer, joins against active dimension records using natural keys with point-in-time correctness (transaction timestamp between `valid_from` and `valid_to`), and INSERTs enriched rows with surrogate keys and measures
  - [ ] 5.8 Write tests in `tests/test_bigquery_schemas.py`: validate Terraform plan includes all 3 datasets, 11 Bronze tables, 11 Silver tables, 3 dimension tables, and 2 fact tables; verify column names and types match PRD specifications
  - [ ] 5.9 Write tests in `tests/test_continuous_queries.py`: validate SQL syntax of all CQ scripts; verify each CQ references the correct source and target tables; verify `dim_track` joins include album, artist, genre, and media_type
  - [ ] 5.10 Add `_loaded_at` and `_source_ts_ms` metadata columns to Silver and Gold tables for observability and lineage tracking
  - [ ] 5.11 Document the BigQuery layer architecture in `README.md` including the Bronze/Silver/Gold pattern, table naming conventions, CQ behavior, and SCD Type 2 logic

- [ ] 6.0 Deployment & Teardown Scripts + End-to-End Testing (Complete Vertical Slice)
  - [ ] 6.1 Create `scripts/deploy.sh` that orchestrates the full post-Terraform deployment: (1) runs `data/init_db.sh` for database initialization, (2) builds and pushes the Kafka Connect Docker image via `gcloud builds submit`, (3) waits for the Cloud Run service to become healthy, (4) runs `connect/register-connectors.sh` to register Source and Sink connectors, (5) starts all BigQuery Continuous Queries by executing the SQL scripts in `transform/` via `bq query`; include prerequisite checks, error handling, and step-by-step logging
  - [ ] 6.2 Create `scripts/teardown.sh` that cleans up before `terraform destroy`: (1) cancels all running BigQuery Continuous Queries via `bq cancel` or the BigQuery API, (2) drops the logical replication slot in PostgreSQL via `psql`, (3) deletes the Debezium publication; include error handling for resources that may already be deleted
  - [ ] 6.3 Write end-to-end tests in `tests/test_cdc_pipeline.py`: insert a row in PostgreSQL and verify it appears in BigQuery Bronze, Silver, and Gold layers within 60 seconds; update a row and verify SCD Type 2 dimension history; delete a row and verify `is_deleted` flag in Silver
  - [ ] 6.4 Write tests in `tests/test_pii_masking.py`: query all BigQuery Bronze, Silver, and Gold tables and assert that no `phone` or `fax` columns exist; verify SMT configuration is applied correctly
  - [ ] 6.5 Write tests in `tests/test_scd2.py`: update a customer record multiple times and verify `dim_customer` contains correct `valid_from`/`valid_to` ranges and `is_active` flags; verify `fct_invoice` joins resolve to the correct surrogate key at the time of the invoice
  - [ ] 6.6 Write tests in `tests/test_deploy.py`: verify `deploy.sh` runs successfully end-to-end; verify `teardown.sh` cleans up all CQs and replication slots
  - [ ] 6.7 Add structured logging to both `deploy.sh` and `teardown.sh` with timestamped output, step numbering, success/failure indicators, and a final summary
  - [ ] 6.8 Update the project `README.md` with complete documentation: architecture overview, prerequisites, quickstart guide (`terraform apply` + `deploy.sh`), verification steps (sample BigQuery queries), teardown instructions (`teardown.sh` + `terraform destroy`), and troubleshooting tips

