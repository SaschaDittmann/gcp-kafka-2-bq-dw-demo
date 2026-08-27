# =============================================================================
# Cloud Run: Kafka Connect Services (Source + Sink)
# =============================================================================
# Two independent Kafka Connect clusters for production-like deployment:
#
# 1. Source Service — Runs the Debezium PostgreSQL CDC connector
#    - Fixed at 1 instance (one replication slot = one task)
#    - Own Connect group ID for independent offset tracking
#
# 2. Sink Service — Runs the BigQuery Sink connector
#    - Scalable from 1 to 4 instances
#    - Can scale independently based on throughput
#
# Both use the same Docker image (same plugins installed) but register
# different connectors via the REST API after deployment.
# =============================================================================

# -----------------------------------------------------------------------------
# Local: Shared Kafka Connect environment variables
# -----------------------------------------------------------------------------

locals {
  kafka_bootstrap_servers = "bootstrap.${google_managed_kafka_cluster.cluster.cluster_id}.${var.region}.managedkafka.${var.project_id}.cloud.goog:9092"

  connect_common_env = {
    CONNECT_REST_PORT                        = "8080"
    CONNECT_REST_ADVERTISED_HOST_NAME        = "localhost"
    CONNECT_BOOTSTRAP_SERVERS                = local.kafka_bootstrap_servers
    CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_STATUS_STORAGE_REPLICATION_FACTOR = "3"
    CONNECT_KEY_CONVERTER                    = "org.apache.kafka.connect.json.JsonConverter"
    CONNECT_VALUE_CONVERTER                  = "org.apache.kafka.connect.json.JsonConverter"
    CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE     = "false"
    CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE   = "false"
    CONNECT_PLUGIN_PATH                      = "/usr/share/confluent-hub-components,/etc/kafka-connect/jars"

    # SASL/OAUTHBEARER auth — worker
    CONNECT_SECURITY_PROTOCOL                          = "SASL_SSL"
    CONNECT_SASL_MECHANISM                             = "OAUTHBEARER"
    CONNECT_SASL_LOGIN_CALLBACK_HANDLER_CLASS          = "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler"
    CONNECT_SASL_JAAS_CONFIG                           = "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;"

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

  # Source-specific env vars (separate Connect cluster)
  connect_source_env = merge(local.connect_common_env, {
    CONNECT_GROUP_ID             = "cdc-source-group"
    CONNECT_CONFIG_STORAGE_TOPIC = "source-connect-configs"
    CONNECT_OFFSET_STORAGE_TOPIC = "source-connect-offsets"
    CONNECT_STATUS_STORAGE_TOPIC = "source-connect-status"
  })

  # Sink-specific env vars (separate Connect cluster)
  connect_sink_env = merge(local.connect_common_env, {
    CONNECT_GROUP_ID             = "cdc-sink-group"
    CONNECT_CONFIG_STORAGE_TOPIC = "sink-connect-configs"
    CONNECT_OFFSET_STORAGE_TOPIC = "sink-connect-offsets"
    CONNECT_STATUS_STORAGE_TOPIC = "sink-connect-status"
  })

  connect_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}/kafka-connect:latest"
}

# =============================================================================
# Source Service — Debezium PostgreSQL CDC
# =============================================================================
# Fixed at 1 instance: PostgreSQL logical replication uses a single
# replication slot, so parallelizing the source provides no benefit.
# =============================================================================

resource "google_cloud_run_v2_service" "kafka_connect_source" {
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
      max_instance_count = 1  # Fixed: 1 replication slot = 1 task
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
          memory = "1Gi"
        }
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

# =============================================================================
# Sink Service — BigQuery Sink
# =============================================================================
# Scalable from 1 to 4 instances for higher throughput. Each instance
# can handle multiple topic partitions in parallel.
# =============================================================================

resource "google_cloud_run_v2_service" "kafka_connect_sink" {
  name                = "${var.name_prefix}-connect-sink"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false

  labels = merge(local.common_labels, {
    component = "kafka-connect-sink"
  })

  template {
    service_account = google_service_account.kafka_connect.email

    scaling {
      min_instance_count = 1
      max_instance_count = 4  # Scalable based on throughput
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
          cpu    = "2"
          memory = "2Gi"
        }
      }

      dynamic "env" {
        for_each = local.connect_sink_env
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
