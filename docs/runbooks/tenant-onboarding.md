# Runbook — Tenant Onboarding

> Onboard a new tenant to the platform. Estimated time: 30 minutes of work,
> spread across two PRs and one ticket.

## When to use this

A new engineering team needs a namespace on the shared cluster with isolation guarantees, a default deployment story (Argo CD), and access scoped to their identity provider group.

## When NOT to use this

- Tenant needs cluster-level isolation (specific compliance regimes, kernel-level dependencies, multi-cluster failover). Route to the **Dedicated Cluster Exception** runbook.
- Tenant wants to onboard via Terraform from their own repo with their own state. Route to the **Federated Terraform Onboarding** runbook (v1.0).

## Pre-requisites

- [ ] Tenant has signed the Platform Service Agreement (cost-centre code, SOX scope, on-call expectations).
- [ ] Tenant identity-provider group(s) exist: `tenant:<name>:developers`, `tenant:<name>:owners`.
- [ ] Cost-centre code is registered in the finance ledger.

## Steps

### 1. Open the platform-infra PR (Terraform)

Add a tenant module call in `environments/dev-platform/tenants.tf` (or the platform stack of your choice):

```hcl
module "tenant_<name>" {
  source = "../../modules/tenant-namespace"

  tenant     = "<name>"
  tier       = "silver"          # bronze | silver | gold; see SLA matrix
  project_id = var.project_id

  gcp_service_account_email = google_service_account.tenant_<name>.email

  extra_labels = {
    "cost-centre"         = "<cost-centre-code>"
    "data-classification" = "internal"     # or 'confidential' for PII
    "sox"                 = "in-scope"     # or 'out-of-scope'
  }
}
```

Also add the tenant GSA above the module call:

```hcl
resource "google_service_account" "tenant_<name>" {
  project      = var.project_id
  account_id   = "tenant-<name>-runtime"
  display_name = "Tenant <name> runtime SA"
}
```

> **Review checklist for the PR reviewer:**
> - [ ] Tenant name is DNS-1123 compliant (lowercase, ≤63 chars)
> - [ ] Tier matches the signed SLA
> - [ ] Cost-centre is registered (cross-check against finance ledger)
> - [ ] `sox` label is correct (this drives quarterly evidence collection)
> - [ ] Sentinel `enforce-labels` passes the plan

### 2. Open the argocd PR

Two files under `argocd/`:

**`argocd/projects/tenant-<name>.yaml`** — copy `argocd/projects/tenant-default.yaml`, find/replace `sample` with `<name>`, and update:

- `sourceRepos[]` to the tenant's repo(s)
- `groups:` under each role to the tenant's IDP groups
- `syncWindows` if the tenant has a non-standard change-freeze (rare)

**`argocd/apps/tenants/<name>.yaml`** — Application that points at the tenant's source repo and path. The chart at `helm/sample-tenant-app/` is the reference shape; in production tenants ship their own chart and Application.

### 3. Land both PRs

Both PRs require:

- [ ] One platform-engineering reviewer
- [ ] One security reviewer (auto-assigned via CODEOWNERS when the change touches `policies/`, `argocd/projects/`, or any IAM resource)
- [ ] Green CI (terraform validate + tflint + helm lint + yaml lint)

After both merge, Argo CD discovers the new AppProject within the sync interval (default 3 min) and reconciles the tenant Application.

### 4. Confirm the tenant can deploy

Run these as the tenant lead (or coordinate via the tenant's onboarding ticket):

```bash
# Confirm namespace exists with correct labels
kubectl get ns <name> -o jsonpath='{.metadata.labels}' | jq

# Confirm KSA + WI annotation
kubectl -n <name> get sa tenant-runtime -o yaml

# Confirm default-deny NetworkPolicy
kubectl -n <name> get netpol

# Trigger a sample deploy (Argo CD UI or CLI)
argocd app sync <name>-sample
```

Expected: deploy succeeds; pods reach Ready.

### 5. Hand off

Send the tenant lead:

- Argo CD UI URL + their IDP group binding
- The CODEOWNERS entry covering their app repo (for review automation)
- A link to **Runbook — Tenant Self-Service** (v1.0)
- A link to the incident process and on-call rotation expectations

Close the onboarding ticket with a link to the two merged PRs.

## Common failures

| Symptom | Diagnosis | Fix |
| --- | --- | --- |
| `terraform apply` fails on `google_service_account_iam_member` | The GSA doesn't exist yet | Apply step 1's `google_service_account` resource before the module call (Terraform handles dependency, but if you split the PR this can bite) |
| `kubectl get ns <name>` returns NotFound after merge | Argo CD's platform stack hasn't applied yet | `argocd app sync platform-tenants` — or wait for the next reconciliation |
| Pods scheduled but Pending | nodeSelector `tier=<tier>` matches no node pool | Either change the tier on the namespace annotation, or add a node pool for the new tier to `modules/gke-hardened` |
| Tenant pod denied at admission with `K8sRequireResourceLimits` | Pod manifest missing `resources.limits` | Tenant fixes their manifest; this is working as intended |
| `K8sPinWIServiceAccount` denies SA creation | KSA annotation references a GSA not in the namespace's allow-list | Add the GSA to the namespace `platform.idp/allowed-gsa` annotation (in `modules/tenant-namespace` call) |

## Decommissioning

When a tenant leaves the platform:

1. Tenant sets all their Argo CD Applications to `prune: true` and removes their app manifests in a PR. Argo CD reaps the workloads.
2. Wait one full backup retention window (35 days default) before removing the namespace, so restore is possible.
3. Open a "tenant decommission" PR removing the tenant module call and the AppProject. Reviewer confirms with the tenant lead that nothing in the namespace is salvage.
4. Land the PR. The namespace, KSA, GSA, and AppProject are all deleted. Backup objects remain for the lock window.
