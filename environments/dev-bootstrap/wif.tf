###############################################################################
# Workload Identity Federation for GitHub Actions — per-stack identities
#
# ONE pool. ONE attribute_condition (repo + ref allowlist). FIVE service
# accounts:
#
#   terraform-bootstrap  (APPLY for environments/dev-bootstrap)
#   terraform-cluster    (APPLY for environments/dev)
#   terraform-platform   (APPLY for environments/dev-platform)
#   terraform-tenants    (APPLY for environments/dev-tenants)
#   terraform-plan       (PLAN  read-only, covers every stack)
#
# Why split per-stack?
#
# A single "terraform-actions" SA needs the union of every stack's roles —
# project IAM admin (for bootstrap) plus cluster admin (for cluster) plus
# K8s admin via WI (for platform/tenants). If that SA's workflow ever runs
# malicious code (compromised PR-merge approval, supply chain on a Terraform
# provider, etc.) the blast radius is the entire estate.
#
# Per-stack SAs cap the blast radius at one stack's scope. A compromise of
# the terraform-platform workflow cannot recreate the project, rotate KMS
# keys, or delete the cluster — those are not in its role surface. The
# audit story also improves: every Cloud Audit Log entry names which stack
# was acting, not just "terraform-actions did something".
#
# The two-pool / two-attribute_condition pattern (apply pool main-only,
# plan pool PR-refs) is preserved because the trust requirement is genuinely
# different: PR refs come from less-trusted code and should never mint apply
# credentials. Splitting per-stack within EACH pool keeps that boundary.
#
# ADR-0004 (Workload Identity Federation for CI/CD) and ADR-0005 (per-stack
# identity split) document the rationale.
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# APPLY pool — main only. The first call creates the pool + provider.
# Subsequent calls reuse it via create_pool = false.
# ─────────────────────────────────────────────────────────────────────────────

# Pool-creating call. Also creates the terraform-bootstrap SA, which owns
# the highest-privilege surface (project IAM, KMS, network, state bucket).
module "github_wif" {
  source = "../../modules/github-oidc-wif"

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository
  allowed_branches  = var.github_actions_allowed_branches

  service_account_id           = "terraform-bootstrap"
  service_account_display_name = "Terraform Bootstrap"
  service_account_description  = "APPLY identity for environments/dev-bootstrap. Owns project, IAM admin, KMS, networking, state bucket, bastion."
  project_roles                = var.github_actions_bootstrap_roles

  depends_on = [google_project_service.enabled]
}

# Identity-only call: cluster apply SA, reusing the pool above.
module "github_wif_cluster" {
  source = "../../modules/github-oidc-wif"

  create_pool        = false
  pool_resource_name = module.github_wif.pool_resource_name

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository

  service_account_id           = "terraform-cluster"
  service_account_display_name = "Terraform Cluster"
  service_account_description  = "APPLY identity for environments/dev. Manages the GKE cluster + node pools + Binary Authorization + Backup for GKE. No project IAM admin, no KMS admin."
  project_roles                = var.github_actions_cluster_roles

  depends_on = [google_project_service.enabled]
}

# Identity-only call: platform apply SA.
module "github_wif_platform" {
  source = "../../modules/github-oidc-wif"

  create_pool        = false
  pool_resource_name = module.github_wif.pool_resource_name

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository

  service_account_id           = "terraform-platform"
  service_account_display_name = "Terraform Platform"
  service_account_description  = "APPLY identity for environments/dev-platform. Installs Argo CD into the cluster. Cluster-scoped via container.developer; cannot mutate the project or other clusters."
  project_roles                = var.github_actions_platform_roles

  depends_on = [google_project_service.enabled]
}

# Identity-only call: tenants apply SA.
module "github_wif_tenants" {
  source = "../../modules/github-oidc-wif"

  create_pool        = false
  pool_resource_name = module.github_wif.pool_resource_name

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository

  service_account_id           = "terraform-tenants"
  service_account_display_name = "Terraform Tenants"
  service_account_description  = "APPLY identity for environments/dev-tenants. Creates per-tenant namespaces, ResourceQuotas, NetworkPolicies, and KSA→GSA bindings. Cannot create cluster-scoped resources."
  project_roles                = var.github_actions_tenants_roles

  depends_on = [google_project_service.enabled]
}

# ─────────────────────────────────────────────────────────────────────────────
# PLAN pool — PR refs allowed, read-only roles. SINGLE plan SA covers every
# stack because read-only roles compose cleanly and the WIF binding gives
# the same auditor-visible "which workflow ran this plan" join via OIDC
# claims regardless of stack.
# ─────────────────────────────────────────────────────────────────────────────
module "github_wif_plan" {
  source = "../../modules/github-oidc-wif"

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository
  allowed_branches  = var.github_actions_plan_allowed_branches

  pool_id            = "github-actions-plan"
  provider_id        = "github"
  service_account_id = "terraform-plan"

  service_account_display_name = "Terraform Plan"
  service_account_description  = "READ-ONLY plan identity. Refreshes state, computes diffs, cannot mutate anything. Used by PR-time terraform plan across every stack."
  project_roles                = var.github_actions_plan_roles

  depends_on = [google_project_service.enabled]
}
