# policies/

Defence-in-depth, expressed as two policy layers (see [ADR-0003](../docs/adr/0003-sentinel-opa-defence-in-depth.md)):

| Layer | When it runs | Where it lives | What it protects against |
| --- | --- | --- | --- |
| **Sentinel** | Terraform plan time, before apply | `policies/sentinel/` | Misconfigured infrastructure landing in cloud |
| **OPA Gatekeeper** | Kubernetes admission, every API write | `policies/opa/` | Misconfigured workloads landing in the cluster |

Both layers are necessary because they catch different classes of problem:

- Sentinel cannot see a `kubectl apply` that bypasses Terraform.
- Gatekeeper cannot see a GCP IAM binding that grants `roles/owner` to a tenant SA.

## Sentinel policies

| Policy | Enforcement | What it checks |
| --- | --- | --- |
| `enforce-region.sentinel` | hard-mandatory | All resources are in `europe-west2` or another approved region |
| `enforce-cmek.sentinel` | hard-mandatory | Every GKE cluster has `database_encryption` set and a `boot_disk_kms_key` |
| `enforce-private-cluster.sentinel` | hard-mandatory | `enable_private_nodes` and `enable_private_endpoint` are true |
| `enforce-master-authorized-networks.sentinel` | hard-mandatory | No `0.0.0.0/0` in `master_authorized_networks_config` |
| `enforce-labels.sentinel` | soft-mandatory | Every cluster carries `cost-centre`, `owner`, `env`, `sox` labels |

Wired up via `sentinel.hcl`. Designed to run in Terraform Cloud or Terraform Enterprise.

## OPA Gatekeeper policies

| Template | Constraint | What it enforces |
| --- | --- | --- |
| `K8sRequireResourceLimits` | `require-resource-limits` | Every container has `resources.limits.cpu` and `resources.limits.memory` |
| `K8sDisallowHostNetwork` | `disallow-host-network` | No pod sets `spec.hostNetwork: true` |
| `K8sDisallowPrivileged` | `disallow-privileged` | No container runs `securityContext.privileged: true` |
| `K8sRequireTenantLabels` | `require-tenant-labels` | Every namespace has `platform.idp/tenant` and `platform.idp/tier` |
| `K8sPinWorkloadIdentityToNamespace` | `pin-wi-to-namespace` | A KSA's `iam.gke.io/gcp-service-account` annotation must match the namespace's allowed GSA list |
| `K8sRestrictedRegistries` | `restricted-registries` | Container images must come from approved registries |

`platform` and `kube-system` are excluded from most constraints via `match.excludedNamespaces`. Argo CD applies these via `argocd/apps/platform/gatekeeper.yaml` (added in v0.3).

## Testing locally

Sentinel policies have unit-test mocks alongside them in `policies/sentinel/test/`. Run with:

```bash
cd policies/sentinel
sentinel test
```

OPA policies have Rego unit tests in `policies/opa/tests/`. The Rego is
embedded in Gatekeeper `ConstraintTemplate` YAML, so the test command first
extracts the policy bodies into `build/opa/`:

```bash
make opa-test
```

Run both policy suites with:

```bash
make policy-test
```
