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
