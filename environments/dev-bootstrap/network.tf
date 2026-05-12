###############################################################################
# VPC + Subnet + Cloud NAT
#
# Private GKE nodes have no public IPs, so Cloud NAT is required to pull
# images from public registries. The subnet is VPC-native (alias IPs) and
# carries the two secondary ranges GKE expects for Pods and Services.
###############################################################################

resource "google_compute_network" "vpc" {
  name                    = "idp-vpc"
  project                 = google_project.this.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "dev" {
  name          = "idp-dev"
  project       = google_project.this.project_id
  region        = var.region
  network       = google_compute_network.vpc.self_link
  ip_cidr_range = var.subnet_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

###############################################################################
# Cloud Router + Cloud NAT — egress for private nodes.
###############################################################################

resource "google_compute_router" "router" {
  name    = "idp-router"
  project = google_project.this.project_id
  region  = var.region
  network = google_compute_network.vpc.self_link
}

resource "google_compute_router_nat" "nat" {
  name                               = "idp-nat"
  project                            = google_project.this.project_id
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

###############################################################################
# Firewall rules
#
# - Allow IAP-tunnelled SSH to the bastion (35.235.240.0/20 is Google's
#   IAP source range; documented in https://cloud.google.com/iap/docs/using-tcp-forwarding).
# - Allow the bastion to reach the cluster control plane CIDR.
###############################################################################

resource "google_compute_firewall" "iap_ssh" {
  name    = "allow-iap-ssh"
  project = google_project.this.project_id
  network = google_compute_network.vpc.self_link

  description   = "Permit SSH from Google IAP to the bastion only."
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "bastion_to_control_plane" {
  name    = "allow-bastion-to-gke-master"
  project = google_project.this.project_id
  network = google_compute_network.vpc.self_link

  description        = "Permit the bastion (by tag) to reach the private GKE control plane CIDR on 443."
  direction          = "EGRESS"
  destination_ranges = [var.master_ipv4_cidr_block]
  target_tags        = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}
