#!/usr/bin/env bash
# =============================================================================
# Database Initialization Script
# =============================================================================
# Initializes the Chinook database on Cloud SQL for PostgreSQL:
#   1. Creates a GCS bucket for staging SQL files
#   2. Imports Chinook schema and seed data via gcloud sql import sql
#   3. Configures replication user, slot, and publication via gcloud sql import sql
#
# Uses `gcloud sql import sql` for all steps (via GCS staging).
# No VPC access, psql, or Cloud SQL Auth Proxy needed.
#
# Usage:
#   ./data/init_db.sh
#
# Required environment variables:
#   INSTANCE_NAME  - Cloud SQL instance name (e.g., cdc-demo-pg-5767f555)
#   PROJECT_ID     - GCP project ID
#   DB_NAME        - Database name (default: chinook)
#   DB_USER        - Admin user with CREATE/ALTER privileges (default: admin)
#   REPL_USER      - Replication user name (default: debezium)
#   REPL_PASSWORD  - Replication user password
#
# Optional:
#   GCS_BUCKET     - GCS bucket for staging SQL files (default: gs://<PROJECT_ID>-sql-import)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_NAME="${INSTANCE_NAME:?ERROR: INSTANCE_NAME environment variable is required}"
PROJECT_ID="${PROJECT_ID:?ERROR: PROJECT_ID environment variable is required}"
DB_NAME="${DB_NAME:-chinook}"
DB_USER="${DB_USER:-admin}"
REPL_USER="${REPL_USER:-debezium}"
REPL_PASSWORD="${REPL_PASSWORD:?ERROR: REPL_PASSWORD environment variable is required}"
GCS_BUCKET="${GCS_BUCKET:-gs://${PROJECT_ID}-sql-import}"

STEP=0
TOTAL_STEPS=6
ERRORS=0

# -----------------------------------------------------------------------------
# Logging Helpers
# -----------------------------------------------------------------------------

log_info() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*"
}

log_step() {
  STEP=$((STEP + 1))
  echo ""
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [STEP ${STEP}/${TOTAL_STEPS}] $*"
  echo "-----------------------------------------------------------------------"
}

log_error() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
  ERRORS=$((ERRORS + 1))
}

log_success() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*"
}

# -----------------------------------------------------------------------------
# Helper: Run SQL via gcloud sql connect
# Pipes SQL commands into an interactive psql session.
# -----------------------------------------------------------------------------

run_sql() {
  local sql="$1"
  local label="${2:-inline}"
  local user="${3:-${DB_USER}}"
  local tmp_file
  tmp_file=$(mktemp /tmp/init_db_XXXXXX.sql)
  echo "${sql}" > "${tmp_file}"

  gcloud storage cp "${tmp_file}" "${GCS_BUCKET}/${label}.sql" --quiet 2>&1
  rm -f "${tmp_file}"

  local import_rc=0
  gcloud sql import sql "${INSTANCE_NAME}" "${GCS_BUCKET}/${label}.sql" \
    --database="${DB_NAME}" \
    --user="${user}" \
    --project="${PROJECT_ID}" \
    --quiet 2>&1 || import_rc=$?

  gcloud storage rm "${GCS_BUCKET}/${label}.sql" --quiet 2>&1 || true

  return "${import_rc}"
}

# =============================================================================
# Main
# =============================================================================

log_info "Starting Chinook database initialization"
log_info "Instance: ${INSTANCE_NAME} | Database: ${DB_NAME} | Project: ${PROJECT_ID}"
echo ""

# ---- Step 1: Create GCS bucket for SQL file staging -------------------------

log_step "Creating GCS bucket for SQL file staging"

if gcloud storage buckets describe "${GCS_BUCKET}" --project="${PROJECT_ID}" > /dev/null 2>&1; then
  log_info "Bucket ${GCS_BUCKET} already exists — skipping creation"
else
  gcloud storage buckets create "${GCS_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="$(echo "${INSTANCE_NAME}" | grep -oP 'europe-west1' || echo 'europe-west1')" \
    --uniform-bucket-level-access 2>&1 \
    && log_success "Created staging bucket ${GCS_BUCKET}" \
    || { log_error "Failed to create GCS bucket"; exit 1; }
fi

# Grant the Cloud SQL service account read access to the bucket
SA_EMAIL=$(gcloud sql instances describe "${INSTANCE_NAME}" \
  --project="${PROJECT_ID}" \
  --format="value(serviceAccountEmailAddress)")

gcloud storage buckets add-iam-policy-binding "${GCS_BUCKET}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectViewer" \
  --project="${PROJECT_ID}" --quiet 2>&1 \
  && log_success "Granted Cloud SQL SA (${SA_EMAIL}) read access to bucket" \
  || { log_error "Failed to grant bucket access"; exit 1; }

