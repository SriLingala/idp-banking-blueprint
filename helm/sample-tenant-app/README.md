# helm/sample-tenant-app

Reference chart that demonstrates what an onboarded tenant's application
looks like on the platform. Every resource the chart ships exists for a
reason — admission policy, audit, SRE signal, or platform integration.

## What it ships

| Resource | Why |
| --- | --- |
| `Deployment` | The workload itself. Pod Security Standards `restricted`-compliant. |
| `Service` | ClusterIP — exposure is opt-in via `ingress.enabled`. |
| `HorizontalPodAutoscaler` | On by default. Tenants size up on real CPU signal. |
| `PodDisruptionBudget` | Guarantees 1 pod survives node drains and node-pool upgrades. |
| `NetworkPolicy` (allow ingress) | Default-deny is created by `modules/tenant-namespace`; this opts back in for ingress-nginx traffic. |
| `NetworkPolicy` (allow egress, per-rule) | Tenants opt into every external dependency by name. |
| `ServiceMonitor` | Scraped by kube-prometheus-stack. |
| `Ingress` | Off by default. Tenants enable explicitly. |

## Wiring on the platform

The chart is referenced from `argocd/apps/tenants/sample-tenant.yaml`. To
onboard a new tenant:

1. Provision a namespace via `modules/tenant-namespace` (in the platform
   Terraform stack).
2. Provision an Argo CD `AppProject` by copying
   `argocd/projects/tenant-default.yaml` and replacing `sample` with the
   tenant name.
3. Add an `Application` under `argocd/apps/tenants/` that points at
   *this* chart (or, in production, the tenant's own repo).

The tenant onboarding runbook (v0.3) automates steps 2 and 3.

## What this chart is NOT

- Not a "production tenant app". Real tenant apps have their own chart,
  their own image, their own SLOs.
- Not opinionated about language or runtime. The defaults use
  `nginx-unprivileged` because it's the smallest hardened image that
  serves traffic on a non-root port.

## Values

See `values.yaml` for the authoritative list. Highlights:

| Key | Default | Notes |
| --- | --- | --- |
| `replicaCount` | 2 | HA from day one |
| `serviceAccountName` | `tenant-runtime` | KSA created by tenant-namespace module |
| `tier` | `silver` | Drives toleration + nodeSelector |
| `resources` | small | Admission denies unbounded containers |
| `autoscaling.enabled` | true | HPA on by default |
| `networkPolicies.egress` | `[]` | Tenants opt in explicitly |
| `ingress.enabled` | false | Exposure is explicit, not implicit |
