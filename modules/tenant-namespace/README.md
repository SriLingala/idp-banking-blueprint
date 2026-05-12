# modules/tenant-namespace

One namespace per tenant on the shared regional GKE cluster — the smallest
unit of isolation under [ADR-0001](../../docs/adr/0001-multi-tenant-by-namespace.md).

## What you get

- Namespace labelled for Pod Security Standards `restricted` (enforce + audit + warn)
- `ResourceQuota` — hard cap on CPU / memory / pods / services / PVCs
- `LimitRange` — every container starts with sane defaults; nothing runs unbounded
- `NetworkPolicy` default-deny ingress and egress, with opt-in DNS egress
- `ServiceAccount` annotated for Workload Identity, with IAM binding to the
  supplied GCP service account

## Usage

```hcl
module "tenant_acme" {
  source = "../../modules/tenant-namespace"

  tenant     = "acme"
  tier       = "silver"
  project_id = var.project_id

  gcp_service_account_email = google_service_account.tenant_acme.email

  extra_labels = {
    "cost-centre"          = "1234"
    "data-classification"  = "internal"
    "sox"                  = "in-scope"
  }
}
```

## Inputs

See `variables.tf`. Key inputs:

| Name | Required | Notes |
| --- | --- | --- |
| `tenant` | yes | DNS-1123 label; becomes the namespace name |
| `tier` | no | `bronze` / `silver` / `gold`; default `silver` |
| `project_id` | yes | GCP project hosting the cluster |
| `gcp_service_account_email` | no | Pass `null` to skip the Workload Identity binding |
| `resource_quota` | no | Override per tenant when negotiated |
| `default_container_limits` | no | LimitRange defaults |
| `allow_dns_egress` | no | Default `true` |
| `extra_labels` | no | cost-centre, data-classification, etc. |

## Outputs

| Name | Notes |
| --- | --- |
| `namespace` | The created namespace name |
| `service_account_name` | KSA name (default `tenant-runtime`) |
| `service_account_full` | `<ns>/<ksa>` reference |
| `tier` | Echoes the input |

## What this module does NOT do

- It does **not** create the GCP service account. Platform engineering
  provisions and scopes those in a separate Terraform stack with explicit
  IAM review.
- It does **not** create RBAC bindings for tenant humans. That lives in
  the tenant onboarding runbook (v0.3).
- It does **not** create the Argo CD `AppProject`. That manifest lives
  under `argocd/projects/`.
