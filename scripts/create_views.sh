#!/usr/bin/env bash
# =============================================================================
# Create/Recreate BigQuery Views
# =============================================================================
# Creates all Silver and Gold views in BigQuery.
# Run this after `terraform apply` or whenever views need to be recreated.
#
# Prerequisites:
#   - Bronze tables must exist (created by BigQuery Sink Connector)
#   - Gold Iceberg tables must exist (created by Terraform)
#   - gcloud CLI authenticated with appropriate permissions
#
# Usage:
#   ./scripts/create_views.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRANSFORM_DIR="${PROJECT_ROOT}/transform"

# Get project ID from Terraform or environment
if [[ -n "${PROJECT_ID:-}" ]]; then
  echo "Using PROJECT_ID from environment: ${PROJECT_ID}"
elif [[ -d "${PROJECT_ROOT}/infra" ]]; then
  PROJECT_ID=$(cd "${PROJECT_ROOT}/infra" && terraform output -raw project_id 2>/dev/null || echo "")
  if [[ -z "${PROJECT_ID}" ]]; then
    echo "ERROR: Could not determine PROJECT_ID. Set it via environment variable or run terraform apply first."
    exit 1
  fi
  echo "Using PROJECT_ID from Terraform: ${PROJECT_ID}"
else
  echo "ERROR: PROJECT_ID not set and infra/ directory not found."
  exit 1
fi

SILVER_VIEWS=(
  "silver_artist.sql"
  "silver_album.sql"
  "silver_genre.sql"
  "silver_media_type.sql"
  "silver_playlist.sql"
  "silver_playlist_track.sql"
)

GOLD_VIEWS=(
  "gold_v_dim_customer.sql"
  "gold_v_dim_employee.sql"
  "gold_v_dim_track.sql"
  "gold_v_fct_invoice.sql"
  "gold_v_fct_invoice_line.sql"
)

errors=0

echo ""
echo "=== Creating Silver views ==="
for view_file in "${SILVER_VIEWS[@]}"; do
  view_path="${TRANSFORM_DIR}/${view_file}"
  if [[ ! -f "${view_path}" ]]; then
    echo "  ⚠ Not found: ${view_file}"
    errors=$((errors + 1))
    continue
  fi

  view_sql=$(sed "s/\${PROJECT_ID}/${PROJECT_ID}/g" "${view_path}")

  if bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "${view_sql}" >/dev/null 2>&1; then
    echo "  ✓ ${view_file}"
  else
    echo "  ✗ ${view_file} — Bronze table may not exist yet"
    errors=$((errors + 1))
  fi
done

echo ""
echo "=== Creating Gold views ==="
for view_file in "${GOLD_VIEWS[@]}"; do
  view_path="${TRANSFORM_DIR}/${view_file}"
  if [[ ! -f "${view_path}" ]]; then
    echo "  ⚠ Not found: ${view_file}"
    errors=$((errors + 1))
    continue
  fi

  view_sql=$(sed "s/\${PROJECT_ID}/${PROJECT_ID}/g" "${view_path}")

  if bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "${view_sql}" >/dev/null 2>&1; then
    echo "  ✓ ${view_file}"
  else
    echo "  ✗ ${view_file} — Gold table may not exist yet"
    errors=$((errors + 1))
  fi
done

echo ""
if [[ ${errors} -gt 0 ]]; then
  echo "⚠ ${errors} view(s) failed. Ensure the pipeline has been deployed first."
  echo "  Bronze tables are created by the BigQuery Sink Connector."
  echo "  Gold tables are created by terraform apply."
  exit 1
else
  echo "✓ All views created successfully."
fi
