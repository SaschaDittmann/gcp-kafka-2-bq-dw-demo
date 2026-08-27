# =============================================================================
# Terraform Outputs
# =============================================================================
# Exports key resource identifiers for use by deployment scripts and
# downstream Terraform configurations (Cloud SQL, Kafka, Cloud Run, BigQuery).
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

output "vpc_connector_name" {
  description = "The name of the Serverless VPC Access Connector for Cloud Run."
  value       = google_vpc_access_connector.connector.name
}

output "vpc_connector_id" {
  description = "The full resource ID of the Serverless VPC Access Connector."
  value       = google_vpc_access_connector.connector.id
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
# Artifact Registry
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
# Cloud Run
# -----------------------------------------------------------------------------

output "cloudrun_source_service_name" {
  description = "The Cloud Run source (Debezium) service name."
  value       = google_cloud_run_v2_service.kafka_connect_source.name
}

output "cloudrun_source_service_url" {
  description = "The Cloud Run source service URL."
  value       = google_cloud_run_v2_service.kafka_connect_source.uri
}

output "cloudrun_sink_service_name" {
  description = "The Cloud Run sink (BigQuery) service name."
  value       = google_cloud_run_v2_service.kafka_connect_sink.name
}

output "cloudrun_sink_service_url" {
  description = "The Cloud Run sink service URL."
  value       = google_cloud_run_v2_service.kafka_connect_sink.uri
}
