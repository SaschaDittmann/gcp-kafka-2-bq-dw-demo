#!/usr/bin/env bash
# =============================================================================
# Database Initialization Script
# =============================================================================
# Initializes the Chinook database on Cloud SQL for PostgreSQL:
#   1. Creates the replication user with REPLICATION role
#   2. Loads the Chinook schema (DDL)
#   3. Seeds the Chinook sample data
#   4. Creates the logical replication slot for Debezium
#   5. Creates a publication for all tables
#
# Usage:
#   ./data/init_db.sh
#
# Required environment variables:
#   DB_HOST       - Cloud SQL private IP address
#   DB_PORT       - PostgreSQL port (default: 5432)
#   DB_NAME       - Database name (default: chinook)
#   DB_USER       - Admin user with CREATE/ALTER privileges
#   DB_PASSWORD   - Admin user password
#   REPL_USER     - Replication user name (default: debezium)
#   REPL_PASSWORD - Replication user password
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HOST="${DB_HOST:?ERROR: DB_HOST environment variable is required}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-chinook}"
DB_USER="${DB_USER:?ERROR: DB_USER environment variable is required}"
DB_PASSWORD="${DB_PASSWORD:?ERROR: DB_PASSWORD environment variable is required}"
REPL_USER="${REPL_USER:-debezium}"
REPL_PASSWORD="${REPL_PASSWORD:?ERROR: REPL_PASSWORD environment variable is required}"

STEP=0
TOTAL_STEPS=5
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
# Helper: Run psql command with connection parameters
# -----------------------------------------------------------------------------

run_psql() {
  PGPASSWORD="${DB_PASSWORD}" psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --no-password \
    --set=ON_ERROR_STOP=1 \
    "$@"
}

run_psql_repl() {
  PGPASSWORD="${REPL_PASSWORD}" psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${REPL_USER}" \
    --dbname="${DB_NAME}" \
    --no-password \
    --set=ON_ERROR_STOP=1 \
    "$@"
}

# =============================================================================
# Main
# =============================================================================

log_info "Starting Chinook database initialization"
log_info "Host: ${DB_HOST}:${DB_PORT} | Database: ${DB_NAME} | User: ${DB_USER}"
echo ""

# ---- Step 1: Create replication user ----------------------------------------

log_step "Creating replication user '${REPL_USER}'"

run_psql -c "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} WITH LOGIN PASSWORD '${REPL_PASSWORD}' REPLICATION;
    RAISE NOTICE 'Created replication user ${REPL_USER}';
  ELSE
    ALTER ROLE ${REPL_USER} WITH PASSWORD '${REPL_PASSWORD}' REPLICATION;
    RAISE NOTICE 'Replication user ${REPL_USER} already exists — updated password and ensured REPLICATION role';
  END IF;
END
\$\$;
" 2>&1 && log_success "Replication user '${REPL_USER}' is ready" \
       || { log_error "Failed to create replication user"; exit 1; }

# ---- Step 2: Load Chinook schema -------------------------------------------

log_step "Loading Chinook schema from chinook_schema.sql"

if [[ ! -f "${SCRIPT_DIR}/chinook_schema.sql" ]]; then
  log_error "Schema file not found: ${SCRIPT_DIR}/chinook_schema.sql"
  exit 1
fi

run_psql -f "${SCRIPT_DIR}/chinook_schema.sql" 2>&1 \
  && log_success "Chinook schema loaded successfully" \
  || { log_error "Failed to load Chinook schema"; exit 1; }

# ---- Step 3: Seed demo data ------------------------------------------------

log_step "Seeding Chinook sample data from chinook_seed.sql"

if [[ ! -f "${SCRIPT_DIR}/chinook_seed.sql" ]]; then
  log_error "Seed file not found: ${SCRIPT_DIR}/chinook_seed.sql"
  exit 1
fi

run_psql -f "${SCRIPT_DIR}/chinook_seed.sql" 2>&1 \
  && log_success "Chinook sample data seeded successfully" \
  || { log_error "Failed to seed Chinook data"; exit 1; }

# Grant SELECT on all tables to the replication user
run_psql -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${REPL_USER};" 2>&1 \
  && log_success "Granted SELECT on all tables to '${REPL_USER}'" \
  || { log_error "Failed to grant SELECT to replication user"; exit 1; }

# ---- Step 4: Create logical replication slot --------------------------------

log_step "Creating logical replication slot 'debezium_slot'"

SLOT_EXISTS=$(run_psql -tAc "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = 'debezium_slot';")

if [[ "${SLOT_EXISTS}" -eq 0 ]]; then
  run_psql -c "SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');" 2>&1 \
    && log_success "Logical replication slot 'debezium_slot' created" \
    || { log_error "Failed to create replication slot"; exit 1; }
else
  log_info "Replication slot 'debezium_slot' already exists — skipping"
fi

# ---- Step 5: Create publication for all tables ------------------------------

log_step "Creating publication 'debezium_publication' for all tables"

PUB_EXISTS=$(run_psql -tAc "SELECT COUNT(*) FROM pg_publication WHERE pubname = 'debezium_publication';")

if [[ "${PUB_EXISTS}" -eq 0 ]]; then
  run_psql -c "CREATE PUBLICATION debezium_publication FOR ALL TABLES;" 2>&1 \
    && log_success "Publication 'debezium_publication' created for all tables" \
    || { log_error "Failed to create publication"; exit 1; }
else
  log_info "Publication 'debezium_publication' already exists — skipping"
fi

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

# Print table row counts for verification
echo ""
log_info "Table row counts:"
run_psql -c "
SELECT schemaname, relname AS table_name, n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY relname;
"
