# =============================================================================
# Input Variables
# =============================================================================
# All configurable parameters for the CDC pipeline infrastructure.
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where all resources will be deployed."
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "The GCP region for all resources. Must match across Cloud SQL, Kafka, Cloud Run, and BigQuery."
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Environment label (e.g., 'demo', 'dev'). Applied to all resources via common labels."
  type        = string
  default     = "demo"
}

variable "name_prefix" {
  description = "Prefix for resource names to avoid collisions (e.g., 'cdc-demo')."
  type        = string
  default     = "cdc-demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Primary CIDR range for the VPC subnet. Minimum /22 required for Managed Kafka Connect."
  type        = string
  default     = "10.0.0.0/22"
}

variable "vpc_connector_cidr" {
  description = "Dedicated /28 CIDR for the Serverless VPC Access Connector. Must not overlap with vpc_cidr or psa_cidr."
  type        = string
  default     = "10.8.0.0/28"
}

variable "psa_cidr_prefix_length" {
  description = "Prefix length for the Private Service Access IP range (used by Cloud SQL private IP). Typically /20 for production, /24 for demo."
  type        = number
  default     = 20
}

# -----------------------------------------------------------------------------
# Feature Flags
# -----------------------------------------------------------------------------

variable "source_connector_type" {
  description = <<-EOT
    How to deploy the CDC source connector:
    - "managed"  (default) — Built-in Cloud SQL for PostgreSQL source via Managed Kafka Connect
    - "cloudrun" — Self-hosted Debezium on Cloud Run (requires Docker image build first)
  EOT
  type        = string
  default     = "managed"

  validation {
    condition     = contains(["managed", "cloudrun"], var.source_connector_type)
    error_message = "source_connector_type must be either \"managed\" or \"cloudrun\"."
  }
}
