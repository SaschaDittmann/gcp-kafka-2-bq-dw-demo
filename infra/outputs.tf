# =============================================================================
# Terraform Outputs
# =============================================================================
# Exports key resource identifiers for use by deployment scripts and
# downstream Terraform configurations (Cloud SQL, Kafka, Kafka Connect,
# BigQuery).
# =============================================================================

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the CDC pipeline VPC network."
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "The name of the CDC pipeline VPC network."
  value       = google_compute_network.vpc.name
}

output "subnet_self_link" {
  description = "The self-link of the primary subnet."
  value       = google_compute_subnetwork.subnet.self_link
}

output "subnet_name" {
  description = "The name of the primary subnet."
  value       = google_compute_subnetwork.subnet.name
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

output "kafka_connect_sa_email" {
  description = "The email address of the Kafka Connect service account."
  value       = google_service_account.kafka_connect.email
}

output "kafka_connect_sa_member" {
  description = "The IAM member string for the Kafka Connect service account."
  value       = google_service_account.kafka_connect.member
}

# -----------------------------------------------------------------------------
# Cloud SQL
# -----------------------------------------------------------------------------

output "cloudsql_instance_name" {
  description = "The Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "cloudsql_connection_name" {
  description = "Cloud SQL connection name (project:region:instance)."
  value       = google_sql_database_instance.postgres.connection_name
}

output "cloudsql_private_ip" {
  description = "Private IP address of the Cloud SQL PostgreSQL instance."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "cloudsql_database_name" {
  description = "The name of the Chinook database."
  value       = google_sql_database.chinook.name
}

output "cloudsql_admin_user" {
  description = "The admin database username."
  value       = google_sql_user.admin.name
}

output "cloudsql_admin_password" {
  description = "The admin database password."
  value       = random_password.db_admin_password.result
  sensitive   = true
}

output "cloudsql_repl_password" {
  description = "The replication user password."
  value       = random_password.db_repl_password.result
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Kafka
# -----------------------------------------------------------------------------

output "kafka_cluster_id" {
  description = "The Managed Kafka cluster ID."
  value       = google_managed_kafka_cluster.cluster.cluster_id
}

output "kafka_bootstrap_server" {
  description = "The Kafka bootstrap server endpoint."
  value       = "bootstrap.${google_managed_kafka_cluster.cluster.cluster_id}.${var.region}.managedkafka.${var.project_id}.cloud.goog:9092"
}

output "kafka_topic_names" {
  description = "List of all Chinook CDC topic names."
  value       = [for t in google_managed_kafka_topic.chinook : t.topic_id]
}

# -----------------------------------------------------------------------------
# Kafka Connect
# -----------------------------------------------------------------------------

output "connect_cluster_id" {
  description = "The Managed Kafka Connect cluster ID."
  value       = google_managed_kafka_connect_cluster.connect.connect_cluster_id
}

output "connect_source_connector_id" {
  description = "The managed CDC source connector ID (null when source_connector_type = cloudrun)."
  value       = var.source_connector_type == "managed" ? google_managed_kafka_connector.cdc_source[0].connector_id : null
}

output "connect_bigquery_sink_id" {
  description = "The BigQuery sink connector ID."
  value       = google_managed_kafka_connector.bigquery_sink.connector_id
}

output "connect_gcs_sink_id" {
  description = "The GCS archive sink connector ID."
  value       = google_managed_kafka_connector.gcs_sink.connector_id
}

output "cdc_archive_bucket" {
  description = "The GCS bucket for long-term CDC event archive."
  value       = google_storage_bucket.cdc_archive.name
}

# -----------------------------------------------------------------------------
# Artifact Registry (for Cloud Run source deployment)
# -----------------------------------------------------------------------------

output "artifact_registry_repository" {
  description = "The Artifact Registry Docker repository ID."
  value       = google_artifact_registry_repository.docker.repository_id
}

output "artifact_registry_url" {
  description = "The full Artifact Registry URL for docker push/pull."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

# -----------------------------------------------------------------------------
# Cloud Run (deployed when source_connector_type = "cloudrun")
# -----------------------------------------------------------------------------

output "vpc_connector_name" {
  description = "The name of the Serverless VPC Access Connector for Cloud Run."
  value       = google_vpc_access_connector.connector.name
}

output "vpc_connector_id" {
  description = "The full resource ID of the Serverless VPC Access Connector."
  value       = google_vpc_access_connector.connector.id
}

output "cloudrun_source_service_name" {
  description = "The Cloud Run source (Debezium) service name."
  value       = var.source_connector_type == "cloudrun" ? google_cloud_run_v2_service.kafka_connect_source[0].name : null
}

output "cloudrun_source_service_url" {
  description = "The Cloud Run source service URL."
  value       = var.source_connector_type == "cloudrun" ? google_cloud_run_v2_service.kafka_connect_source[0].uri : null
}

output "cloudrun_deployer_sa_email" {
  description = "The service account email used for connector deployment."
  value       = var.source_connector_type == "cloudrun" ? google_service_account.connect_deployer[0].email : null
}

# -----------------------------------------------------------------------------
# BigQuery
# -----------------------------------------------------------------------------

output "bigquery_datasets" {
  description = "The BigQuery dataset IDs (bronze, silver, gold)."
  value = {
    bronze = google_bigquery_dataset.bronze.dataset_id
    silver = google_bigquery_dataset.silver.dataset_id
    gold   = google_bigquery_dataset.gold.dataset_id
  }
}

output "iceberg_bucket" {
  description = "The GCS bucket for Gold layer Iceberg data."
  value       = google_storage_bucket.iceberg_data.name
}

output "iceberg_connection" {
  description = "The BigQuery connection for Iceberg tables."
  value       = google_bigquery_connection.iceberg.name
}
