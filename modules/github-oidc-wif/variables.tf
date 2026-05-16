variable "project_id" {
  description = "GCP project hosting the Workload Identity Pool and service accounts. Usually the same project as the cluster — keep the trust boundary tight."
  type        = string
}

variable "create_pool" {
  description = "When true (default), this call creates the Workload Identity Pool + OIDC provider. When false, the call only creates a service account + IAM binding inside an EXISTING pool — pass var.pool_resource_name. Use this to share one pool across multiple per-stack identities (terraform-bootstrap, terraform-cluster, terraform-platform, terraform-tenants, terraform-plan)."
  type        = bool
  default     = true
}

variable "pool_resource_name" {
  description = "Fully-qualified pool resource name (projects/<n>/locations/global/workloadIdentityPools/<id>). Required when create_pool = false; ignored when create_pool = true. Pass the `pool_resource_name` output of the pool-creating module call."
  type        = string
  default     = null
}

variable "pool_id" {
  description = "ID for the Workload Identity Pool. Only used when create_pool = true. Once created, this is forever — bumping it forces a full re-grant of every GitHub Actions principal."
  type        = string
  default     = "github-actions"
}

variable "provider_id" {
  description = "ID for the OIDC provider inside the pool. Only used when create_pool = true. Multiple providers per pool are supported (e.g. one per SaaS); we ship one for github.com."
  type        = string
  default     = "github"
}

variable "github_owner" {
  description = "GitHub user or org name that owns the repository. Used to narrow the OIDC attribute_condition so only this org's workflows can mint tokens against the pool, and as the principalSet anchor on each per-stack IAM binding."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name (without the owner prefix). Combined with var.github_owner forms `<owner>/<repo>` — the only repo the SAs in this pool can be impersonated from."
  type        = string
}

variable "allowed_branches" {
  description = "GitHub refs allowed to assume any SA in this pool. Only used when create_pool = true. Defaults to main only — feature branches plan via the read-only plan identity. Pattern is `refs/heads/<name>` or `refs/pull/*/merge`."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "service_account_id" {
  description = "Account ID for the service account this call creates. Becomes <id>@<project>.iam.gserviceaccount.com. Each per-stack identity passes its own ID (terraform-bootstrap / terraform-cluster / terraform-platform / terraform-tenants / terraform-plan)."
  type        = string
  default     = "terraform-actions"
}

variable "service_account_display_name" {
  description = "Human-readable display name for the service account. Shown in the GCP console and in audit logs."
  type        = string
  default     = "Terraform Actions"
}

variable "service_account_description" {
  description = "Description recorded against the service account. Surface what the SA can change so a reviewer reading IAM does not have to read code to know."
  type        = string
  default     = "Identity for Terraform plan + apply workflows in GitHub Actions. Impersonated via WIF; never has a static key."
}

variable "project_roles" {
  description = "Project-level roles granted to THIS service account. Keep to the minimum surface the stack actually needs — every per-stack SA should have a narrower role list than a 'covers everything' SA would have."
  type        = list(string)
  default     = []
}
