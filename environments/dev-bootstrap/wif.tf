###############################################################################
# Workload Identity Federation for GitHub Actions
#
# TWO pools, TWO providers, TWO service accounts — apply vs plan.
#
#   github-actions       (APPLY) — main only,    write-capable SA
#   github-actions-plan  (PLAN)  — PR refs,      read-only SA
#
# A PR-time workflow CANNOT assume the apply SA: the apply pool's
# attribute_condition rejects refs/pull/*/merge at the pool layer,
# before the workflow even gets a token. Defence in depth — even a
# misconfigured workflow YAML can't mint apply credentials from a
# feature branch.
#
# See modules/github-oidc-wif/README.md and ADR-0004 for the trust
# flow diagram and rationale.
###############################################################################

# ── APPLY identity ───────────────────────────────────────────────────────
module "github_wif" {
  source = "../../modules/github-oidc-wif"

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository
  allowed_branches  = var.github_actions_allowed_branches
  # pool_id / provider_id / service_account_id use module defaults
  # (github-actions / github / terraform-actions)

  depends_on = [google_project_service.enabled]
}

# ── PLAN identity (read-only) ────────────────────────────────────────────
module "github_wif_plan" {
  source = "../../modules/github-oidc-wif"

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository
  allowed_branches  = var.github_actions_plan_allowed_branches

  # Distinct pool / provider / SA so the trust surfaces never overlap.
  pool_id            = "github-actions-plan"
  provider_id        = "github"
  service_account_id = "terraform-plan"
  project_roles      = var.github_actions_plan_roles

  depends_on = [google_project_service.enabled]
}
