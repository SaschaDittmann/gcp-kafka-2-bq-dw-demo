#!/usr/bin/env bash
# =============================================================================
# Register Kafka Connect Connectors
# =============================================================================
# Registers connectors to the split source/sink Kafka Connect services:
#   - Debezium source connector → source service
#
# NOTE: Only used for Cloud Run mode (source_connector_type=cloudrun).
# BQ sink and GCS sink are always managed via Terraform (infra/kafka_connect.tf).
#
# Usage:
#   ./connect/register-connectors.sh
#
# Required environment variables:
#   SOURCE_CONNECT_URL  - Source service REST URL (default: http://localhost:8083)
#   DB_HOST             - Cloud SQL private IP
#   DB_REPL_USER        - Debezium replication user (default: debezium)
#   DB_REPL_PASSWORD    - Debezium replication user password
#   GCP_PROJECT_ID      - GCP project ID
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CONNECT_URL="${SOURCE_CONNECT_URL:-http://localhost:8083}"
DB_HOST="${DB_HOST:?ERROR: DB_HOST environment variable is required}"
DB_REPL_USER="${DB_REPL_USER:-debezium}"
DB_REPL_PASSWORD="${DB_REPL_PASSWORD:?ERROR: DB_REPL_PASSWORD environment variable is required}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:?ERROR: GCP_PROJECT_ID environment variable is required}"

MAX_RETRIES=30
RETRY_INTERVAL=10

# -----------------------------------------------------------------------------
# Logging Helpers
# -----------------------------------------------------------------------------

log_info() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*"
}

log_error() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_success() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*"
}

# -----------------------------------------------------------------------------
# Helper: Wait for a Kafka Connect REST API to be healthy
# -----------------------------------------------------------------------------

wait_for_connect() {
  local url="$1"
  local label="$2"
  log_info "Waiting for ${label} at ${url}..."
  local attempt=0
  while [[ ${attempt} -lt ${MAX_RETRIES} ]]; do
    attempt=$((attempt + 1))
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "${url}/") || true
    if [[ "${status_code}" == "200" ]]; then
      log_success "${label} is ready (HTTP ${status_code})"
      return 0
    fi
    log_info "Attempt ${attempt}/${MAX_RETRIES}: HTTP ${status_code} — retrying in ${RETRY_INTERVAL}s"
    sleep "${RETRY_INTERVAL}"
  done
  log_error "${label} did not become ready after ${MAX_RETRIES} attempts"
  return 1
}

# -----------------------------------------------------------------------------
# Helper: Register or update a connector
# -----------------------------------------------------------------------------

register_connector() {
  local connect_url="$1"
  local config_file="$2"
  local connector_name
  connector_name=$(python3 -c "import json,sys; print(json.load(open('${config_file}'))['name'])")

  log_info "Registering connector '${connector_name}' from ${config_file}"

  # Substitute environment variables in the config
  local config_json
  config_json=$(envsubst < "${config_file}")

  # Check if connector already exists
  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "${connect_url}/connectors/${connector_name}") || true

  local response
  if [[ "${status_code}" == "200" ]]; then
    # Update existing connector config
    log_info "Connector '${connector_name}' exists — updating configuration"
    local config_only
    config_only=$(echo "${config_json}" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['config']))")
    response=$(curl -s -w "\n%{http_code}" -X PUT \
      -H "Content-Type: application/json" \
      -d "${config_only}" \
      "${connect_url}/connectors/${connector_name}/config")
  else
    # Create new connector
    log_info "Creating new connector '${connector_name}'"
    response=$(curl -s -w "\n%{http_code}" -X POST \
      -H "Content-Type: application/json" \
      -d "${config_json}" \
      "${connect_url}/connectors")
  fi

  local http_code
  http_code=$(echo "${response}" | tail -1)
  local body
  body=$(echo "${response}" | sed '$d')

  if [[ "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
    log_success "Connector '${connector_name}' registered (HTTP ${http_code})"
  else
    log_error "Failed to register '${connector_name}' (HTTP ${http_code}): ${body}"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Helper: Check connector status
# -----------------------------------------------------------------------------

check_connector_status() {
  local connect_url="$1"
  local connector_name="$2"
  local response
  response=$(curl -s "${connect_url}/connectors/${connector_name}/status") || true

  local state
  state=$(echo "${response}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('connector',{}).get('state','UNKNOWN'))" 2>/dev/null) || state="UNKNOWN"

  log_info "Connector '${connector_name}' state: ${state}"
  echo "${response}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d.get('tasks', []):
    print(f\"  Task {t['id']}: {t['state']}\")
" 2>/dev/null || true
}

# =============================================================================
# Main
# =============================================================================

log_info "Starting connector registration (split source/sink architecture)"
echo ""

# Step 1: Wait for both Connect services
log_info "--- Waiting for Connect Services ---"
wait_for_connect "${SOURCE_CONNECT_URL}" "Source service" || exit 1
echo ""

# Step 2: Register Debezium Source → Source service
log_info "--- Registering Debezium PostgreSQL Source Connector ---"
register_connector "${SOURCE_CONNECT_URL}" "${SCRIPT_DIR}/debezium-source.json" || exit 1
echo ""

# Step 3: Verify connector status
log_info "--- Connector Status ---"
sleep 5  # Brief pause for connectors to initialize
check_connector_status "${SOURCE_CONNECT_URL}" "debezium-source"

echo ""
log_success "All connectors registered successfully"
