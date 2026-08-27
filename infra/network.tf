# =============================================================================
# Networking: VPC, Subnet, Firewall, VPC Connector, Private Service Access
# =============================================================================
# Defines the network topology for the CDC pipeline:
# - Custom VPC with a single subnet in europe-west1
# - Firewall rules for internal communication (Cloud SQL, Kafka, Kafka Connect)
# - Serverless VPC Access Connector for Cloud Run → VPC connectivity
# - Private Service Access for Cloud SQL private IP
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Network
# Custom mode (auto_create_subnetworks = false) to control CIDR allocation.
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Custom VPC for CDC streaming pipeline"

  depends_on = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# Subnet
# Single subnet in the pipeline region with Private Google Access enabled
# so that Cloud Run and other private resources can reach GCP APIs.
# -----------------------------------------------------------------------------

resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.name_prefix}-subnet-${var.region}"
  ip_cidr_range            = var.vpc_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Primary subnet for CDC pipeline compute and managed services"
}

# -----------------------------------------------------------------------------
# Firewall Rules
# -----------------------------------------------------------------------------

# Allow internal communication between all resources within the VPC.
# Covers: PostgreSQL (5432), Kafka (9092-9093), Kafka Connect REST API (8083).
resource "google_compute_firewall" "allow_internal" {
  name        = "${var.name_prefix}-allow-internal"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow internal TCP traffic for CDC pipeline services"

  source_ranges = [var.vpc_cidr, var.vpc_connector_cidr]

  allow {
    protocol = "tcp"
    ports    = ["5432", "8083", "9092", "9093"]
  }

  allow {
    protocol = "icmp"
  }
}

# Allow health check probes from Google's health check IP ranges.
# Required for Cloud Run and load balancer health checks.
resource "google_compute_firewall" "allow_health_checks" {
  name        = "${var.name_prefix}-allow-health-checks"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow Google health check probes"

  # Google health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
    ports    = ["8083"]
  }
}

# -----------------------------------------------------------------------------
# Serverless VPC Access Connector
# Enables Cloud Run to communicate with private IP resources (Cloud SQL,
# Managed Kafka) in the VPC. Uses a dedicated /28 CIDR block.
# -----------------------------------------------------------------------------

resource "google_vpc_access_connector" "connector" {
  name          = "${var.name_prefix}-vpc-connector"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = var.vpc_connector_cidr

  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"

  labels = local.common_labels

  depends_on = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# Private Service Access (PSA)
# Required for Cloud SQL to use a private IP address within the VPC.
# Allocates a dedicated IP range and creates a peering connection.
# -----------------------------------------------------------------------------

resource "google_compute_global_address" "psa_range" {
  name          = "${var.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_cidr_prefix_length
  network       = google_compute_network.vpc.id
  description   = "Reserved IP range for Private Service Access (Cloud SQL)"
  labels        = local.common_labels
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]

  depends_on = [google_project_service.apis]
}
