# Architecture Design Document: Real-Time CDC Pipeline with Managed Kafka & BQ Continuous Queries

## 1. Executive Summary
The objective of this demo is to build an end-to-end, serverless streaming data pipeline on Google Cloud. This architecture demonstrates the ingestion of transactional data changes (CDC) from a PostgreSQL database, event streaming via Google Managed Service for Apache Kafka, in-flight transformation (filtering/masking), and real-time modeling into a BigQuery Star Schema (Bronze, Silver, Gold) making extensive use of **BigQuery Continuous Queries (CQ)**.

## 2. Architecture Components & Configuration Guidelines

### 2.1. Source System: Cloud SQL for PostgreSQL
The OLTP demo database is hosted on Cloud SQL.
*   **Prerequisite:** Logical decoding must be enabled for CDC.
*   **Configuration:**
    *   Set the database flag `cloudsql.logical_decoding=on`.
    *   Set the `wal_level` parameter to `logical`.
    *   Create a dedicated replication user with the `REPLICATION` role.
    *   Create a Logical Replication Slot for Debezium (using the standard `pgoutput` plugin).

### 2.2. Streaming Broker: Google Managed Service for Apache Kafka
Serves as the central message broker.
*   **Setup:** Provision a Google Managed Kafka cluster.
*   **Topics:** Configure dedicated topics per source table (e.g., `cdc.public.customers`, `cdc.public.orders`).
*   **Security:** IAM-based setup. The Service Account associated with the Kafka Connect runtime requires appropriate roles (e.g., `roles/managedkafka.client`).

### 2.3. CDC Ingestion & Sink: Kafka Connect on Cloud Run
To keep the demo infrastructure as "serverless" as possible, Kafka Connect is deployed as a custom container on Cloud Run.
*   **Container Image:** A custom Docker image based on the official Kafka Connect image, including the following plugins:
    1.  Debezium PostgreSQL Source Connector.
    2.  BigQuery Kafka Sink Connector (from Confluent or Google).
*   **Cloud Run Configuration:**
    *   The service must run with **"CPU always allocated"**, as Kafka Connect requires a continuous background process.
    *   Set `min-instances` to `1` to prevent cold starts and connection drops.
    *   Configure VPC Serverless Access (or Direct VPC Egress) to allow Cloud Run to communicate with the private IP of the Cloud SQL instance and the Managed Kafka cluster.

### 2.4. In-Flight Processing (Filtering & Transforming before Sink)
The logic for filtering messages and removing specific properties is handled entirely without code, utilizing **Single Message Transforms (SMTs)** within the BigQuery Sink Connector configuration.
*   **Removing Properties:** Use the `ReplaceField$Value` SMT (e.g., `transforms.MaskFields.type=org.apache.kafka.connect.transforms.ReplaceField$Value`, followed by `transforms.MaskFields.exclude=credit_card,ssn`).
*   **Filtering Messages:** Use the `Filter` SMT (e.g., `org.apache.kafka.connect.transforms.Filter`) to exclude messages from being written to the BigQuery sink based on payload criteria (e.g., specific record types or status updates).

## 3. Data Warehouse Layer: BigQuery Continuous Queries (CQ) & Scheduled Queries
The BigQuery Sink Connector continuously writes the records into BigQuery. It is configured with `value.converter.schemas.enable=true`, which produces properly typed RECORD columns. From this point on, BigQuery Continuous Queries and Scheduled Queries take over the real-time transformations.

### 3.1. Bronze Layer (Raw Data)
*   **Structure:** Append-only tables that represent a 1:1 reflection of the Kafka topics.
*   **Content:** Contains the standard Debezium payload (`before`, `after`, `op` [Create, Update, Delete], `ts_ms`) stored as typed RECORD/struct columns instead of JSON.
*   **Setup:** Native BigQuery tables (not external tables).

### 3.2. Silver Layer (Cleansed / Current State)
*   **Goal:** Provide the current state of the OLTP entities without historical data.
*   **Hybrid Approach:** The layer uses a hybrid approach: 5 tables populated by Continuous Queries for complex transformations, and 6 views directly on the Bronze tables for simpler state representations.
*   **Implementation:**
    *   Since Bronze tables use RECORD/struct columns, Silver accesses the fields directly via `after.field_name` struct access instead of parsing JSON (`JSON_VALUE`).
    *   For the CQ-populated tables, a Continuous Query continuously reads from the Bronze table.
    *   It uses `MERGE` statements (if fully supported by CQ in the demo phase) or calculates the latest record per key (`QUALIFY ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_ms DESC) = 1`) to update the Silver tables.
    *   Soft deletes (`op = 'd'`) from Debezium are converted into a boolean flag (`is_deleted = TRUE`).

### 3.3. Gold Layer (Star Schema & SCD Type 2)
The Gold Layer provides real-time data for analytics and dashboards. It uses **Scheduled Queries** (every 5 minutes) rather than Continuous Queries because Iceberg tables don't support CQs.

