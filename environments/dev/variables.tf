variable "project_id" {
  description = "GCP project ID for the dev environment."
  type        = string
}

variable "region" {
  description = "GCP region. Pinned for data residency."
  type        = string
  default     = "europe-west2"
}

variable "network_self_link" {
  description = "Self-link of the pre-existing VPC."
  type        = string
}

variable "subnetwork_self_link" {
  description = "Self-link of the pre-existing subnet."
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Name of the secondary range used for Pod IPs."
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "Name of the secondary range used for Service IPs."
  type        = string
  default     = "services"
}

variable "master_ipv4_cidr_block" {
  description = "/28 range for the private control plane."
  type        = string
}

variable "master_authorized_networks" {
  description = "Networks permitted to reach the control plane."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "database_encryption_key" {
  description = "KMS key for etcd CMEK."
  type        = string
}

variable "boot_disk_kms_key" {
  description = "KMS key for node boot disks."
  type        = string
}

variable "enable_backup" {
  description = "Enable Backup for GKE on the dev cluster. Defaults off until the dedicated KMS key is provisioned; prod sets this to true."
  type        = bool
  default     = false
}

variable "backup_encryption_key" {
  description = "KMS key for Backup for GKE. Required when enable_backup is true."
  type        = string
  default     = null
}

variable "labels" {
  description = "Common labels for cost allocation and audit."
  type        = map(string)
  default = {
    env   = "dev"
    owner = "platform-engineering"
    repo  = "idp-banking-blueprint"
  }
}
