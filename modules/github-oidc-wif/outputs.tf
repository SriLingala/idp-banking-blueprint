output "pool_id" {
  description = "ID of the Workload Identity Pool. Null when create_pool = false."
  value       = var.create_pool ? google_iam_workload_identity_pool.this[0].workload_identity_pool_id : null
}

output "pool_resource_name" {
  description = "Fully-qualified pool resource name — pass this to subsequent module calls running with create_pool = false so they bind into the same pool."
  value       = local.pool_name
}

output "provider_resource_name" {
  description = "Fully-qualified provider resource — paste this into the GitHub Actions `google-github-actions/auth` step as `workload_identity_provider`. Null when create_pool = false (the value lives on the pool-creating call's output)."
  value       = var.create_pool ? google_iam_workload_identity_pool_provider.github[0].name : null
}

output "service_account_email" {
  description = "Email of the service account this call created. Paste into `service_account` on the workflow's `auth` step."
  value       = google_service_account.sa.email
}

output "service_account_id" {
  description = "Account ID portion of the service account (before the @)."
  value       = google_service_account.sa.account_id
}

output "github_repository" {
  description = "Owner/repo string the binding is scoped to. Surfaced for documentation."
  value       = "${var.github_owner}/${var.github_repository}"
}

locals {
  _provider_for_snippet = try(google_iam_workload_identity_pool_provider.github[0].name, "")
  _snippet              = <<-EOT

    # ─── paste into your terraform workflow's auth step ───
    permissions:
      contents: read
      id-token: write       # required for OIDC token minting
      pull-requests: write  # if the workflow comments plans on PRs

    steps:
      - uses: actions/checkout@v4

      - id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${local._provider_for_snippet}
          service_account: ${google_service_account.sa.email}
          token_format: access_token
          access_token_lifetime: 1200s

      - uses: google-github-actions/setup-gcloud@v2
        with:
          install_components: gke-gcloud-auth-plugin
  EOT
}

output "workflow_auth_snippet" {
  description = "Copy-paste YAML for the GitHub Actions auth step. Returns the snippet only when this module call created the pool (var.create_pool = true) — identity-only calls return an empty string because the provider belongs to the pool-creating sibling call."
  value       = var.create_pool ? local._snippet : ""
}
