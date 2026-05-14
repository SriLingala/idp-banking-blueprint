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

variable "github_owner" {
  description = "GitHub user/org owning this repo. Used to scope the Workload Identity Federation pool to the right OIDC subject."
  type        = string
  default     = "SriLingala"
}

variable "github_repository" {
  description = "GitHub repo name (no owner prefix) that hosts these Terraform stacks and CI/CD workflows."
  type        = string
  default     = "idp-banking-blueprint"
}

variable "github_actions_allowed_branches" {
  description = "Refs allowed to assume the terraform-actions APPLY SA. Default main only — apply happens after PR merge."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "github_actions_plan_allowed_branches" {
  description = "Refs allowed to assume the terraform-plan READ-ONLY SA. Covers PR-time plans on any branch (refs/pull/*/merge) plus speculative plans on main."
  type        = list(string)
  default     = ["refs/pull/*/merge", "refs/heads/main"]
}

variable "github_actions_plan_roles" {
  description = "Project-level roles granted to the terraform-plan SA. Read-only by design — these surfaces are enough to refresh state and compute a diff against the live infrastructure without being able to mutate anything."
  type        = list(string)
  default = [
    # State bucket: read object, list bucket. Plans use -lock=false so
    # no write needed.
    "roles/storage.objectViewer",
    # Compute / Network read for VPC, subnets, NAT, firewall plans
    "roles/compute.viewer",
    # GKE cluster + backup plans
    "roles/container.viewer",
    "roles/gkebackup.viewer",
    # KMS — read key + binding state
    "roles/cloudkms.viewer",
    # Service accounts and IAM bindings the plan needs to refresh
    "roles/iam.securityReviewer",
    # Logging / monitoring resources
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    # Binary Authorization
    "roles/binaryauthorization.policyViewer",
    # Workload Identity Federation pool / provider state
    "roles/iam.workloadIdentityPoolViewer",
  ]
}