**Dimensions (SCD Type 2):**
*   **Structure:** Tables containing the columns `surrogate_key`, `natural_key`, `valid_from`, `valid_to`, `is_active`.
*   **Surrogate Keys:** Since incremental IDs are difficult to manage in distributed streaming, hashes are used. Generate them using `FARM_FINGERPRINT(CAST(natural_key AS STRING))` or `GENERATE_UUID()` if deterministic keys are not strictly required.
*   **Scheduled Query Implementation for SCD2:**
    *   A Scheduled Query (running every 5 minutes) monitors the Silver (or directly Bronze) layer.
    *   Upon receiving an entity update (`op = 'u'`), the Scheduled Query performs two actions:
        1.  Closes the existing active record (updates `valid_to` to `CURRENT_TIMESTAMP()` and sets `is_active = FALSE`).
        2.  Inserts the new record as a new row with a new surrogate key, `valid_from = CURRENT_TIMESTAMP()`, and `is_active = TRUE`.

**Fact Tables:**
*   **Structure:** Classic fact tables containing only surrogate keys (linking to dimensions) and metrics/measures.
*   **Scheduled Query Implementation:**
    *   A Scheduled Query (running every 5 minutes) processes incoming transaction events (e.g., new orders).
    *   The statement joins the incoming row against the *dimension tables* based on the natural key.
    *   **Crucial:** The join must be point-in-time correct. The transaction timestamp must fall between the `valid_from` and `valid_to` of the SCD2 dimension to fetch the correct surrogate key valid at the exact time of the transaction.
    *   The Scheduled Query streams the enriched result (via INSERT) into the final fact table.

**Current-State Views:**
*   **Views:** `v_dim_customer`, `v_dim_employee`, `v_dim_track`, `v_fct_invoice`, `v_fct_invoice_line`.

---

## 4. Next Steps for the Solution Architect
1.  **Review VPC Architecture:** Define Serverless Access Connectors or Direct Egress for Cloud Run to securely access both the private Cloud SQL instance and the Managed Kafka cluster.
2.  **Create Dockerfile:** Build the Dockerfile for the Kafka Connect container, ensuring Debezium and the BQ Sink Connector are properly installed and configured.
3.  **Draft CQ SQL Scripts:** Formulate the exact SQL statements for the SCD Type 2 transformations, as these contain the most complex logical patterns within the pipeline.

---

## 5. Deployment & Lifecycle Management (IaC)

To ensure a reproducible and automated lifecycle for the demo, **Terraform** acts as the primary Infrastructure as Code (IaC) tool. Any configuration steps not natively or reliably supported by the Terraform provider are handled via auxiliary setup scripts (Bash/Python) leveraging the `gcloud`, `bq`, and `psql` command-line interfaces.

**5.1. Terraform Scope (Infrastructure Provisioning)**
Terraform is responsible for deploying all foundational Google Cloud resources and managing IAM configurations.
*   **Networking:** VPC, subnets, firewall rules, and Serverless VPC Access Connectors or Direct Egress configurations.
*   **Storage & Messaging:** Provisioning the Cloud SQL instance (`google_sql_database_instance`), Managed Kafka cluster (`google_managed_kafka_cluster`), and Kafka topics.
*   **Analytics Base:** Creation of BigQuery datasets (Bronze, Silver, Gold), the definition of the static destination tables (`google_bigquery_table`), and a BigQuery Enterprise reservation managed by Terraform (with autoscale and a CONTINUOUS job type).
*   **Compute:** Setting up Google Artifact Registry (`google_artifact_registry_repository`) and deploying the Kafka Connect custom container to Cloud Run (`google_cloud_run_v2_service`).
*   **Security:** Assigning required IAM bindings for the Cloud Run Service Account (e.g., roles for Managed Kafka, Cloud SQL Client, and BigQuery Data Editor).

**5.2. Scripting Scope (Post-Provisioning & Execution)**
Since continuous SQL processes and internal database configurations are stateful actions rather than static infrastructure, they are orchestrated via a deployment script immediately following `terraform apply`.
*   **Database Configuration:** Executing a `psql` command to create the logical replication slot (`pg_create_logical_replication_slot`) on the Cloud SQL PostgreSQL instance and initializing the demo schema/data.
*   **Container Image Build:** Running `gcloud builds submit` to package the Debezium and BigQuery Sink connectors into a Docker image and push it to the Artifact Registry prior to the Cloud Run deployment.
*   **Continuous Queries Lifecycle:** Terraform is not well-suited for managing the running state of a streaming SQL query. A script utilizing the `bq` CLI (e.g., `bq query --continuous`) or the BigQuery Python Client is used to start, monitor, and terminate the Continuous Queries for the Silver and Gold layer transformations.

**5.3. Teardown & Cleanup Routine**
The cleanup process must follow a specific sequence to avoid dangling processes or locking issues before destroying the infrastructure.
1.  **Script Teardown:**
    *   Cancel all running BigQuery Continuous Queries using the `bq` CLI to stop stream inserts.
    *   Drop the logical replication slot in PostgreSQL via a `psql` command to release WAL logs.
2.  **Terraform Teardown:** Execute `terraform destroy` to remove all provisioned infrastructure (Cloud Run, Managed Kafka, Cloud SQL, and BigQuery datasets).
