#!/usr/bin/env bash
# =============================================================================
# Full Pipeline Deployment Script
# =============================================================================
# Orchestrates all post-Terraform deployment steps:
#   1. Initialize the database (schema, seed, replication)
#   2. Build and push the Kafka Connect Docker image (Cloud Run mode only)
#   3. Update Cloud Run services with the new image (Cloud Run mode only)
#   4. Wait for Cloud Run services to become healthy (Cloud Run mode only)
#   5. Register Kafka Connect connectors (Cloud Run mode only)
#   6. Create Silver layer views (after Bronze tables are auto-created)
#   7. Start BigQuery Continuous Queries
#
# Prerequisites:
#   - `terraform apply` has been run successfully in infra/
#   - gcloud CLI is authenticated and configured
#   - bq CLI is available (comes with gcloud SDK)
#
# Usage:
#   ./scripts/deploy.sh
#
# Optional environment variables:
#   SKIP_DB_INIT      - Set to "true" to skip database initialization
#   SKIP_IMAGE_BUILD  - Set to "true" to skip Docker image build
#   SKIP_CQ_START     - Set to "true" to skip Continuous Query startup
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra"

STEP=0
TOTAL_STEPS=7
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
  echo "======================================================================="
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [STEP ${STEP}/${TOTAL_STEPS}] $*"
  echo "======================================================================="
}

log_error() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
  ERRORS=$((ERRORS + 1))
}

log_success() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*"
}

log_warn() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [WARN]  $*"
}

# -----------------------------------------------------------------------------
# Prerequisite Checks
# -----------------------------------------------------------------------------

check_prerequisites() {
  log_info "Checking prerequisites..."

  local missing=0
  for cmd in gcloud bq terraform; do
    if ! command -v "${cmd}" &> /dev/null; then
      log_error "Required command '${cmd}' not found in PATH"
      missing=$((missing + 1))
    fi
  done

  if [[ ! -d "${INFRA_DIR}" ]]; then
    log_error "Terraform directory not found: ${INFRA_DIR}"
    missing=$((missing + 1))
  fi

  if ! terraform -chdir="${INFRA_DIR}" output -json &> /dev/null; then
    log_error "Cannot read Terraform outputs — has 'terraform apply' been run?"
    missing=$((missing + 1))
  fi

  if [[ ${missing} -gt 0 ]]; then
    log_error "${missing} prerequisite(s) missing — aborting"
    exit 1
  fi

  log_success "All prerequisites met"
}

# -----------------------------------------------------------------------------
# Extract Terraform Outputs
# -----------------------------------------------------------------------------

load_terraform_outputs() {
  log_info "Loading Terraform outputs..."

  local tf_json
  tf_json=$(terraform -chdir="${INFRA_DIR}" output -json)

  PROJECT_ID=$(echo "${tf_json}" | python3 -c "import json,sys; o=json.load(sys.stdin); print(o.get('cloudsql_connection_name',{}).get('value','').split(':')[0])")
  REGION=$(echo "${tf_json}" | python3 -c "import json,sys; o=json.load(sys.stdin); print(o.get('cloudsql_connection_name',{}).get('value','').split(':')[1])")
  INSTANCE_NAME=$(echo "${tf_json}" | python3 -c "import json,sys; o=json.load(sys.stdin); print(o['cloudsql_instance_name']['value'])")
  DB_HOST=$(echo "${tf_json}" | python3 -c "import json,sys; o=json.load(sys.stdin); print(o['cloudsql_private_ip']['value'])")
  DB_ADMIN_PASSWORD=$(terraform -chdir="${INFRA_DIR}" output -raw cloudsql_admin_password)
  REPL_PASSWORD=$(terraform -chdir="${INFRA_DIR}" output -raw cloudsql_repl_password)
  AR_URL=$(echo "${tf_json}" | python3 -c "import json,sys; o=json.load(sys.stdin); print(o['artifact_registry_url']['value'])")
  SOURCE_SERVICE=$(echo "${tf_json}" | python3 -c "import json,sys; o=json.load(sys.stdin); print(o.get('cloudrun_source_service_name',{}).get('value') or '')")
  CONNECT_CLUSTER=$(echo "${tf_json}" | python3 -c "import json,sys; o=json.load(sys.stdin); print(o.get('connect_cluster_id',{}).get('value') or '')")

  if [[ -n "${SOURCE_SERVICE}" && "${SOURCE_SERVICE}" != "None" ]]; then
    export SOURCE_CONNECTOR_TYPE="cloudrun"
  else
    export SOURCE_CONNECTOR_TYPE="managed"
  fi

  IMAGE_TAG="${AR_URL}/kafka-connect:latest"

  log_success "Loaded outputs: project=${PROJECT_ID}, region=${REGION}, instance=${INSTANCE_NAME}"
}

