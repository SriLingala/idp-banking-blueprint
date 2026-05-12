# environments/dev-tenants

Tenant compositions for the dev cluster. **One module call per tenant.**

Onboarding a new tenant is:
1. Add a `module "tenant_<name>"` block here (this file)
2. Add a matching `Application` manifest under `argocd/apps/tenants/`
3. PR both, merge, apply this stack from the bastion

After apply, Argo CD reconciles the tenant's chart into the new namespace within ~3 minutes (default sync interval).

## What this stack creates per tenant

Via [`modules/tenant-namespace`](../../modules/tenant-namespace):

- Namespace with Pod Security Standards `restricted` labels
- `ResourceQuota` — hard cap on CPU / memory / pods / services / PVCs
- `LimitRange` — every container starts with sane defaults
- `NetworkPolicy` default-deny ingress and egress + opt-in DNS egress
- `ServiceAccount` (`tenant-runtime`) optionally annotated for Workload Identity
- `google_service_account_iam_member` binding if a GSA is supplied

## Where this runs

The GKE control plane is private. Apply from the **bastion** (provisioned by `environments/dev-bootstrap`), reachable via gcloud IAP tunnel.

## Usage (from the bastion)

```bash
gcloud container clusters get-credentials idp-dev \
  --region=us-central1 \
  --project=<PROJECT_ID>

cd ~/idp-banking-blueprint/environments/dev-tenants
cp terraform.tfvars.example terraform.tfvars
# Edit: set project_id

terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
terraform plan -out=tfplan
terraform apply tfplan
```

## Trial trade-offs

The sample tenant in this stack omits Workload Identity (`gcp_service_account_email = null`). In prod each tenant has a dedicated GSA provisioned in a separate IAM Terraform stack with reviewed scopes; this stack only consumes the GSA email.

## Decommissioning a tenant

See [`docs/runbooks/tenant-onboarding.md`](../../docs/runbooks/tenant-onboarding.md) — final section.
