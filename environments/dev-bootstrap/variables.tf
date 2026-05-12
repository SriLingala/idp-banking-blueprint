variable "project_id_prefix" {
  description = "Prefix for the auto-generated GCP project ID. A 6-char random suffix is appended to keep it globally unique."
  type        = string
  default     = "idp-bank-trial"
}

variable "project_name" {
  description = "Human-readable project name (shown in the GCP console)."
  type        = string
  default     = "IDP Banking Trial"
}

variable "billing_account" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX) to link to the new project."
  type        = string
}

variable "region" {
  description = "GCP region the trial runs in."
  type        = string
  default     = "us-central1"
}

variable "subnet_cidr" {
  description = "Primary CIDR for the dev subnet (nodes)."
  type        = string
  default     = "10.20.0.0/22"
}

variable "pods_cidr" {
  description = "Secondary CIDR for Pod IPs (VPC-native). Must not overlap subnet_cidr."
  type        = string
  default     = "10.21.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR for Service IPs."
  type        = string
  default     = "10.22.0.0/20"
}

variable "master_ipv4_cidr_block" {
  description = "/28 reserved for the private GKE control plane endpoint."
  type        = string
  default     = "172.16.0.0/28"
}

variable "bastion_machine_type" {
  description = "Bastion VM size. e2-small is plenty for an SSH jump host."
  type        = string
  default     = "e2-small"
}

variable "labels" {
  description = "Labels applied to every taggable resource in this stack."
  type        = map(string)
  default = {
    env     = "dev"
    purpose = "idp-banking-trial"
    owner   = "platform-engineering"
  }
}
