###############################################################################
# environments/dev
#
# Reference composition that wires the gke-hardened module into a working
# development environment. Network, KMS keys, and bastion are assumed to be
# managed elsewhere (intentional — they're shared, not per-environment).
###############################################################################

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
  name       = "idp-dev"

  network                       = var.network_self_link
  subnetwork                    = var.subnetwork_self_link
  pods_secondary_range_name     = var.pods_secondary_range_name
  services_secondary_range_name = var.services_secondary_range_name
  master_ipv4_cidr_block        = var.master_ipv4_cidr_block
  master_authorized_networks    = var.master_authorized_networks

  database_encryption_key = var.database_encryption_key
  boot_disk_kms_key       = var.boot_disk_kms_key

  # Backup for GKE: opt in once the backup-dedicated KMS key is provisioned
  # alongside the etcd + node-disk keys. Until then, keep this off in dev
  # so the env validates without an unbound key reference. Prod must set
  # both to true and supply the key.
  enable_backup         = var.enable_backup
  backup_encryption_key = var.backup_encryption_key

  # Machine types are n2d-* (AMD) because gke-hardened defaults
  # enable_confidential_nodes = true, which requires AMD SEV — supported
  # on N2D family only. e2-* / n2-* (Intel) machines will fail at apply
  # with "Confidential nodes feature is not supported for instance type SEV".
  node_pools = {
    bronze = {
      machine_type  = "n2d-standard-4"
      min_count     = 1
      max_count     = 5
      initial_count = 1
      spot          = true
      labels        = { tier = "bronze" }
      taints = [
        { key = "tier", value = "bronze", effect = "NO_SCHEDULE" }
      ]
    }
    silver = {
      machine_type  = "n2d-standard-4"
      min_count     = 2
      max_count     = 10
      initial_count = 2
      labels        = { tier = "silver" }
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
