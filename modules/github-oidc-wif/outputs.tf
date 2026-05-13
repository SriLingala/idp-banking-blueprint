output "pool_id" {
  description = "ID of the Workload Identity Pool. Echoed for downstream config."
  value       = google_iam_workload_identity_pool.this.workload_identity_pool_id
}

output "provider_resource_name" {
  description = "Fully-qualified provider resource — paste this into the GitHub Actions `google-github-actions/auth` step as `workload_identity_provider`."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "Email of the terraform-actions SA. Paste this into `service_account` on the `auth` step."
  value       = google_service_account.terraform_actions.email
}

output "github_repository" {
  description = "Owner/repo string the pool is bound to. Surfaced for documentation."
  value       = "${var.github_owner}/${var.github_repository}"
}

output "workflow_auth_snippet" {
  description = "Copy-paste YAML for the GitHub Actions auth step. Drops directly into terraform-plan.yml / terraform-apply.yml."
  value       = <<-EOT

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
          workload_identity_provider: ${google_iam_workload_identity_pool_provider.github.name}
          service_account: ${google_service_account.terraform_actions.email}
          # Optional: pin to a specific token lifetime for tighter audit
          # token_format: access_token
          # access_token_lifetime: 1800s

      - uses: google-github-actions/setup-gcloud@v2
        with:
          install_components: gke-gcloud-auth-plugin
  EOT
}
