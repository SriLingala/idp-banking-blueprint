# modules/github-oidc-wif

Workload Identity Federation for GitHub Actions. **No static GCP keys ever leave the cluster's project.**

This is the identity that every Terraform plan + apply workflow assumes. The module creates:

- A **Workload Identity Pool** in the project.
- An **OIDC provider** inside the pool, configured for `token.actions.githubusercontent.com`.
- A constrained `attribute_condition` that lets only **your** repo's **allow-listed branches** mint a federated token.
- A `terraform-actions` **service account** with the project-level roles Terraform needs.
- An **IAM binding** that lets the federated principal impersonate the SA — and nothing else.

See [ADR-0004](../../docs/adr/0004-workload-identity-federation-for-cicd.md) for the trade-offs.

## How the trust flows at runtime

```
┌───────────────────────────┐                ┌───────────────────────────┐
│  GitHub Actions runner    │                │  iam.googleapis.com       │
│                           │                │                           │
│  (1) OIDC token from      │  exchange ───▶│  (2) WIF pool checks      │
│      token.actions...     │                │      attribute_condition  │
│                           │                │      → mints federated ID │
└───────────────────────────┘                └────────────┬──────────────┘
                                                          │
                                                          ▼
                                             ┌───────────────────────────┐
                                             │  (3) federated ID         │
                                             │      impersonates         │
                                             │      terraform-actions SA │
                                             │      → access_token       │
                                             └────────────┬──────────────┘
                                                          │
                                                          ▼
                                             ┌───────────────────────────┐
                                             │  (4) Terraform calls GCP  │
                                             │      as terraform-actions │
                                             └───────────────────────────┘
```

Cloud Audit Logs record every API call the SA makes; the `attribute.actor` + `attribute.run_id` claims propagate so an auditor can join an SA call back to a specific workflow run.

## Usage

Called from `environments/dev-bootstrap` (the only place that should create the WIF — the rest of the platform consumes its outputs):

```hcl
module "github_wif" {
  source = "../../modules/github-oidc-wif"

  project_id        = google_project.this.project_id
  github_owner      = "SriLingala"
  github_repository = "idp-banking-blueprint"

  # Default: only main can apply. Feature branches plan via separate
  # read-only credentials (added in a follow-up).
  allowed_branches = ["refs/heads/main"]
}
```

## Inputs

| Name | Required | Notes |
| --- | --- | --- |
| `project_id` | yes | GCP project hosting the pool. Usually the cluster's project — keeps trust boundary tight |
| `pool_id` | no | Default `github-actions`. Immutable post-creation |
| `provider_id` | no | Default `github`. The OIDC provider's name inside the pool |
| `github_owner` | yes | User or org name |
| `github_repository` | yes | Repo name (no owner prefix) |
| `allowed_branches` | no | Default `["refs/heads/main"]`. Refs allowed to assume the SA |
| `service_account_id` | no | Default `terraform-actions` |
| `project_roles` | no | Default: minimum surface for the bootstrap → cluster → platform → tenants chain |
| `labels` | no | |

## Outputs

| Name | Notes |
| --- | --- |
| `pool_id` | Echo |
| `provider_resource_name` | Paste into `workload_identity_provider` on the GitHub Action |
| `service_account_email` | Paste into `service_account` on the GitHub Action |
| `github_repository` | `<owner>/<repo>` |
| `workflow_auth_snippet` | A copy-pasteable YAML chunk for `terraform-plan.yml` / `terraform-apply.yml` |

## What this module does NOT do

- It does **not** narrow per-stack roles. The default `project_roles` gives the SA enough to apply every stack from `dev-bootstrap` to `dev-tenants`. For prod, **split into per-stack SAs** (e.g. `terraform-bootstrap`, `terraform-cluster`, `terraform-platform`) with the minimum role surface each one actually needs.
- It does **not** rotate anything — WIF tokens are short-lived by design (default 1h), and the SA never has a key to rotate.
- It does **not** allow forked PRs. By design — `attribute_condition` rejects them. Forked PR workflows would need a separate read-only pool with `pull_request` context allowed.
