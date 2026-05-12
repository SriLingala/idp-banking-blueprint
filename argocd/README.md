# argocd/

Argo CD manifests that drive the in-cluster delivery story. Once
`modules/argocd-bootstrap` has installed Argo CD itself, the **root app**
under `apps/root.yaml` is applied once by hand (or via `make argocd-root`),
after which Argo CD owns the rest.

## Layout

```
argocd/
├── projects/
│   ├── platform.yaml            ← AppProject for platform-managed addons
│   └── tenant-default.yaml      ← Template AppProject used per tenant
├── apps/
│   ├── root.yaml                ← App-of-apps: scans apps/platform/ and apps/tenants/
│   ├── platform/
│   │   ├── cert-manager.yaml
│   │   ├── ingress-nginx.yaml
│   │   ├── kube-prometheus-stack.yaml
│   │   ├── loki.yaml
│   │   └── grafana.yaml
│   └── tenants/
│       └── sample-tenant.yaml   ← Wires modules/tenant-namespace + helm/sample-tenant-app
```

## How to bootstrap

```bash
# 1. Apply the root app and projects once, with cluster-admin creds.
kubectl apply -f argocd/projects/
kubectl apply -f argocd/apps/root.yaml

# 2. Argo CD takes over: it discovers apps/platform/ and apps/tenants/ and
#    reconciles them with sync-waves.
```

## Sync waves

- **wave -3** — platform-namespaces (creates monitoring, logging, cert-manager,
  ingress-nginx, gatekeeper-system with Pod Security Standards labels;
  must exist before any chart's PreSync hooks land)
- **wave -2** — kube-prometheus-stack (installs ServiceMonitor / PodMonitor /
  PrometheusRule / Alertmanager CRDs that everything else references)
- **wave -1** — cert-manager and Gatekeeper (their own CRDs land too;
  cert-manager's ClusterIssuer needs cert-manager pods Ready)
- **wave 0** — ingress-nginx, Loki, Grafana, Gatekeeper **ConstraintTemplates**
- **wave 1** — Gatekeeper **Constraints** (must land after their Template
  has been registered as a dynamic CRD)
- **wave 2** — tenant namespaces and apps (Constraints active before
  any tenant workload deploys)

`argocd.argoproj.io/sync-wave` annotations on each Application drive
ordering. Within a wave, parallel sync is fine.

## Why this lives in-repo

Argo CD reading the same Git repo that defines the cluster is deliberate:
one audit story, one PR review, one diff for any platform change.
