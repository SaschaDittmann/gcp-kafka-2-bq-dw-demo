#!/usr/bin/env bash
# =============================================================================
# Terraform Destroy Cleanup
# =============================================================================
# Called by the chinook database destroy provisioner to clean up CDC runtime
# state before Terraform deletes the database and user.
#
# Usage (called automatically by Terraform):
#   ./scripts/destroy-cleanup.sh <instance> <database> <project>
# =============================================================================

set -euo pipefail

INSTANCE="${1:?Usage: destroy-cleanup.sh <instance> <database> <project>}"
DATABASE="${2:?}"
PROJECT="${3:?}"

echo "=== Cleaning up CDC runtime state before database deletion ==="
echo "  Instance: ${INSTANCE}"
echo "  Database: ${DATABASE}"
echo "  Project:  ${PROJECT}"

# GCS staging bucket — create if it was already deleted during destroy
GCS_BUCKET="gs://${PROJECT}-sql-import"
echo ""
echo "--- Ensuring GCS staging bucket exists ---"
gcloud storage buckets create "${GCS_BUCKET}" \
  --project="${PROJECT}" --location=eu --quiet 2>/dev/null || true

# Grant Cloud SQL SA access (may have been revoked during destroy)
CLOUDSQL_SA=$(gcloud sql instances describe "${INSTANCE}" \
  --project="${PROJECT}" \
  --format="value(serviceAccountEmailAddress)" 2>/dev/null) || true

if [[ -n "${CLOUDSQL_SA}" ]]; then
  echo "  Granting ${CLOUDSQL_SA} read access to ${GCS_BUCKET}"
  gcloud storage buckets add-iam-policy-binding "${GCS_BUCKET}" \
    --member="serviceAccount:${CLOUDSQL_SA}" \
    --role="roles/storage.objectViewer" --quiet 2>/dev/null || true
fi

# ---- Step 1: Drop replication slot and publication ----
echo ""
echo "--- Step 1: Dropping replication slot and publication ---"

SQL_FILE=$(mktemp /tmp/teardown_slot_XXXXXX.sql)
cat > "${SQL_FILE}" << 'ENDSQL'
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'debezium_slot') THEN
    PERFORM pg_drop_replication_slot('debezium_slot');
    RAISE NOTICE 'Dropped replication slot debezium_slot';
  ELSE
    RAISE NOTICE 'Replication slot debezium_slot does not exist — skipping';
  END IF;
END $$;

DROP PUBLICATION IF EXISTS debezium_publication;
ENDSQL

gcloud storage cp "${SQL_FILE}" "${GCS_BUCKET}/teardown_slot.sql" --quiet 2>&1 || true
rm -f "${SQL_FILE}"

if gcloud sql import sql "${INSTANCE}" "${GCS_BUCKET}/teardown_slot.sql" \
    --database="${DATABASE}" --user=postgres --project="${PROJECT}" --quiet 2>&1; then
  echo "  ✅ Replication slot and publication dropped"
else
  echo "  ⚠️  Failed to drop replication slot (may already be gone)"
fi
gcloud storage rm "${GCS_BUCKET}/teardown_slot.sql" --quiet 2>/dev/null || true

# ---- Step 2: Reassign object ownership ----
echo ""
echo "--- Step 2: Reassigning object ownership to admin ---"

SQL_FILE=$(mktemp /tmp/teardown_owner_XXXXXX.sql)
cat > "${SQL_FILE}" << 'ENDSQL'
DO $$
DECLARE
  kafka_user TEXT;
BEGIN
  SELECT usename INTO kafka_user
    FROM pg_user
    WHERE usename LIKE 'service-%@gcp-sa-managedkafka.iam';
  IF kafka_user IS NOT NULL THEN
    EXECUTE format('REASSIGN OWNED BY %I TO admin', kafka_user);
    EXECUTE format('DROP OWNED BY %I', kafka_user);
    RAISE NOTICE 'Reassigned objects from % to admin', kafka_user;
  ELSE
    RAISE NOTICE 'No Managed Kafka IAM user found — skipping';
  END IF;
END $$;
ENDSQL

gcloud storage cp "${SQL_FILE}" "${GCS_BUCKET}/teardown_owner.sql" --quiet 2>&1 || true
rm -f "${SQL_FILE}"

if gcloud sql import sql "${INSTANCE}" "${GCS_BUCKET}/teardown_owner.sql" \
    --database="${DATABASE}" --user=postgres --project="${PROJECT}" --quiet 2>&1; then
  echo "  ✅ Object ownership reassigned to admin"
else
  echo "  ⚠️  Failed to reassign ownership (may already be clean)"
fi
gcloud storage rm "${GCS_BUCKET}/teardown_owner.sql" --quiet 2>/dev/null || true

# ---- Cleanup staging bucket ----
echo ""
echo "--- Cleaning up staging bucket ---"
gcloud storage rm --recursive "${GCS_BUCKET}/" --quiet 2>/dev/null || true
gcloud storage buckets delete "${GCS_BUCKET}" --quiet 2>/dev/null || true

echo ""
echo "=== CDC cleanup completed ==="

