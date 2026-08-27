# =============================================================================
# Artifact Registry: Docker Repository for Kafka Connect Image
# =============================================================================
# Hosts the custom Kafka Connect Docker image with Debezium PostgreSQL
# Source Connector and BigQuery Sink Connector plugins.
# =============================================================================

resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = "${var.name_prefix}-docker"
  description   = "Docker repository for CDC pipeline container images"
  format        = "DOCKER"
  labels        = local.common_labels

  cleanup_policy_dry_run = false

  depends_on = [google_project_service.apis]
}
