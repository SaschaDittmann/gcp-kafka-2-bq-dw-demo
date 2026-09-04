#!/usr/bin/env bash
# =============================================================================
# Demo Deployment Script
# =============================================================================
# One-command setup for the CDC streaming pipeline demo:
#   1. Prompts for GCP project, region, and connector type
#   2. Creates/updates infra/terraform.auto.tfvars
#   3. Runs terraform apply to provision infrastructure
#   4. Runs deploy.sh to configure connectors and start queries
#
# Usage:
#   ./deploy-demo.sh
#
# Prerequisites:
#   - gcloud CLI authenticated with sufficient permissions
#   - terraform >= 1.5 installed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/infra"
TFVARS_FILE="${INFRA_DIR}/terraform.auto.tfvars"
TFVARS_EXAMPLE="${INFRA_DIR}/terraform.tfvars.example"

# -----------------------------------------------------------------------------
# Logging Helpers
# -----------------------------------------------------------------------------

log_info() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*"
}

log_success() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*"
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
    log_error "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
    missing=1
  fi

  if ! command -v terraform &>/dev/null; then
    log_error "terraform not found. Install: https://developer.hashicorp.com/terraform/install"
    missing=1
  fi

  if [[ ${missing} -ne 0 ]]; then
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Detect Defaults from gcloud
# -----------------------------------------------------------------------------

detect_defaults() {
  # Prefer Cloud Shell environment variables, fall back to gcloud config
  DEFAULT_PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo "")}"
  DEFAULT_REGION="${CLOUDSDK_COMPUTE_REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo "")}"

  if [[ -z "${DEFAULT_REGION}" ]]; then
    DEFAULT_REGION="us-central1"
  fi
}

# -----------------------------------------------------------------------------
# Interactive Configuration
# -----------------------------------------------------------------------------

prompt_configuration() {
  echo ""
  echo "======================================================================="
  echo "  CDC Streaming Pipeline — Demo Configuration"
  echo "======================================================================="
  echo ""

  # GCP Project ID
  if [[ -n "${DEFAULT_PROJECT}" ]]; then
    read -rp "GCP Project ID [${DEFAULT_PROJECT}]: " PROJECT_ID
    PROJECT_ID="${PROJECT_ID:-${DEFAULT_PROJECT}}"
  else
    read -rp "GCP Project ID: " PROJECT_ID
    if [[ -z "${PROJECT_ID}" ]]; then
      log_error "Project ID is required"
      exit 1
    fi
  fi

  # Region
  read -rp "GCP Region [${DEFAULT_REGION}]: " REGION
  REGION="${REGION:-${DEFAULT_REGION}}"

  # Source Connector Type
  echo ""
  echo "Kafka Source Connector Type:"
  echo "  1) managed   — Google Managed Kafka Connect (recommended)"
  echo "  2) cloudrun  — Self-hosted Debezium on Cloud Run"
  echo ""
  read -rp "Select connector type [1]: " CONNECTOR_CHOICE
  CONNECTOR_CHOICE="${CONNECTOR_CHOICE:-1}"

  case "${CONNECTOR_CHOICE}" in
    1|managed)
      SOURCE_CONNECTOR_TYPE="managed"
      ;;
    2|cloudrun)
      SOURCE_CONNECTOR_TYPE="cloudrun"
      ;;
    *)
      log_error "Invalid choice: ${CONNECTOR_CHOICE}"
      exit 1
      ;;
  esac

  # Confirm
  echo ""
  echo "-----------------------------------------------------------------------"
  echo "  Project:    ${PROJECT_ID}"
  echo "  Region:     ${REGION}"
  echo "  Connector:  ${SOURCE_CONNECTOR_TYPE}"
  echo "-----------------------------------------------------------------------"
  echo ""
  read -rp "Proceed with deployment? [Y/n]: " CONFIRM
  CONFIRM="${CONFIRM:-Y}"

  if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
  fi
}

# -----------------------------------------------------------------------------
# Create / Update terraform.auto.tfvars
# -----------------------------------------------------------------------------

configure_tfvars() {
  if [[ ! -f "${TFVARS_FILE}" ]]; then
    log_info "Creating ${TFVARS_FILE} from template..."
    cp "${TFVARS_EXAMPLE}" "${TFVARS_FILE}"
  else
    log_info "Updating existing ${TFVARS_FILE}..."
  fi

  # Update the three user-configured values using sed
  sed -i "s|^project_id.*|project_id  = \"${PROJECT_ID}\"|" "${TFVARS_FILE}"
  sed -i "s|^region.*|region      = \"${REGION}\"|" "${TFVARS_FILE}"
  sed -i "s|^source_connector_type.*|source_connector_type = \"${SOURCE_CONNECTOR_TYPE}\"|" "${TFVARS_FILE}"

  log_success "Configuration saved to ${TFVARS_FILE}"
}

# -----------------------------------------------------------------------------
# Provision Infrastructure
# -----------------------------------------------------------------------------

provision_infrastructure() {
  echo ""
  echo "======================================================================="
  log_info "Provisioning infrastructure with Terraform..."
  echo "======================================================================="

  terraform -chdir="${INFRA_DIR}" init -input=false
  terraform -chdir="${INFRA_DIR}" apply -auto-approve -input=false

  log_success "Infrastructure provisioned"
}

# -----------------------------------------------------------------------------
# Deploy Pipeline
# -----------------------------------------------------------------------------

deploy_pipeline() {
  echo ""
  echo "======================================================================="
  log_info "Deploying pipeline (connectors, queries, backfill)..."
  echo "======================================================================="

  "${SCRIPT_DIR}/scripts/deploy.sh"

  log_success "Pipeline deployed"
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "======================================================================="
  echo "  CDC Streaming Pipeline — Demo Deployment"
  echo "======================================================================="

  check_prerequisites
  detect_defaults
  prompt_configuration
  configure_tfvars
  provision_infrastructure
  deploy_pipeline

  echo ""
  echo "======================================================================="
  log_success "Demo deployment complete!"
  echo "======================================================================="
  echo ""
  log_info "To tear down: ./teardown-demo.sh"
}

main "$@"

