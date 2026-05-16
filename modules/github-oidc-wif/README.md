# modules/github-oidc-wif

Workload Identity Federation for GitHub Actions. **No static GCP keys ever leave the cluster's project.**

This is the identity primitive every Terraform plan + apply workflow assumes. One module call creates:

- A **Workload Identity Pool** in the project (optional — see [Two modes](#two-modes) below).
- An **OIDC provider** inside the pool, configured for `token.actions.githubusercontent.com` (optional, paired with pool creation).
- A constrained `attribute_condition` that lets only **your** repo's **allow-listed branches** mint a federated token.
- A **service account** with whatever project-level roles Terraform actually needs for *this* identity's stack.
- An **IAM binding** that lets the federated principal impersonate the SA — and nothing else.

See [ADR-0004](../../docs/adr/0004-workload-identity-federation-for-cicd.md) for the WIF trade-offs and [ADR-0006](../../docs/adr/0006-per-stack-terraform-identities.md) for why we split the apply SA per stack.

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
                                             │      impersonates the     │
                                             │      stack's SA           │
                                             │      → access_token       │
                                             └────────────┬──────────────┘
                                                          │
                                                          ▼
                                             ┌───────────────────────────┐
                                             │  (4) Terraform calls GCP  │
                                             │      as terraform-<stack> │
                                             └───────────────────────────┘
```

Cloud Audit Logs record every API call the SA makes; the `attribute.actor` + `attribute.run_id` claims propagate so an auditor can join an SA call back to a specific workflow run AND tell which stack acted by the SA name.

## Two modes

The module supports two modes via `var.create_pool`:

| Mode               | When to use                                          | What it creates                          |
|--------------------|------------------------------------------------------|------------------------------------------|
| **Pool-creating** (`create_pool = true`, default) | First call per pool — e.g. the apply pool's bootstrap SA or the plan pool's plan SA | Pool + provider + SA + IAM binding + roles |
| **Identity-only** (`create_pool = false`) | Subsequent SAs sharing an existing pool — e.g. the cluster / platform / tenants apply SAs | SA + IAM binding + roles only            |

In identity-only mode, pass `pool_resource_name` from the pool-creating call's output.

## Usage

`environments/dev-bootstrap/wif.tf` is the canonical caller. It calls this module five times — once to create the apply pool plus the `terraform-bootstrap` SA, three identity-only calls to add `terraform-cluster` / `terraform-platform` / `terraform-tenants`, and once more (pool-creating) for the read-only plan pool's `terraform-plan` SA.

Minimal example:

```hcl
# Pool-creating: apply pool + bootstrap SA
module "github_wif" {
  source = "../../modules/github-oidc-wif"

  project_id        = google_project.this.project_id
  github_owner      = "SriLingala"
  github_repository = "idp-banking-blueprint"
  allowed_branches  = ["refs/heads/main"]

  service_account_id           = "terraform-bootstrap"
  service_account_display_name = "Terraform Bootstrap"
  project_roles                = var.github_actions_bootstrap_roles
}

# Identity-only: cluster SA in the same pool
module "github_wif_cluster" {
  source = "../../modules/github-oidc-wif"

  create_pool        = false
  pool_resource_name = module.github_wif.pool_resource_name

  project_id        = google_project.this.project_id
  github_owner      = "SriLingala"
  github_repository = "idp-banking-blueprint"

  service_account_id = "terraform-cluster"
  project_roles      = var.github_actions_cluster_roles
}
```

## Inputs

| Name | Required | Notes |
| --- | --- | --- |
| `project_id` | yes | GCP project hosting the pool + SAs |
| `create_pool` | no | Default `true`. Set `false` for identity-only calls |
| `pool_resource_name` | when `create_pool = false` | Full pool resource path from the pool-creating call's `pool_resource_name` output |
| `pool_id` | no | Default `github-actions`. Used only when `create_pool = true`. Immutable post-creation |
| `provider_id` | no | Default `github` |
| `github_owner` | yes | User or org name |
| `github_repository` | yes | Repo name (no owner prefix) |
| `allowed_branches` | no | Default `["refs/heads/main"]`. Used only when `create_pool = true` (pool-level attribute_condition) |
| `service_account_id` | no | Default `terraform-actions`. Per-stack callers pass their stack's SA id |
| `service_account_display_name` | no | Human-readable display name |
| `service_account_description` | no | Recorded against the SA; surface what the SA can change here |
| `project_roles` | no | Default `[]` — every caller should pass a minimum role list tailored to its stack |

## Outputs

| Name | Notes |
| --- | --- |
| `pool_id` | `null` when `create_pool = false` |
| `pool_resource_name` | Always set — pass this to identity-only callers |
| `provider_resource_name` | `null` when `create_pool = false` (the value lives on the pool-creating call) |
| `service_account_email` | Paste into `service_account` on the GitHub Action |
| `service_account_id` | Account ID portion (before the `@`) |
| `github_repository` | `<owner>/<repo>` |
| `workflow_auth_snippet` | Copy-pasteable YAML; empty string when `create_pool = false` |

## What this module does NOT do

- It does **not** rotate anything — WIF tokens are short-lived by design (default 20 minutes via `access_token_lifetime`), and the SAs never have keys to rotate.
- It does **not** allow forked PRs. By design — `attribute_condition` rejects them at the pool layer.
- It does **not** restrict which workflow path within the repo can impersonate the SA. Tightening to `principal://…job_workflow_ref:…` is the next-step hardening; tracked in ADR-0006 under "Things we deliberately did NOT do".
