###############################################################################
# Workload Identity Federation for GitHub Actions
#
# Creates the pool, OIDC provider, and terraform-actions SA the delivery
# workflows assume at runtime. No static GCP keys live anywhere.
#
# See modules/github-oidc-wif/README.md and ADR-0004 for the security
# rationale and the trust flow diagram.
###############################################################################

module "github_wif" {
  source = "../../modules/github-oidc-wif"

  project_id        = google_project.this.project_id
  github_owner      = var.github_owner
  github_repository = var.github_repository
  allowed_branches  = var.github_actions_allowed_branches

  depends_on = [google_project_service.enabled]
}
