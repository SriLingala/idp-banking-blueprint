# Evidence capture

This folder is for proof from real trial or production-like runs. Do not
invent evidence. If a deployment has not been run, leave the relevant entry
empty and say so in the PR.

## Evidence checklist

Capture these artifacts after a sandbox apply:

- Terraform plan summary for `environments/dev-bootstrap`
- Terraform plan summary for `environments/dev`
- Terraform plan summary for `environments/dev-platform`
- `terraform validate` and `tflint` outputs
- `make policy-test` output
- Argo CD root app screenshot or `argocd app get root`
- `kubectl get applications -n argocd`
- `kubectl get constraints`
- sample Gatekeeper denial for a non-compliant pod
- tenant namespace labels, quotas, LimitRanges, and NetworkPolicies
- Backup for GKE backup list
- DR drill result, when available

## Suggested file naming

```text
YYYY-MM-DD-dev-terraform-validate.txt
YYYY-MM-DD-dev-argocd-root.txt
YYYY-MM-DD-dev-gatekeeper-denial.txt
YYYY-MM-DD-dev-backup-list.txt
YYYY-MM-DD-dr-drill-payments.md
```

## Redaction rules

- Redact project numbers, private CIDRs if required, user emails, and tokens.
- Do not commit kubeconfigs, Terraform state, service-account keys, or screenshots containing secrets.
- Prefer command output over screenshots when possible.

