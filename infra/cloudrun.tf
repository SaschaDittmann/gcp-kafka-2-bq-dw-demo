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
    CONNECT_REST_PORT                         = "8080"
    CONNECT_REST_ADVERTISED_HOST_NAME         = "localhost"
    CONNECT_BOOTSTRAP_SERVERS                 = local.kafka_bootstrap_servers
    CONNECT_GROUP_ID                          = "cdc-source-group"
    CONNECT_CONFIG_STORAGE_TOPIC              = "source-connect-configs"
    CONNECT_OFFSET_STORAGE_TOPIC              = "source-connect-offsets"
    CONNECT_STATUS_STORAGE_TOPIC              = "source-connect-status"
    CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_STATUS_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_KEY_CONVERTER                     = "org.apache.kafka.connect.json.JsonConverter"
    CONNECT_VALUE_CONVERTER                   = "org.apache.kafka.connect.json.JsonConverter"
    CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE      = "false"
    CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE    = "true"
    CONNECT_PLUGIN_PATH                       = "/usr/share/confluent-hub-components,/etc/kafka-connect/jars"

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

  connect_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}/kafka-connect:latest"
}

# =============================================================================
# Source Service — Debezium PostgreSQL CDC
# =============================================================================

resource "google_cloud_run_v2_service" "kafka_connect_source" {
  count               = var.source_connector_type == "cloudrun" ? 1 : 0
  name                = "${var.name_prefix}-connect-source"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
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
      connector = google_vpc_access_connector.connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = local.connect_image

      ports {
        container_port = 8080
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
          port = 8080
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
    google_artifact_registry_repository.docker,
    google_managed_kafka_cluster.cluster,
  ]
}
