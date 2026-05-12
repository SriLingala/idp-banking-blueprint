variable "project_id" {
  description = "GCP project ID hosting the cluster."
  type        = string
}

variable "region" {
  description = "GCP region. Regional cluster — pinned for data residency."
  type        = string
}

variable "name" {
  description = "Cluster name. Will be prefixed with the environment in calling code."
  type        = string
}

variable "network" {
  description = "Self-link of the VPC network the cluster attaches to."
  type        = string
}

variable "subnetwork" {
  description = "Self-link of the subnet. Must have secondary ranges for Pods and Services."
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Name of the secondary IP range for Pods (VPC-native)."
  type        = string
}

variable "services_secondary_range_name" {
  description = "Name of the secondary IP range for Services (VPC-native)."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "RFC1918 /28 range used by the private cluster control plane."
  type        = string
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the private control plane (admin/CI). Locked down by default."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "release_channel" {
  description = "GKE release channel. REGULAR is the default — stable but recent."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE."
  }
}

variable "kubernetes_version" {
  description = "Pin a specific minor version (e.g. 1.30) — leave null to track the release channel default."
  type        = string
  default     = null
}

variable "database_encryption_key" {
  description = "KMS key self-link for etcd application-layer encryption. Required in regulated environments."
  type        = string
}

variable "boot_disk_kms_key" {
  description = "KMS key self-link for node boot disk CMEK."
  type        = string
}

variable "enable_confidential_nodes" {
  description = "Enable AMD SEV confidential nodes. Slight cost, real defence-in-depth."
  type        = bool
  default     = true
}

variable "node_pools" {
  description = "Map of node pool name → config. Use taints + tolerations for tier separation."
  type = map(object({
    machine_type   = string
    min_count      = number
    max_count      = number
    initial_count  = number
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-balanced")
    image_type     = optional(string, "COS_CONTAINERD")
    preemptible    = optional(bool, false)
    spot           = optional(bool, false)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    oauth_scopes = optional(list(string), [
      "https://www.googleapis.com/auth/cloud-platform"
    ])
  }))
}

variable "labels" {
  description = "Labels applied to the cluster and propagated to node pools."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Block accidental cluster deletion via the GCP API. Disable explicitly when decommissioning."
  type        = bool
  default     = true
}

variable "maintenance_start_time" {
  description = "RFC3339 maintenance window start. Default: 03:00 UTC."
  type        = string
  default     = "2026-01-01T03:00:00Z"
}

variable "maintenance_end_time" {
  description = "RFC3339 maintenance window end. Default: 07:00 UTC."
  type        = string
  default     = "2026-01-01T07:00:00Z"
}

variable "maintenance_recurrence" {
  description = "RRULE recurrence for the maintenance window."
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}
