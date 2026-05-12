# Runbook — Trial Walkthrough

> Stand up the platform end-to-end on a fresh GCP project, verify it works, then tear it down. Designed for a half-day exercise.

This is the path that took the v1.0 → v1.2 work from "code in a repo" to "Argo CD reconciling a tenant app on a private GKE cluster" in one sitting. Three Terraform stacks, applied in order, with a bastion VM as the operator's only entry point into the private cluster.

## Time + cost

| Phase | Duration | Cost so far |
| --- | --- | --- |
| Bootstrap (project + VPC + KMS + bastion) | ~5 min | ~$50/mo run rate |
| Cluster (GKE control plane + node pools) | ~15-20 min | +$300-400/mo run rate |
| Platform (Argo CD) | ~5 min | +$0 (within cluster) |
| Argo CD reconciles platform addons | ~5-10 min | +small |
| **Total to "working platform"** | **~30-45 min** | **~$350-450/mo run rate** |
| Trial cost if torn down within 8 hours | | **~$5-15 total** |

## Prerequisites

- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- ADC set up (`gcloud auth application-default login` — Terraform reads this)
- `terraform` 1.5+ on your laptop
- A GCP billing account with capacity (the bootstrap stack creates a fresh project under it)
- Internet egress to `googleapis.com`, `github.com`, and the public Helm chart repos

## Stage 1 — Bootstrap

Local apply. Creates the project, VPC, KMS, state bucket, bastion.

```bash
cd environments/dev-bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set billing_account to your XXXXXX-XXXXXX-XXXXXX

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Capture the outputs you need for the next stage:

```bash
terraform output -raw cluster_tfvars_snippet > /tmp/cluster.tfvars
terraform output -raw project_id          # used to set ADC quota project
terraform output -raw tfstate_bucket      # used by terraform init below
```

Point ADC's quota project at the new project (avoids a `UserProjectAccountProblem` error in the next stage):

```bash
gcloud auth application-default set-quota-project $(terraform output -raw project_id)
```

## Stage 2 — Cluster

Local apply. Creates the private GKE cluster + node pools + baseline backup plan. The state lives in the GCS bucket from Stage 1.

```bash
cd ../dev
cat /tmp/cluster.tfvars > terraform.tfvars   # produced in Stage 1

terraform init -reconfigure \
  -backend-config="bucket=$(cd ../dev-bootstrap && terraform output -raw tfstate_bucket)"

terraform plan -out=tfplan
terraform apply tfplan
```

This is the long one. GKE regional control plane creation is ~10 minutes; node pools another ~3-5 each. Confirm both pools are RUNNING:

```bash
PROJECT_ID=$(cd ../dev-bootstrap && terraform output -raw project_id)
gcloud container node-pools list --cluster=idp-dev --region=us-central1 --project="$PROJECT_ID"
```

Expected: `bronze` and `silver`, both `RUNNING`.

## Stage 3 — Platform

Run from **inside the bastion VM**. The cluster's control plane is private; your laptop cannot reach it directly.

```bash
# From your laptop:
PROJECT_ID=$(cd environments/dev-bootstrap && terraform output -raw project_id)
gcloud compute ssh bastion \
  --project="$PROJECT_ID" \
  --zone=us-central1-a \
  --tunnel-through-iap
```

Inside the bastion:

```bash
# 1. Auth the operator's identity (OS-Login is pre-provisioned).
gcloud auth login
gcloud auth application-default login

# 2. Install Terraform (bastion's cloud-init handles gcloud + kubectl).
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# 3. Cluster credentials (internal endpoint).
gcloud container clusters get-credentials idp-dev \
  --region=us-central1 \
  --project=<PROJECT_ID-from-stage-1>

# 4. Clone the repo and configure the platform stack.
git clone https://github.com/SriLingala/idp-banking-blueprint.git
cd idp-banking-blueprint/environments/dev-platform

cat > terraform.tfvars <<EOF
project_id   = "<PROJECT_ID-from-stage-1>"
region       = "us-central1"
cluster_name = "idp-dev"
EOF

