###############################################################################
# gke-hardened
#
# A regional, private, Workload-Identity-enabled GKE cluster with
# defaults appropriate for a regulated banking estate.
#
# Hardening summary:
#   - Private cluster (private nodes + private control plane endpoint)
#   - Master authorized networks (no 0.0.0.0/0 access to the API server)
#   - Workload Identity bound to the project's WI pool
#   - Shielded nodes (secure boot + integrity monitoring)
#   - Confidential nodes (AMD SEV) — optional but on by default
#   - VPC-native (alias IPs) — required for NetworkPolicy
#   - NetworkPolicy enabled (Calico)
#   - CMEK on boot disks + application-layer etcd encryption
#   - Cloud Audit Logs (system_components, workloads, API server) → Cloud Logging
#   - Managed Prometheus enabled
#   - Release channel REGULAR, weekend maintenance window
#   - Resource labels propagated for cost allocation
#
# Pod Security Standards are enforced via the in-tree Kubernetes admission
# controller (PodSecurity) using namespace labels in v0.2's tenant-namespace
# module. Cluster-side PSS does not require any setting on this resource.
###############################################################################

resource "google_container_cluster" "this" {
  provider = google-beta

  name     = var.name
  project  = var.project_id
  location = var.region

  # Remove the default node pool; we manage node pools as separate resources.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  release_channel {
    channel = var.release_channel
  }

  min_master_version = var.kubernetes_version

  # ---------------------------------------------------------------------------
  # VPC-native networking. Required for NetworkPolicy and modern GKE features.
  # ---------------------------------------------------------------------------
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # ---------------------------------------------------------------------------
  # Private cluster: no public IPs on nodes, private control plane endpoint.
  # ---------------------------------------------------------------------------
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = false
    }
  }

  # Lock down who can reach the control plane.
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Workload Identity — the default authn for pods to GCP services.
  # ---------------------------------------------------------------------------
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # ---------------------------------------------------------------------------
  # NetworkPolicy — required for multi-tenant default-deny.
  # ---------------------------------------------------------------------------
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  addons_config {
    network_policy_config {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    dns_cache_config {
      enabled = true
    }
    # Backup for GKE — installs the in-cluster agent. The backup plan
    # itself is a separate resource (google_gke_backup_backup_plan) gated
    # on var.enable_backup so callers can opt in to a baseline plan
    # without standing up their own.
    gke_backup_agent_config {
      enabled = var.enable_backup
    }
  }

  # ---------------------------------------------------------------------------
  # Application-layer etcd encryption — protects K8s Secrets with a CMEK.
  # Required for any workload that handles regulated data.
  # ---------------------------------------------------------------------------
  database_encryption {
    state    = "ENCRYPTED"
    key_name = var.database_encryption_key
  }

  # ---------------------------------------------------------------------------
  # Logging / monitoring — audit and SRE signal in one place.
  # ---------------------------------------------------------------------------
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "STORAGE",
      "POD",
      "DEPLOYMENT",
      "STATEFULSET",
      "DAEMONSET",
      "HPA",
      "CADVISOR",
      "KUBELET",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  # ---------------------------------------------------------------------------
  # Maintenance — weekend window by default. Tenants are warned in their SLA.
  # ---------------------------------------------------------------------------
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  # ---------------------------------------------------------------------------
  # Binary Authorization (v0.3) — only attested images may run on the
  # cluster. The attestors and policy are managed by the platform IAM team
  # in a separate Terraform stack; this resource only opts the cluster in.
  # ---------------------------------------------------------------------------
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = var.binary_authorization_evaluation_mode
    }
  }

  # ---------------------------------------------------------------------------
  # Misc safety
  # ---------------------------------------------------------------------------
  enable_shielded_nodes = true
  deletion_protection   = var.deletion_protection

  resource_labels = var.labels

  lifecycle {
    # GKE auto-bumps the min_master_version when the release channel rolls.
    # Ignore so we don't fight it on every plan.
    ignore_changes = [
      min_master_version,
    ]
  }
}

###############################################################################
# Node pools — managed as a map so tenant tiers can be added without
# touching the cluster resource itself.
###############################################################################

resource "google_container_node_pool" "this" {
  provider = google-beta

  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  initial_node_count = each.value.initial_count

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = each.value.image_type
    preemptible  = each.value.preemptible
    spot         = each.value.spot

    boot_disk_kms_key = var.boot_disk_kms_key

    oauth_scopes = each.value.oauth_scopes

    labels = merge(var.labels, each.value.labels)

    # Confidential nodes are configured under node_config in the node-pool resource.
    dynamic "confidential_nodes" {
      for_each = var.enable_confidential_nodes ? [1] : []
      content {
        enabled = true
      }
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}

###############################################################################
# Backup for GKE — baseline plan
#
# Daily backups of all namespaces, with PVCs and Secrets included, retained
# for 35 days. Opt-in via var.enable_backup (default true). Banking data
# residency: backup_location is pinned to the cluster region.
#
# This is a *baseline* plan. Tenants that need shorter RPO or cross-region
# DR add their own google_gke_backup_backup_plan keyed on their namespace.
###############################################################################

resource "google_gke_backup_backup_plan" "baseline" {
  count = var.enable_backup ? 1 : 0

  provider = google-beta

  name     = "${var.name}-baseline"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.id

  backup_config {
    include_volume_data = true
    include_secrets     = true

    all_namespaces = true

    encryption_key {
      gcp_kms_encryption_key = var.backup_encryption_key
    }
  }

  retention_policy {
    backup_delete_lock_days = var.backup_delete_lock_days
    backup_retain_days      = var.backup_retain_days
  }

  backup_schedule {
    cron_schedule = var.backup_cron_schedule
  }

  labels = var.labels
}