# =============================================================================
# Step 1: Database Initialization
# =============================================================================

step_init_database() {
  log_step "Initializing Chinook database"

  if [[ "${SKIP_DB_INIT:-false}" == "true" ]]; then
    log_warn "Skipping database init (SKIP_DB_INIT=true)"
    return 0
  fi

  export INSTANCE_NAME PROJECT_ID REPL_PASSWORD
  export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)
  export DB_NAME="chinook"
  export DB_USER="admin"
  export REPL_USER="debezium"

  if bash "${PROJECT_ROOT}/data/init_db.sh"; then
    log_success "Database initialization completed"
  else
    log_error "Database initialization failed"
    return 1
  fi
}

# =============================================================================
# Step 2: Build and Push Docker Image
# =============================================================================

step_build_image() {
  log_step "Building and pushing Kafka Connect Docker image"

  if [[ "${SOURCE_CONNECTOR_TYPE}" == "managed" ]]; then
    log_info "Connectors are managed via Terraform — skipping image build"
    return 0
  fi

  if [[ "${SKIP_IMAGE_BUILD:-false}" == "true" ]]; then
    log_warn "Skipping image build (SKIP_IMAGE_BUILD=true)"
    return 0
  fi

  log_info "Building image: ${IMAGE_TAG}"
  log_info "Using Cloud Build (no local Docker required)"

  if gcloud builds submit "${PROJECT_ROOT}/connect/" \
       --tag="${IMAGE_TAG}" \
       --project="${PROJECT_ID}" \
       --quiet; then
    log_success "Docker image built and pushed: ${IMAGE_TAG}"
  else
    log_error "Docker image build failed"
    return 1
  fi
}

# =============================================================================
# Step 3: Update Cloud Run Services
# =============================================================================

step_update_cloudrun() {
  log_step "Updating Cloud Run services with new image"

  if [[ "${SOURCE_CONNECTOR_TYPE}" == "managed" ]]; then
    log_info "Connectors are managed via Terraform — skipping Cloud Run update"
    return 0
  fi

  log_info "Updating source service: ${SOURCE_SERVICE}"
  if gcloud run services update "${SOURCE_SERVICE}" \
       --image="${IMAGE_TAG}" \
       --region="${REGION}" \
       --project="${PROJECT_ID}" \
       --quiet; then
    log_success "Source service updated"
  else
    log_error "Failed to update source service"
    return 1
  fi
}

# =============================================================================
# Step 4: Wait for Cloud Run Health
# =============================================================================

step_wait_for_cloudrun() {
  log_step "Waiting for Cloud Run services to become healthy"

  if [[ "${SOURCE_CONNECTOR_TYPE}" == "managed" ]]; then
    log_info "Connectors are managed via Terraform — skipping Cloud Run wait"
    return 0
  fi

  local max_attempts=30
  local interval=10

  for service in "${SOURCE_SERVICE}"; do
    log_info "Checking service: ${service}"
    local attempt=0
    while [[ ${attempt} -lt ${max_attempts} ]]; do
      attempt=$((attempt + 1))
      local conditions
      conditions=$(gcloud run services describe "${service}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" \
        --format="value(status.conditions[0].status)" 2>/dev/null) || true

      if [[ "${conditions}" == "True" ]]; then
        log_success "Service '${service}' is healthy"
        break
      fi
      log_info "Attempt ${attempt}/${max_attempts}: ${service} not ready — retrying in ${interval}s"
      sleep "${interval}"
    done

    if [[ ${attempt} -ge ${max_attempts} ]]; then
      log_error "Service '${service}' did not become healthy after ${max_attempts} attempts"
      return 1
    fi
  done
}

# =============================================================================
# Step 5: Register Connectors
# =============================================================================