# 5. Init against the shared state bucket; plan + apply.
terraform init -backend-config="bucket=<PROJECT_ID-from-stage-1>-tfstate"
terraform plan -out=tfplan
terraform apply tfplan
```

## Stage 4 — Bootstrap Argo CD's root-app

Still on the bastion:

```bash
cd ~/idp-banking-blueprint
make argocd-root
```

This applies the platform AppProject + tenant-default AppProject + the root Application. From this point Argo CD owns reconciliation: it discovers everything under `argocd/apps/{platform,tenants}/` and starts pulling them in.

## Stage 5 — Verify

Still on the bastion:

```bash
# Argo CD itself is up.
kubectl -n argocd get pods

# Platform addons reconciled.
kubectl get applications -n argocd
# Expected (after ~5-10 min):
#   root                    Synced  Healthy
#   cert-manager            Synced  Healthy
#   ingress-nginx           Synced  Healthy
#   kube-prometheus-stack   Synced  Healthy
#   loki                    Synced  Healthy
#   grafana                 Synced  Healthy
#   gatekeeper              Synced  Healthy
#   gatekeeper-policies     Synced  Healthy
#   sample-tenant-app       Synced  Healthy

# Gatekeeper constraints active.
kubectl get constraints

# Sample tenant app running in its namespace.
kubectl -n sample get pods

# Try to deploy a non-compliant pod and watch admission deny it.
kubectl -n sample run nope --image=nginx --restart=Never
# Expected: error about K8sRestrictedRegistries or K8sRequireResourceLimits.
```

For the Argo CD UI:

```bash
# Port-forward from the bastion to your laptop via the same IAP tunnel.
kubectl -n argocd port-forward svc/argocd-server 8080:443
# Then on your laptop, open another IAP tunnel session and browse https://localhost:8080
```

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo
```

## Stage 6 — Teardown

The trial isn't cheap if left running. When done, destroy in **reverse order**:

```bash
# 1. From the bastion: destroy the platform stack first (uninstalls Argo CD).
cd ~/idp-banking-blueprint/environments/dev-platform
terraform destroy

# 2. From your laptop: destroy the cluster.
cd environments/dev
terraform destroy

# 3. From your laptop: destroy the bootstrap (VPC, KMS, bastion, state bucket).
cd ../dev-bootstrap
terraform destroy
```

Order matters: tearing down the bootstrap first would orphan resources that depend on the VPC and KMS keys.

**KMS keys cannot be hard-deleted.** They go into a 30-day scheduled-destroy window. To accelerate:

```bash
gcloud kms keys list --location=us-central1 --keyring=idp --project=<PROJECT_ID>
# For each key/version, destroy the version immediately:
gcloud kms keys versions destroy 1 --key=etcd --keyring=idp --location=us-central1 --project=<PROJECT_ID>
```

**Project shutdown:** if you want the project gone entirely after the trial:

```bash
gcloud projects delete <PROJECT_ID>
# Schedules deletion in 30 days. To accelerate: gcloud projects undelete won't work after restoration window.
```

## Common gotchas

| Symptom | Diagnosis | Fix |
| --- | --- | --- |
| `terraform init` fails with `UserProjectAccountProblem` on the cluster stack | ADC quota project points at a different project | `gcloud auth application-default set-quota-project <project_id>` |
| `Error creating NodePool: Confidential nodes feature is not supported on machine type ...` | Pool uses an Intel machine type | Switch to `n2d-*` or set `enable_confidential_nodes = false` |
| `maintenance policy would go longer than 32d without 48h maintenance availability` | Window is too narrow for GKE's 48h-per-32-day floor | Widen the window (the default in v1.0+ is 03:00-11:00 UTC weekends, 16h/week) |
| `Service account service-...@gcp-sa-gkebackup.iam.gserviceaccount.com does not exist` | gkebackup service agent not provisioned yet | Use `google_project_service_identity` (bootstrap stack handles this in v1.1.1+) |
| `kubectl` times out from bastion | Cluster MAN doesn't include bastion's IP | The bootstrap stack adds the bastion's internal IP to MAN automatically; check `gcloud container clusters describe idp-dev` |
| Argo CD Application stuck `OutOfSync` after merge | sync interval not elapsed yet | Wait 3 min, or `argocd app sync <name>` |
