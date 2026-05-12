# environments/dev-bootstrap

Pre-cluster Terraform stack that stands up everything `environments/dev` assumes already exists:

- A GCP project (auto-named `idp-bank-trial-<random-suffix>`) with billing linked
- The APIs the cluster + Backup for GKE + Binary Authorization need
- A VPC + subnet with secondary ranges for Pods and Services
- Cloud Router + Cloud NAT so private nodes can egress
- Three CMEK keys in a single KeyRing: `etcd`, `nodes`, `backup`
- IAM bindings (GKE service agent, Compute service agent, GKE Backup service agent → encrypt/decrypt)
- A GCS bucket (`<project>-tfstate`) for the downstream stacks' state
- A bastion VM reachable via IAP tunnel (no public IP), pre-authorised to your gcloud user
- Firewall rules: IAP → bastion on 22; bastion → control-plane CIDR on 443

Runs on **local state** by design — this stack creates the bucket that
holds everyone else's state, so it cannot also live in it.

## Usage

```bash
cd environments/dev-bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set billing_account to your account ID

terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Copy the cluster_tfvars_snippet output into environments/dev/terraform.tfvars
terraform output -raw cluster_tfvars_snippet > /tmp/cluster.tfvars
cat /tmp/cluster.tfvars
```

## Cost note

The stack itself is cheap (~$50/mo):

| Resource | Approx /mo |
| --- | --- |
| Bastion VM (e2-small) | $13 |
| Cloud NAT (gateway + egress estimate) | $35 |
| KMS keys (3 × $0.06) | $0.18 |
| GCS state bucket | < $1 |
| VPC, subnet, firewall rules | $0 |

The cluster itself (provisioned by the next stack, `environments/dev`) adds substantially more — a regional control plane is $72/mo and the node pools dominate.

## SSH into the bastion

```bash
gcloud compute ssh bastion \
  --project=$(terraform output -raw project_id) \
  --zone=$(terraform output -raw bastion_zone) \
  --tunnel-through-iap
```

First connection takes ~30s while OS-Login provisions your user.

## Teardown

```bash
terraform destroy
```

Note: KMS keys can't be hard-deleted, only disabled then scheduled for destroy (default 30-day window). Empty the destruction list with `gcloud kms keys versions destroy` if you want it gone immediately.
