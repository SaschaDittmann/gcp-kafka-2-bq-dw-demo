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
