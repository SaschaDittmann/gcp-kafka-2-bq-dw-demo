#!/usr/bin/env bash
# =============================================================================
# Pipeline Teardown Script
# =============================================================================
# Cleans up pipeline resources before running `terraform destroy`:
#   1. Cancels all running BigQuery Continuous Queries
#   2. Drops the PostgreSQL logical replication slot
#   3. Drops the Debezium publication
#
# Run this BEFORE `terraform destroy` to avoid orphaned resources.
#
# Usage:
#   ./scripts/teardown.sh
#
# Resources that may already be deleted are handled gracefully.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra"

STEP=0
TOTAL_STEPS=3
ERRORS=0
CLEANED=0

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
# Load Terraform Outputs
# -----------------------------------------------------------------------------

load_terraform_outputs() {
  log_info "Loading Terraform outputs..."

  local tf_json
  if ! tf_json=$(terraform -chdir="${INFRA_DIR}" output -json 2>/dev/null); then
    log_warn "Cannot read Terraform outputs — some cleanup may be skipped"
    PROJECT_ID=""
    INSTANCE_NAME=""
    return 1
  fi

  PROJECT_ID=$(echo "${tf_json}" | python3 -c "
import json, sys
o = json.load(sys.stdin)
cn = o.get('cloudsql_connection_name', {}).get('value', '')
print(cn.split(':')[0] if cn else '')
" 2>/dev/null || echo "")

  INSTANCE_NAME=$(echo "${tf_json}" | python3 -c "
import json, sys
o = json.load(sys.stdin)
print(o.get('cloudsql_instance_name', {}).get('value', ''))
" 2>/dev/null || echo "")

  log_success "Loaded outputs: project=${PROJECT_ID}, instance=${INSTANCE_NAME}"
}

# -----------------------------------------------------------------------------
# Helper: Run SQL via gcloud sql import (same pattern as init_db.sh)
# -----------------------------------------------------------------------------

run_sql() {
  local sql="$1"
  local label="${2:-teardown}"
  local user="${3:-admin}"
  local gcs_bucket="gs://${PROJECT_ID}-sql-import"
  local tmp_file
  tmp_file=$(mktemp /tmp/teardown_XXXXXX.sql)
  echo "${sql}" > "${tmp_file}"

  gcloud storage cp "${tmp_file}" "${gcs_bucket}/${label}.sql" --quiet 2>&1
  rm -f "${tmp_file}"

  local import_rc=0
  gcloud sql import sql "${INSTANCE_NAME}" "${gcs_bucket}/${label}.sql" \
    --database="chinook" \
    --user="${user}" \
    --project="${PROJECT_ID}" \
    --quiet 2>&1 || import_rc=$?

  gcloud storage rm "${gcs_bucket}/${label}.sql" --quiet 2>&1 || true

  return "${import_rc}"
}

# =============================================================================
# Step 1: Cancel BigQuery Continuous Queries
# =============================================================================

step_cancel_continuous_queries() {
  log_step "Cancelling BigQuery Continuous Queries"

  # List all running jobs and filter for CONTINUOUS type
  log_info "Listing running BigQuery jobs..."

  local job_ids
  job_ids=$(bq ls --jobs --all --project_id="${PROJECT_ID}" \
    --format=json --max_results=100 2>/dev/null | \
    python3 -c "
import json, sys
try:
    jobs = json.load(sys.stdin)
    for job in jobs:
        status = job.get('status', {}).get('state', '')
        config = job.get('configuration', {}).get('query', {})
        is_continuous = config.get('continuous', False)
        if status == 'RUNNING' and is_continuous:
            ref = job.get('jobReference', {})
            print(f\"{ref.get('projectId', '')}:{ref.get('location', '')}:{ref.get('jobId', '')}\")
except Exception:
    pass
" 2>/dev/null) || true

  if [[ -z "${job_ids}" ]]; then
    log_info "No running Continuous Queries found"
    return 0
  fi

  local cancelled=0
  while IFS= read -r job_id; do
    if [[ -n "${job_id}" ]]; then
      log_info "Cancelling CQ job: ${job_id}"
      if bq cancel --project_id="${PROJECT_ID}" "${job_id}" 2>/dev/null; then
        log_success "Cancelled: ${job_id}"
        cancelled=$((cancelled + 1))
        CLEANED=$((CLEANED + 1))
      else
        log_warn "Could not cancel: ${job_id} (may already be stopped)"
      fi
    fi
  done <<< "${job_ids}"

  log_success "Cancelled ${cancelled} Continuous Query job(s)"
}

# =============================================================================
# Step 2: Drop Replication Slot
# =============================================================================

step_drop_replication_slot() {
  log_step "Dropping PostgreSQL logical replication slot"

  if [[ -z "${INSTANCE_NAME:-}" ]]; then
    log_warn "Instance name not available — skipping replication slot cleanup"
    return 0
  fi

  log_info "Dropping replication slot 'debezium_slot'..."

  if run_sql "
DO \$\$
BEGIN
  IF EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'debezium_slot') THEN
    PERFORM pg_drop_replication_slot('debezium_slot');
    RAISE NOTICE 'Dropped replication slot debezium_slot';
  ELSE
    RAISE NOTICE 'Replication slot debezium_slot does not exist — skipping';
  END IF;
END
\$\$;
" "drop_slot" "debezium"; then
    log_success "Replication slot cleanup completed"
    CLEANED=$((CLEANED + 1))
  else
    log_warn "Could not drop replication slot (may not exist or instance may be stopped)"
  fi
}

# =============================================================================
# Step 3: Drop Publication
# =============================================================================

step_drop_publication() {
  log_step "Dropping PostgreSQL publication"

  if [[ -z "${INSTANCE_NAME:-}" ]]; then
    log_warn "Instance name not available — skipping publication cleanup"
    return 0
  fi

  log_info "Dropping publication 'debezium_publication'..."

  if run_sql "
DO \$\$
BEGIN
  IF EXISTS (SELECT FROM pg_publication WHERE pubname = 'debezium_publication') THEN
    DROP PUBLICATION debezium_publication;
    RAISE NOTICE 'Dropped publication debezium_publication';
  ELSE
    RAISE NOTICE 'Publication debezium_publication does not exist — skipping';
  END IF;
END
\$\$;
" "drop_publication"; then
    log_success "Publication cleanup completed"
    CLEANED=$((CLEANED + 1))
  else
    log_warn "Could not drop publication (may not exist or instance may be stopped)"
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "======================================================================="
  log_info "CDC Pipeline Teardown"
  echo "======================================================================="

  load_terraform_outputs || true

  step_cancel_continuous_queries || true
  step_drop_replication_slot     || true
  step_drop_publication          || true

  # Cleanup the GCS staging bucket used by init_db.sh
  if [[ -n "${PROJECT_ID:-}" ]]; then
    log_info "Cleaning up GCS staging bucket..."
    gcloud storage rm --recursive "gs://${PROJECT_ID}-sql-import/" --quiet 2>/dev/null || true
  fi

  # Summary
  echo ""
  echo "======================================================================="
  if [[ ${ERRORS} -eq 0 ]]; then
    log_success "Teardown completed — cleaned ${CLEANED} resource(s)"
  else
    log_warn "Teardown completed with ${ERRORS} warning(s) — cleaned ${CLEANED} resource(s)"
  fi
  echo "======================================================================="
  echo ""
  log_info "You can now safely run: cd infra && terraform destroy"
}

main "$@"