step_register_connectors() {
  log_step "Registering Kafka Connect connectors"

  if [[ "${SOURCE_CONNECTOR_TYPE}" == "managed" ]]; then
    log_info "Connectors are managed via Terraform — skipping REST registration"
    return 0
  fi

  # Cloud Run internal services are not directly reachable from outside the VPC.
  # Use gcloud run services proxy to create a local tunnel.
  log_info "Starting proxy tunnels to Cloud Run services..."

  # Start source proxy in background
  gcloud run services proxy "${SOURCE_SERVICE}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --port=8083 &
  local source_proxy_pid=$!

  # Give proxies time to start
  sleep 5

  # Set environment variables for register-connectors.sh
  export SOURCE_CONNECT_URL="http://localhost:8083"
  export DB_HOST
  export DB_REPL_USER="debezium"
  export DB_REPL_PASSWORD="${REPL_PASSWORD}"
  export GCP_PROJECT_ID="${PROJECT_ID}"

  local register_rc=0
  bash "${PROJECT_ROOT}/connect/register-connectors.sh" || register_rc=$?

  # Cleanup proxy processes
  kill "${source_proxy_pid}" 2>/dev/null || true

  if [[ ${register_rc} -eq 0 ]]; then
    log_success "Connectors registered successfully"
  else
    log_error "Connector registration failed"
    return 1
  fi
}

# =============================================================================
# Step 6: Create Silver Views (after Bronze tables exist)
# =============================================================================

step_create_silver_views() {
  log_step "Creating Silver layer views"

  local transform_dir="${PROJECT_ROOT}/transform"

  # Wait for Bronze tables to be auto-created by the BQ sink connector.
  # On a fresh deploy, the CDC source snapshot + BQ sink can take several minutes.
  log_info "Waiting for Bronze tables to be auto-created by the BQ sink connector..."
  local max_wait=300  # seconds (5 min for initial snapshot)
  local elapsed=0
  local interval=10

  while [[ ${elapsed} -lt ${max_wait} ]]; do
    local table_count
    table_count=$(bq ls --project_id="${PROJECT_ID}" "bronze" 2>/dev/null | grep -c "_raw" || echo "0")
    if [[ ${table_count} -ge 11 ]]; then
      log_success "All 11 Bronze tables detected"
      break
    fi
    log_info "Found ${table_count}/11 Bronze tables — waiting ${interval}s..."
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  if [[ ${elapsed} -ge ${max_wait} ]]; then
    log_warn "Timed out waiting for Bronze tables — views will be created anyway"
  fi

  # Deploy view SQL scripts
  local view_files=(
    "silver_artist.sql"
    "silver_album.sql"
    "silver_genre.sql"
    "silver_media_type.sql"
    "silver_playlist.sql"
    "silver_playlist_track.sql"
  )

  local view_errors=0
  for view_file in "${view_files[@]}"; do
    local view_path="${transform_dir}/${view_file}"
    if [[ ! -f "${view_path}" ]]; then
      log_warn "View file not found: ${view_path}"
      view_errors=$((view_errors + 1))
      continue
    fi

    log_info "Creating view: ${view_file}"
    local view_sql
    view_sql=$(sed "s/\${PROJECT_ID}/${PROJECT_ID}/g" "${view_path}")

    if bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "${view_sql}"; then
      log_success "Created view: ${view_file}"
    else
      log_warn "Failed to create view: ${view_file}"
      view_errors=$((view_errors + 1))
    fi
  done

  if [[ ${view_errors} -gt 0 ]]; then
    log_warn "${view_errors} view(s) failed — they can be created manually after data flows"
    return 0  # Non-fatal
  fi

  log_success "All Silver views created"

  # --- Gold current-state views ---
  # These can only be created after the gold Iceberg tables exist (from terraform apply).
  log_info "Creating Gold current-state views..."
  local gold_view_files=(
    "gold_v_dim_customer.sql"
    "gold_v_dim_employee.sql"
    "gold_v_dim_track.sql"
    "gold_v_fct_invoice.sql"
    "gold_v_fct_invoice_line.sql"
  )

  local gold_errors=0
  for view_file in "${gold_view_files[@]}"; do
    local view_path="${transform_dir}/${view_file}"
    if [[ ! -f "${view_path}" ]]; then
      log_warn "View file not found: ${view_path}"
      gold_errors=$((gold_errors + 1))
      continue
    fi

    log_info "Creating view: ${view_file}"
    local view_sql
    view_sql=$(sed "s/\${PROJECT_ID}/${PROJECT_ID}/g" "${view_path}")

    if bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "${view_sql}"; then
      log_success "Created view: ${view_file}"
    else
      log_warn "Failed to create view: ${view_file}"
      gold_errors=$((gold_errors + 1))
    fi
  done

  if [[ ${gold_errors} -gt 0 ]]; then
    log_warn "${gold_errors} gold view(s) failed — ensure terraform apply has been run first"
  else
    log_success "All Gold views created"
  fi
}

