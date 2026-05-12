# environments/dev-platform

Post-cluster Terraform stack. Installs the Argo CD control plane into the GKE cluster created by `environments/dev`. After Argo CD is up, the operator runs `make argocd-root` once to apply the platform AppProject + root-app — Argo CD then owns every other in-cluster addon and tenant app via the app-of-apps pattern under `argocd/`.

This is **the only Helm release Terraform manages**. See [ADR-0002](../../docs/adr/0002-argocd-app-of-apps.md) for why.

## Where this runs

The GKE control plane is private (`enable_private_endpoint = true`). Apply this stack from a host **inside the VPC** — typically the bastion VM created by `environments/dev-bootstrap`, reachable via gcloud's IAP TCP tunnel.

## Prerequisites

- `environments/dev-bootstrap` has been applied — project, VPC, KMS, state bucket, bastion exist
- `environments/dev` has been applied — the GKE cluster `idp-dev` exists and is RUNNING
- The bastion has `gcloud`, `kubectl`, and Terraform installed (the bootstrap's cloud-init handles gcloud + kubectl; install Terraform once with `apt-get install terraform` or via tfenv)
- The operator is SSH'd into the bastion (`gcloud compute ssh bastion --tunnel-through-iap`)

## Usage (from the bastion)

```bash
# 1. Authenticate gcloud + ADC under the operator's identity (OS-Login provisioned).
gcloud auth login
gcloud auth application-default login

# 2. Get cluster credentials (uses the internal endpoint).
gcloud container clusters get-credentials idp-dev \
  --region us-central1 \
  --project <project-id-from-bootstrap>

# 3. Clone the repo and configure the stack.
git clone https://github.com/SriLingala/idp-banking-blueprint.git
cd idp-banking-blueprint/environments/dev-platform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set project_id

# 4. Init against the shared GCS state bucket (same bucket as the cluster stack).
terraform init \
  -backend-config="bucket=<project-id-from-bootstrap>-tfstate"

# 5. Plan + apply.
terraform plan -out=tfplan
terraform apply tfplan
```

After the apply finishes, follow the `next_steps` output for port-forwarding to Argo CD and applying the root app.

## What this stack does NOT do

- It does not install cert-manager, ingress-nginx, observability, or Gatekeeper. **Argo CD does** — once you apply `argocd/apps/root.yaml`, Argo CD discovers everything under `argocd/apps/platform/` and reconciles it.
- It does not configure tenant namespaces. Each tenant gets its own Terraform stack (or a tenant module call in a multi-tenant stack); see the [tenant onboarding runbook](../../docs/runbooks/tenant-onboarding.md).

## Inputs

| Name | Default | Notes |
| --- | --- | --- |
| `project_id` | (required) | Output `project_id` from environments/dev-bootstrap |
| `region` | `us-central1` | Must match the cluster's region |
| `cluster_name` | `idp-dev` | Match the name set in environments/dev/main.tf |
| `argocd_chart_version` | `7.7.7` | Pin explicitly — bumps go through review |
| `argocd_ha` | `true` | Off saves a few resources on a trial cluster |

## Outputs

| Name | Notes |
| --- | --- |
| `argocd_namespace` | Where Argo CD landed (default `argocd`) |
| `argocd_chart_version` | Echo of the installed chart version |
| `next_steps` | A copy-pasteable recap — UI port-forward, admin password, root-app bootstrap |
