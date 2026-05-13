###############################################################################
# modules/github-oidc-wif
#
# Workload Identity Federation for GitHub Actions.
#
# This module is the *security perimeter* of the platform's CI/CD: it lets
# a GitHub Actions workflow mint a short-lived GCP access token without any
# static service-account key existing in GitHub Secrets or anywhere else.
#
# How the trust flows:
#
#   1. A workflow runs on a runner. Actions hands the runner an OIDC token
#      signed by token.actions.githubusercontent.com.
#   2. The runner exchanges that OIDC token at sts.googleapis.com for a
#      federated identity token via *this* pool's provider.
#   3. That federated identity is allowed to call iam.serviceAccounts.
#      getAccessToken on the `terraform-actions` SA — but ONLY if the OIDC
#      claims match the attribute_condition encoded here (owner + repo +
#      ref allowlist).
#   4. The SA's access token is what Terraform uses to talk to GCP.
#
# What that means in practice:
#   - No JSON keys in GitHub Secrets. No keys to rotate.
#   - A workflow on a forked PR or an arbitrary branch cannot impersonate
#     the SA — the attribute_condition rejects it.
#   - Every Terraform API call carries the SA's identity, and the audit
#     log can be joined back to the workflow run via the OIDC token's
#     `actor` / `run_id` claims (kept as attribute_mapping below).
#
# Reference:
#   https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
###############################################################################

locals {
  # The principalSet for the GitHub repo. Members shaped like
  # principalSet://iam.googleapis.com/projects/<n>/locations/global/workloadIdentityPools/<pool>/attribute.repository/<owner>/<repo>
  # are how we constrain WHICH repo's workflows are allowed to impersonate
  # this SA — the SA itself never holds keys.
  pool_resource_name = google_iam_workload_identity_pool.this.name
}

###############################################################################
# Pool + Provider
###############################################################################

resource "google_iam_workload_identity_pool" "this" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Federated identity pool used by Terraform delivery workflows in github.com/${var.github_owner}/${var.github_repository}."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.this.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "github.com"
  description                        = "OIDC provider for GitHub Actions tokens. Constrained to the configured repo and branch allowlist."

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # attribute_mapping records claims from the OIDC token onto the federated
  # identity so they're visible in Cloud Audit Logs (alongside the SA call)
  # and can be joined back to the workflow run.
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.workflow"         = "assertion.workflow"
    "attribute.run_id"           = "assertion.run_id"
  }

  # attribute_condition is the *real* gate. The pool will refuse to mint
  # a federated token unless ALL of these are true for the incoming OIDC
  # claims.  This means:
  #   - The token came from the right GitHub org
  #   - It came from this exact repo (defence in depth — owner+repo is
  #     stronger than owner alone)
  #   - It came from a ref on the allowlist (default: refs/heads/main)
  attribute_condition = join(" && ", [
    "assertion.repository_owner == '${var.github_owner}'",
    "assertion.repository == '${var.github_owner}/${var.github_repository}'",
    "[${join(",", [for r in var.allowed_branches : "'${r}'"])}].exists(b, assertion.ref == b)",
  ])
}

###############################################################################
# Service account that the federated identity impersonates
###############################################################################

resource "google_service_account" "terraform_actions" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Terraform Actions"
  description  = "Identity for Terraform plan + apply workflows in GitHub Actions. Impersonated via WIF; never has a static key."
}

# The federated principal is allowed to impersonate the SA — and ONLY
# this principal, scoped to repo + ref by the attribute_condition above.
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.terraform_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.pool_resource_name}/attribute.repository/${var.github_owner}/${var.github_repository}"
}

###############################################################################
# Project-level roles the SA needs to do its job
###############################################################################

resource "google_project_iam_member" "terraform_actions_roles" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_actions.email}"
}
