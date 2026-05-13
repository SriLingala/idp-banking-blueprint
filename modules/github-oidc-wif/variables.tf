variable "project_id" {
  description = "GCP project hosting the Workload Identity Pool. Usually the same project as the cluster — keep the trust boundary tight."
  type        = string
}

variable "pool_id" {
  description = "ID for the Workload Identity Pool. Once created, this is forever — bumping it forces a full re-grant of every GitHub Actions principal."
  type        = string
  default     = "github-actions"
}

variable "provider_id" {
  description = "ID for the OIDC provider inside the pool. Multiple providers per pool are supported (e.g. one per SaaS); we ship one for github.com."
  type        = string
  default     = "github"
}

variable "github_owner" {
  description = "GitHub user or org name that owns the repository. Used to narrow the OIDC attribute_condition so only this org's workflows can mint tokens against the pool."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name (without the owner prefix). Combined with var.github_owner forms `<owner>/<repo>` — the only repo the SA can be impersonated from."
  type        = string
}

variable "allowed_branches" {
  description = "GitHub refs allowed to assume the terraform-actions SA. Defaults to main only — feature branches plan via separate read-only credentials in a follow-up. Pattern is `refs/heads/<name>` or `refs/tags/<name>`."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "service_account_id" {
  description = "Account ID for the terraform-actions service account. Becomes <id>@<project>.iam.gserviceaccount.com."
  type        = string
  default     = "terraform-actions"
}

variable "project_roles" {
  description = "Project-level roles granted to the terraform-actions SA. The defaults cover the minimum surface for the bootstrap → cluster → platform → tenants chain. Tighten or split per-stack in prod with separate SAs."
  type        = list(string)
  default = [
    # Project / billing / IAM administration
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/serviceusage.serviceUsageAdmin",

    # Networking
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.instanceAdmin.v1",

    # Storage (state bucket + GKE artefacts)
    "roles/storage.admin",

    # KMS — key + binding management (NOT raw encrypt/decrypt; that's
    # for service agents)
    "roles/cloudkms.admin",

    # GKE cluster + workload identity admin
    "roles/container.admin",
    "roles/gkebackup.admin",
    "roles/binaryauthorization.policyAdmin",

    # IAP (bastion tunnel grant)
    "roles/iap.admin",

    # Logging / monitoring (project-level service-agent provisioning)
    "roles/logging.admin",
    "roles/monitoring.admin",
  ]
}

