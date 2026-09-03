# =============================================================================
# Cloud SQL for PostgreSQL: Instance, Database, and Users
# =============================================================================
# Provisions a Cloud SQL PostgreSQL instance with:
# - Private IP via Private Service Access (no public IP)
# - Logical decoding enabled for Debezium CDC
# - Random suffix to avoid 7-day name reuse lockout after deletion
# - Deletion protection disabled for demo teardown
# =============================================================================

# -----------------------------------------------------------------------------
# Random suffix to avoid Cloud SQL 7-day name reuse collision on recreate
# -----------------------------------------------------------------------------

resource "random_id" "db_suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# Passwords
# -----------------------------------------------------------------------------

resource "random_password" "db_admin_password" {
  length  = 24
  special = false
}

resource "random_password" "db_repl_password" {
  length  = 24
  special = false
}

# -----------------------------------------------------------------------------
# Cloud SQL PostgreSQL Instance
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "postgres" {
  name             = "${var.name_prefix}-pg-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region

  # Allow clean teardown for demo environments
  deletion_protection = false

  # PSA peering must exist before Cloud SQL can create its network interface
  depends_on = [google_service_networking_connection.psa]

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = false
    edition           = "ENTERPRISE"

    # Private IP only — no public IP
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      allocated_ip_range                            = google_compute_global_address.psa_range.name
      enable_private_path_for_google_cloud_services = true
    }

    # Enable logical decoding for Debezium CDC
    database_flags {
      name  = "cloudsql.logical_decoding"
      value = "on"
    }

    database_flags {
      name  = "max_replication_slots"
      value = "10"
    }

    # Enable IAM database authentication for Managed Kafka Connect
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    backup_configuration {
      enabled = false
    }

    user_labels = local.common_labels
  }
}

# -----------------------------------------------------------------------------
# Chinook Database
# -----------------------------------------------------------------------------

resource "google_sql_database" "chinook" {
  name      = "chinook"
  instance  = google_sql_database_instance.postgres.name
  charset   = "UTF8"
  collation = "en_US.UTF8"

  # On destroy: drop the CDC replication slot, publication, and reassign
  # object ownership from the Managed Kafka IAM user back to admin.
  # Without this, DROP DATABASE and DROP USER fail due to active slots
  # and owned objects.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up CDC runtime state before database deletion..."

      # GCS staging bucket for SQL import — ensure it exists
      GCS_BUCKET="gs://${self.project}-sql-import"
      gcloud storage buckets create "$GCS_BUCKET" --project="${self.project}" --location=eu --quiet 2>/dev/null || true

      # Grant Cloud SQL SA access to the bucket (may have been revoked during destroy)
      CLOUDSQL_SA=$(gcloud sql instances describe "${self.instance}" \
        --project="${self.project}" --format="value(serviceAccountEmailAddress)" 2>/dev/null) || true
      if [[ -n "$CLOUDSQL_SA" ]]; then
        gcloud storage buckets add-iam-policy-binding "$GCS_BUCKET" \
          --member="serviceAccount:$CLOUDSQL_SA" --role="roles/storage.objectViewer" --quiet 2>/dev/null || true
      fi

      # 1. Drop replication slot (blocks DROP DATABASE)
      SQL_FILE=$(mktemp /tmp/teardown_slot_XXXXXX.sql)
      cat > "$SQL_FILE" <<'SQL'
      DO $$
      BEGIN
        IF EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'debezium_slot') THEN
          PERFORM pg_drop_replication_slot('debezium_slot');
          RAISE NOTICE 'Dropped replication slot debezium_slot';
        END IF;
      END $$;
      DROP PUBLICATION IF EXISTS debezium_publication;
      SQL
      gcloud storage cp "$SQL_FILE" "$GCS_BUCKET/teardown_slot.sql" --quiet 2>&1 || true
      rm -f "$SQL_FILE"
      gcloud sql import sql "${self.instance}" "$GCS_BUCKET/teardown_slot.sql" \
        --database="${self.name}" --user=admin --project="${self.project}" --quiet 2>&1 || true
      gcloud storage rm "$GCS_BUCKET/teardown_slot.sql" --quiet 2>&1 || true

      # 2. Reassign object ownership from Managed Kafka IAM user to admin
      SQL_FILE=$(mktemp /tmp/teardown_owner_XXXXXX.sql)
      cat > "$SQL_FILE" <<'SQL'
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
        END IF;
      END $$;
      SQL
      gcloud storage cp "$SQL_FILE" "$GCS_BUCKET/teardown_owner.sql" --quiet 2>&1 || true
      rm -f "$SQL_FILE"
      gcloud sql import sql "${self.instance}" "$GCS_BUCKET/teardown_owner.sql" \
        --database="${self.name}" --user=admin --project="${self.project}" --quiet 2>&1 || true
      gcloud storage rm "$GCS_BUCKET/teardown_owner.sql" --quiet 2>&1 || true

      # Clean up staging bucket
      gcloud storage rm --recursive "$GCS_BUCKET/" --quiet 2>/dev/null || true
      gcloud storage buckets delete "$GCS_BUCKET" --quiet 2>/dev/null || true

      echo "CDC cleanup completed"
    EOT
  }
}

# -----------------------------------------------------------------------------
# Admin User (used by init_db.sh for schema setup)
# -----------------------------------------------------------------------------

resource "google_sql_user" "admin" {
  name            = "admin"
  instance        = google_sql_database_instance.postgres.name
  password        = random_password.db_admin_password.result
  deletion_policy = "ABANDON"
}
