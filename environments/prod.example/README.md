# environments/prod.example

Production-shaped example for the GKE cluster stack.

This directory is intentionally named `prod.example`, not `prod`, because a
real banking production stack should be created only after the organisation
has chosen its project layout, state bucket, KMS ownership, Binary
Authorization policy, attestors, tenant tiers, and change controls.

Use this as the production baseline to copy into a real `environments/prod/`
stack once those decisions are made.

## What differs from dev

| Area | Dev | Production example |
| --- | --- | --- |
| Cluster name | `idp-dev` | `idp-prod` |
| Release channel | `REGULAR` | `STABLE` |
| Backup for GKE | optional | required |
| Deletion protection | default on | explicitly on |
| Node pools | bronze, silver | silver, gold |
| Spot nodes | allowed for bronze | not used |
| Labels | dev defaults | SOX in-scope defaults |
| Authorized networks | bastion CIDR | bastion / controlled admin CIDRs only |

## Required external dependencies

- Bootstrap stack has created the project, VPC, subnet, NAT, KMS keys, and state bucket.
- KMS key rotation and access policy have been reviewed by security.
- Binary Authorization policy and attestors exist in the platform IAM/security stack.
- Branch protection requires CODEOWNERS approval before production changes merge.
- Terraform Cloud / Enterprise policy set points at `policies/sentinel`.

## Apply model

Production applies should run from the bastion or another controlled runner
that can reach the private control plane and write to the production state
bucket.

```bash
cd environments/prod.example
cp terraform.tfvars.example terraform.tfvars
# Edit every placeholder. Do not commit terraform.tfvars.

terraform init -backend-config="bucket=<prod-state-bucket>"
terraform plan -out=tfplan
terraform apply tfplan
```

## Promotion expectation

Promote by pull request, not by copying a local plan:

1. Validate the change in dev.
2. Capture Argo CD, Terraform, and policy evidence.
3. Open a production PR with the dev evidence linked.
4. Require platform and security approval.
5. Apply from the controlled production runner.