# ---- Step 2: Upload and import Chinook schema ------------------------------

log_step "Importing Chinook schema via Cloud SQL import"

if [[ ! -f "${SCRIPT_DIR}/chinook_schema.sql" ]]; then
  log_error "Schema file not found: ${SCRIPT_DIR}/chinook_schema.sql"
  exit 1
fi

gcloud storage cp "${SCRIPT_DIR}/chinook_schema.sql" "${GCS_BUCKET}/chinook_schema.sql" --quiet 2>&1 \
  && log_info "Uploaded chinook_schema.sql to ${GCS_BUCKET}" \
  || { log_error "Failed to upload schema file"; exit 1; }

gcloud sql import sql "${INSTANCE_NAME}" "${GCS_BUCKET}/chinook_schema.sql" \
  --database="${DB_NAME}" \
  --user="${DB_USER}" \
  --project="${PROJECT_ID}" \
  --quiet 2>&1 \
  && log_success "Chinook schema imported successfully" \
  || { log_error "Failed to import schema"; exit 1; }

# ---- Step 3: Upload and import Chinook seed data ---------------------------

log_step "Importing Chinook seed data via Cloud SQL import"

if [[ ! -f "${SCRIPT_DIR}/chinook_seed.sql" ]]; then
  log_error "Seed file not found: ${SCRIPT_DIR}/chinook_seed.sql"
  exit 1
fi

gcloud storage cp "${SCRIPT_DIR}/chinook_seed.sql" "${GCS_BUCKET}/chinook_seed.sql" --quiet 2>&1 \
  && log_info "Uploaded chinook_seed.sql to ${GCS_BUCKET}" \
  || { log_error "Failed to upload seed file"; exit 1; }

gcloud sql import sql "${INSTANCE_NAME}" "${GCS_BUCKET}/chinook_seed.sql" \
  --database="${DB_NAME}" \
  --user="${DB_USER}" \
  --project="${PROJECT_ID}" \
  --quiet 2>&1 \
  && log_success "Chinook seed data imported successfully" \
  || { log_error "Failed to import seed data"; exit 1; }

# ---- Step 4: Create replication user ----------------------------------------

log_step "Creating replication user '${REPL_USER}' via Cloud SQL import"

run_sql "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} WITH LOGIN PASSWORD '${REPL_PASSWORD}' REPLICATION;
    RAISE NOTICE 'Created replication user ${REPL_USER}';
  ELSE
    ALTER ROLE ${REPL_USER} WITH PASSWORD '${REPL_PASSWORD}' REPLICATION;
    RAISE NOTICE 'Replication user ${REPL_USER} already exists — updated';
  END IF;
END
\$\$;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${REPL_USER};
" "repl_user" && log_success "Replication user '${REPL_USER}' is ready" \
   || { log_error "Failed to create replication user"; exit 1; }

# ---- Step 5: Create logical replication slot --------------------------------

log_step "Creating logical replication slot 'debezium_slot'"

run_sql "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'debezium_slot') THEN
    PERFORM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');
    RAISE NOTICE 'Created replication slot debezium_slot';
  ELSE
    RAISE NOTICE 'Replication slot debezium_slot already exists — skipping';
  END IF;
END
\$\$;
" "repl_slot" "${REPL_USER}" && log_success "Logical replication slot 'debezium_slot' is ready" \
   || { log_error "Failed to create replication slot"; exit 1; }

# ---- Step 6: Create publication for all tables ------------------------------

log_step "Creating publication 'debezium_publication' for all tables"

run_sql "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname = 'debezium_publication') THEN
    CREATE PUBLICATION debezium_publication FOR ALL TABLES;
    RAISE NOTICE 'Created publication debezium_publication';
  ELSE
    RAISE NOTICE 'Publication debezium_publication already exists — skipping';
  END IF;
END
\$\$;
" "publication" && log_success "Publication 'debezium_publication' is ready" \
   || { log_error "Failed to create publication"; exit 1; }

# =============================================================================
# Cleanup staging files
# =============================================================================

log_info "Cleaning up GCS staging files"
gcloud storage rm "${GCS_BUCKET}/chinook_schema.sql" "${GCS_BUCKET}/chinook_seed.sql" --quiet 2>&1 || true

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "======================================================================="
if [[ ${ERRORS} -eq 0 ]]; then
  log_success "Database initialization completed successfully (${TOTAL_STEPS}/${TOTAL_STEPS} steps)"
else
  log_error "Database initialization completed with ${ERRORS} error(s)"
  exit 1
fi
echo "======================================================================="
