provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

module "gke" {
  source = "../../modules/gke-hardened"

  project_id = var.project_id
  region     = var.region
  name       = "idp-prod"

  release_channel     = "STABLE"
  deletion_protection = true

  network                       = var.network_self_link
  subnetwork                    = var.subnetwork_self_link
  pods_secondary_range_name     = var.pods_secondary_range_name
  services_secondary_range_name = var.services_secondary_range_name
  master_ipv4_cidr_block        = var.master_ipv4_cidr_block
  master_authorized_networks    = var.master_authorized_networks

  database_encryption_key = var.database_encryption_key
  boot_disk_kms_key       = var.boot_disk_kms_key

  enable_backup         = true
  backup_encryption_key = var.backup_encryption_key
  backup_retain_days    = 35

  enable_binary_authorization = true

  node_pools = {
    silver = {
      machine_type  = "n2d-standard-4"
      min_count     = 3
      max_count     = 12
      initial_count = 3
      labels        = { tier = "silver" }
    }
    gold = {
      machine_type  = "n2d-standard-8"
      min_count     = 3
      max_count     = 18
      initial_count = 3
      labels        = { tier = "gold" }
      taints = [
        { key = "tier", value = "gold", effect = "NO_SCHEDULE" }
      ]
    }
  }

  labels = var.labels
}

output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_location" {
  value = module.gke.location
}

output "workload_identity_pool" {
  value = module.gke.workload_identity_pool
}

