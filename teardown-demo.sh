#!/usr/bin/env bash
# =============================================================================
# Demo Teardown Script
# =============================================================================
# One-command teardown for the CDC streaming pipeline demo:
#   1. Runs teardown.sh to cancel CQs and drop replication slots
#   2. Runs terraform destroy to remove all infrastructure
#
# Usage:
#   ./teardown-demo.sh
#
# All steps are idempotent — safe to re-run if a previous teardown failed.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/infra"

# -----------------------------------------------------------------------------
# Logging Helpers
# -----------------------------------------------------------------------------

log_info() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*"
}

log_success() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*"
}

log_warn() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [WARN]  $*"
}

log_error() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

# -----------------------------------------------------------------------------
# Prerequisite Checks
# -----------------------------------------------------------------------------

check_prerequisites() {
  local missing=0

  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found."
    missing=1
  fi

  if ! command -v terraform &>/dev/null; then
    log_error "terraform not found."
    missing=1
  fi

  if [[ ${missing} -ne 0 ]]; then
    exit 1
  fi

  # Verify Terraform state exists
  if [[ ! -d "${INFRA_DIR}/.terraform" ]]; then
    log_error "Terraform has not been initialized. Nothing to tear down."
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Confirm
# -----------------------------------------------------------------------------

confirm_teardown() {
  echo ""
  echo "======================================================================="
  echo "  CDC Streaming Pipeline — Demo Teardown"
  echo "======================================================================="
  echo ""
  log_warn "This will DESTROY all demo resources in the GCP project."
  echo ""
  read -rp "Are you sure you want to proceed? [y/N]: " CONFIRM
  CONFIRM="${CONFIRM:-N}"

  if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    echo "Teardown cancelled."
    exit 0
  fi
}

# -----------------------------------------------------------------------------
# Step 1: Clean Up Runtime State
# -----------------------------------------------------------------------------

cleanup_runtime() {
  echo ""
  echo "======================================================================="
  log_info "Step 1/2: Cleaning up runtime state (CQs, replication slots)..."
  echo "======================================================================="

  if "${SCRIPT_DIR}/scripts/teardown.sh"; then
    log_success "Runtime cleanup completed"
  else
    log_warn "Runtime cleanup had warnings — continuing with infrastructure teardown"
  fi
}

# -----------------------------------------------------------------------------
# Step 2: Destroy Infrastructure
# -----------------------------------------------------------------------------

destroy_infrastructure() {
  echo ""
  echo "======================================================================="
  log_info "Step 2/2: Destroying infrastructure with Terraform..."
  echo "======================================================================="

  terraform -chdir="${INFRA_DIR}" destroy -auto-approve -input=false

  log_success "Infrastructure destroyed"
}

# =============================================================================
# Main
# =============================================================================

main() {
  check_prerequisites
  confirm_teardown
  cleanup_runtime
  destroy_infrastructure

  echo ""
  echo "======================================================================="
  log_success "Demo teardown complete! All resources have been removed."
  echo "======================================================================="
  echo ""
  log_info "To redeploy: ./deploy-demo.sh"
}

main "$@"