# =============================================================================
# Step 7: Start BigQuery Continuous Queries
# =============================================================================

step_start_continuous_queries() {
  log_step "Starting BigQuery Continuous Queries"

  if [[ "${SKIP_CQ_START:-false}" == "true" ]]; then
    log_warn "Skipping CQ start (SKIP_CQ_START=true)"
    return 0
  fi

  local transform_dir="${PROJECT_ROOT}/transform"
  local cq_errors=0

  # Start Silver CQs first (Bronze → Silver), then Gold (Silver → Gold)
  local silver_cqs=(
    "silver_customer.sql"
    "silver_employee.sql"
    "silver_track.sql"
    "silver_invoice.sql"
    "silver_invoice_line.sql"
  )

  log_info "Starting Silver layer CQs (Bronze → Silver)..."
  for cq_file in "${silver_cqs[@]}"; do
    local cq_path="${transform_dir}/${cq_file}"
    if [[ ! -f "${cq_path}" ]]; then
      log_error "CQ file not found: ${cq_path}"
      cq_errors=$((cq_errors + 1))
      continue
    fi

    log_info "Starting CQ: ${cq_file}"
    local cq_sql
    cq_sql=$(sed "s/\${PROJECT_ID}/${PROJECT_ID}/g" "${cq_path}")

    if bq query --use_legacy_sql=false --continuous=true --project_id="${PROJECT_ID}" \
         "${cq_sql}" &>/dev/null &
    then
      log_success "Started CQ: ${cq_file} (background)"
    else
      log_warn "Failed to start CQ: ${cq_file} (may require Enterprise edition)"
      cq_errors=$((cq_errors + 1))
    fi
  done

  # Gold layer uses scheduled queries (every 5 min), managed by Terraform.
  log_info "Gold layer transforms run as scheduled queries (managed by Terraform)"

  if [[ ${cq_errors} -gt 0 ]]; then
    log_warn "${cq_errors} CQ(s) failed to start — CQs require BigQuery Enterprise edition with slot reservations"
    log_warn "You can start them manually later: bq query --use_legacy_sql=false --continuous=true < transform/<file>.sql"
    return 0  # Non-fatal — don't block deployment
  fi

  log_success "All Silver Continuous Queries started"
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "======================================================================="
  log_info "CDC Pipeline Deployment"
  echo "======================================================================="

  check_prerequisites
  load_terraform_outputs

  step_init_database      || true
  step_build_image        || { log_error "Image build failed — cannot continue"; exit 1; }
  step_update_cloudrun    || { log_error "Cloud Run update failed — cannot continue"; exit 1; }
  step_wait_for_cloudrun  || { log_error "Cloud Run health check failed — cannot continue"; exit 1; }
  step_register_connectors || true
  step_create_silver_views || true
  step_start_continuous_queries || true

  # Summary
  echo ""
  echo "======================================================================="
  if [[ ${ERRORS} -eq 0 ]]; then
    log_success "Deployment completed successfully (${TOTAL_STEPS}/${TOTAL_STEPS} steps)"
  else
    log_warn "Deployment completed with ${ERRORS} warning(s) — check output above"
  fi
  echo "======================================================================="
  echo ""
  log_info "Verify the pipeline:"
  if [[ "${SOURCE_CONNECTOR_TYPE}" == "cloudrun" ]]; then
    log_info "  1. Check connectors: gcloud run services proxy ${SOURCE_SERVICE} --port=8083"
    log_info "     Then: curl http://localhost:8083/connectors"
  else
    log_info "  1. Check connectors: curl -s -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" \"https://managedkafka.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/connectClusters/${CONNECT_CLUSTER}/connectors\""
  fi
  log_info "  2. Query BigQuery:   bq query 'SELECT COUNT(*) FROM bronze.customer_raw'"
  log_info "  3. Check CQ status:  bq ls --jobs --all --project_id=${PROJECT_ID}"
}

main "$@"
