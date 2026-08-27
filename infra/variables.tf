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
  description = "Primary CIDR range for the VPC subnet."
  type        = string
  default     = "10.0.1.0/24"
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
