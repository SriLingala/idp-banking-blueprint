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
  description = "Bastion VM size. e2-small is plenty for an SSH jump host; bump to e2-medium when also running the GitHub Actions self-hosted runner."
  type        = string
  default     = "e2-small"
}

variable "github_runner_token" {
  description = "GitHub Actions self-hosted runner registration token. Short-lived (1 hour). Generate via `gh api -X POST /repos/<owner>/<repo>/actions/runners/registration-token --jq .token`. Leave empty to skip runner registration entirely — the bastion still functions as a human SSH jump host. Required when you want the terraform-plan workflow's private-cluster matrix entries (dev-platform, dev-tenants) to run."
  type        = string
  default     = ""
  sensitive   = true
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

# ─────────────────────────────────────────────────────────────────────────────
# Per-stack APPLY role surfaces.
#
# Each apply SA holds only the roles its own stack needs. Splitting like this
# bounds blast radius: a compromise of the terraform-platform workflow
# cannot recreate the project, rotate KMS, or destroy the cluster. ADR-0005
# documents the rationale.
#
# These defaults are tuned for the trial topology; production deployments
# should still review each list against the actual resources their stack
# manages.
# ─────────────────────────────────────────────────────────────────────────────

variable "github_actions_bootstrap_roles" {
  description = "Roles for the terraform-bootstrap APPLY SA. Owns project + IAM admin, KMS, networking, state bucket, bastion. Highest-privilege SA, lowest-frequency change."
  type        = list(string)
  default = [
    # Project & service usage
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",

    # IAM administration (creates all downstream SAs, manages bindings)
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityPoolAdmin",

    # Networking (VPC, subnets, Cloud NAT, firewall, bastion)
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.instanceAdmin.v1",

    # Bastion IAP grant
    "roles/iap.admin",

    # Storage (creates the state bucket)
    "roles/storage.admin",

    # KMS — key + ring + binding admin (NOT raw encrypt/decrypt; that's
    # for service agents). Bootstrap owns the keys; cluster only consumes.
    "roles/cloudkms.admin",

    # Logging / monitoring sink admin
    "roles/logging.admin",
    "roles/monitoring.admin",
  ]
}

variable "github_actions_cluster_roles" {
  description = "Roles for the terraform-cluster APPLY SA. Manages the GKE cluster + node pools + Binary Authorization + Backup for GKE. No project IAM admin, no KMS admin, no network mutation."
  type        = list(string)
  default = [
    # State bucket read+write for this stack's state object only (bucket
    # IAM is bootstrap's job). objectAdmin is the narrowest workable role
    # because terraform needs read + write + delete + version listing.
    "roles/storage.objectAdmin",

    # Cluster + node-pool lifecycle
    "roles/container.admin",
    "roles/gkebackup.admin",
    "roles/binaryauthorization.policyAdmin",

    # Network read (needs subnet + secondary-range refs but never mutates)
    "roles/compute.networkViewer",

    # Service account user — so the GKE node SA can be attached to node pools
    "roles/iam.serviceAccountUser",

    # KMS — encrypt/decrypt only (NOT key admin). Required so the cluster
    # can wrap etcd + boot-disk + backup material with the bootstrap-owned keys.
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
  ]
}

variable "github_actions_platform_roles" {
  description = "Roles for the terraform-platform APPLY SA. Installs Argo CD into the cluster via Helm. Cluster-scoped operations only — no project mutation. The Kubernetes-side privilege is whatever cluster-admin RBAC the kubeconfig binds; this role list only covers reaching the cluster API."
  type        = list(string)
  default = [
    # State bucket
    "roles/storage.objectAdmin",

    # Reach the cluster API (gets a kubeconfig; no mutation of the cluster
    # object itself — container.developer is the K8s-API-only surface)
    "roles/container.developer",

    # OIDC / impersonation user for downstream auth steps
    "roles/iam.serviceAccountTokenCreator",
  ]
}

variable "github_actions_tenants_roles" {
  description = "Roles for the terraform-tenants APPLY SA. Creates per-tenant namespaces, quotas, network policies, and binds tenant KSAs to their GSAs. Same K8s-API-only surface as platform plus the SA-user role for KSA→GSA Workload Identity bindings."
  type        = list(string)
  default = [
    # State bucket
    "roles/storage.objectAdmin",

    # Reach the cluster API
    "roles/container.developer",

    # Bind tenant KSAs to tenant GSAs (per-namespace WI annotations)
    "roles/iam.serviceAccountUser",
    "roles/iam.serviceAccountTokenCreator",
  ]
}
