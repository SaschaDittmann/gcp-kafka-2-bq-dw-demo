# =============================================================================
# Terraform Configuration & Provider Setup
# =============================================================================
# Root module for the Real-Time CDC Pipeline demo.
# Provisions all GCP infrastructure: networking, Cloud SQL, Managed Kafka,
# Kafka Connect on Cloud Run, and BigQuery datasets/tables.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }

  # Local state for demo — no remote backend required
  backend "local" {}
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# Common Labels
# Applied to all resources for traceability and cost tracking.
# -----------------------------------------------------------------------------

locals {
  common_labels = {
    managed_by = "terraform"
    project    = "cdc-pipeline-demo"
    env        = var.environment
  }
}

# -----------------------------------------------------------------------------
# Enable Required GCP APIs
# Uses for_each to manage all APIs in a single resource block.
# disable_on_destroy = false prevents cascading failures on terraform destroy.
# -----------------------------------------------------------------------------

locals {
  required_services = [
    "compute.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "managedkafka.googleapis.com",
    "secretmanager.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "bigquery.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "iam.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each                   = toset(local.required_services)
  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false
}
