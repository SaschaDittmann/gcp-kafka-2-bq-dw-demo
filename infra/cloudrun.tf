# =============================================================================
# Cloud Run: Kafka Connect Source Service (Debezium CDC)
# =============================================================================
# Self-hosted Kafka Connect on Cloud Run for the Debezium PostgreSQL CDC
# source connector. Only deployed when source_connector_type = "cloudrun".
#
# The BigQuery and GCS sinks are always handled by Managed Kafka Connect,
# so no Cloud Run sink service is needed.
#
# Fixed at 1 instance: PostgreSQL logical replication uses a single
# replication slot, so parallelizing the source provides no benefit.
# =============================================================================

# -----------------------------------------------------------------------------
# Local: Kafka Connect environment variables
# -----------------------------------------------------------------------------

locals {
  kafka_bootstrap_servers = "bootstrap.${google_managed_kafka_cluster.cluster.cluster_id}.${var.region}.managedkafka.${var.project_id}.cloud.goog:9092"

  connect_source_env = {
    # Debezium Connect well-known env vars
    BOOTSTRAP_SERVERS    = local.kafka_bootstrap_servers
    GROUP_ID             = "cdc-source-group"
    CONFIG_STORAGE_TOPIC = "source-connect-configs"
    OFFSET_STORAGE_TOPIC = "source-connect-offsets"
    STATUS_STORAGE_TOPIC = "source-connect-status"
    KEY_CONVERTER        = "org.apache.kafka.connect.json.JsonConverter"
    VALUE_CONVERTER      = "org.apache.kafka.connect.json.JsonConverter"

    # Bind REST API to all interfaces (required for Cloud Run routing)
    # In Kafka 3.x+, 'listeners' supersedes deprecated rest.host.name/rest.port
    CONNECT_LISTENERS = "http://0.0.0.0:8083"

    # Additional Connect worker properties (CONNECT_ prefix → dots)
    CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_STATUS_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE      = "false"
    CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE    = "true"

    # SASL/OAUTHBEARER auth — worker
    CONNECT_SECURITY_PROTOCOL                 = "SASL_SSL"
    CONNECT_SASL_MECHANISM                    = "OAUTHBEARER"
    CONNECT_SASL_LOGIN_CALLBACK_HANDLER_CLASS = "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler"
    CONNECT_SASL_JAAS_CONFIG                  = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;"

    # SASL/OAUTHBEARER auth — producer
    CONNECT_PRODUCER_SECURITY_PROTOCOL                 = "SASL_SSL"
    CONNECT_PRODUCER_SASL_MECHANISM                    = "OAUTHBEARER"
    CONNECT_PRODUCER_SASL_LOGIN_CALLBACK_HANDLER_CLASS = "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler"
    CONNECT_PRODUCER_SASL_JAAS_CONFIG                  = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;"

    # SASL/OAUTHBEARER auth — consumer
    CONNECT_CONSUMER_SECURITY_PROTOCOL                 = "SASL_SSL"
    CONNECT_CONSUMER_SASL_MECHANISM                    = "OAUTHBEARER"
    CONNECT_CONSUMER_SASL_LOGIN_CALLBACK_HANDLER_CLASS = "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler"
    CONNECT_CONSUMER_SASL_JAAS_CONFIG                  = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;"
  }

  connect_image = var.source_connector_type == "cloudrun" ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker[0].repository_id}/kafka-connect:latest" : ""
}

# -----------------------------------------------------------------------------
# Build Kafka Connect Docker Image via Cloud Build
# -----------------------------------------------------------------------------
# Builds and pushes the custom Kafka Connect image to Artifact Registry
# before the Cloud Run service is created. Re-triggers on Dockerfile changes.
# -----------------------------------------------------------------------------

resource "null_resource" "build_connect_image" {
  count = var.source_connector_type == "cloudrun" ? 1 : 0

  triggers = {
    dockerfile_hash = filemd5("${path.module}/../connect/Dockerfile")
  }

  provisioner "local-exec" {
    command = "gcloud builds submit ${path.module}/../connect/ --tag=${local.connect_image} --project=${var.project_id} --quiet"
  }

  depends_on = [
    google_artifact_registry_repository.docker,
    google_project_iam_member.cloudbuild_storage,
    google_project_iam_member.cloudbuild_logs,
    google_project_iam_member.cloudbuild_ar_writer,
  ]
}

# =============================================================================
# Source Service — Debezium PostgreSQL CDC
# =============================================================================

resource "google_cloud_run_v2_service" "kafka_connect_source" {
  count               = var.source_connector_type == "cloudrun" ? 1 : 0
  name                = "${var.name_prefix}-connect-source"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  labels = merge(local.common_labels, {
    component = "kafka-connect-source"
  })

  template {
    service_account = google_service_account.kafka_connect.email

    scaling {
      min_instance_count = 1
      max_instance_count = 1 # 1 replication slot = 1 instance
    }

    vpc_access {
      connector = google_vpc_access_connector.connector[0].id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = local.connect_image

      ports {
        container_port = 8083
      }

      resources {
        cpu_idle = false
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }

      startup_probe {
        http_get {
          path = "/connectors"
          port = 8083
        }
        initial_delay_seconds = 30
        period_seconds        = 10
        failure_threshold     = 24 # 30 + (24 * 10) = 270s max
        timeout_seconds       = 5
      }

      dynamic "env" {
        for_each = local.connect_source_env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  depends_on = [
    null_resource.build_connect_image,
    google_managed_kafka_cluster.cluster,
  ]
}

# -----------------------------------------------------------------------------
# Service Account for Connector Deployment
# -----------------------------------------------------------------------------
# A dedicated SA used by deploy.sh to authenticate when registering connectors
# via the Cloud Run REST API. The deployer impersonates this SA to obtain an
# identity token with the correct audience.

resource "google_service_account" "connect_deployer" {
  count        = var.source_connector_type == "cloudrun" ? 1 : 0
  account_id   = "${var.name_prefix}-connect-deploy"
  display_name = "Kafka Connect Deployer"
  project      = var.project_id
}

# Allow the SA to invoke the Cloud Run source service
resource "google_cloud_run_v2_service_iam_member" "source_invoker" {
  count    = var.source_connector_type == "cloudrun" ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.kafka_connect_source[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.connect_deployer[0].email}"
}

# Allow the Terraform deployer to impersonate this SA (for identity tokens)
data "google_client_openid_userinfo" "me" {}

resource "google_service_account_iam_member" "deployer_can_impersonate" {
  count              = var.source_connector_type == "cloudrun" ? 1 : 0
  service_account_id = google_service_account.connect_deployer[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${data.google_client_openid_userinfo.me.email}"
}
