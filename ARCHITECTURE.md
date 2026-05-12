# Architecture

This document describes the layered architecture of the platform. For the
*why* behind each layer, see the corresponding ADR in `docs/adr/`.

## Layered view

```
                   ┌────────────────────────────────────────┐
                   │   Tenant developers (consumers)        │
                   └───────────────┬────────────────────────┘
                                   │  (Backstage portal — out of scope v1)
                                   ▼
                   ┌────────────────────────────────────────┐
                   │   GitOps source of truth (Git)         │
                   └───────────────┬────────────────────────┘
                                   │
                                   ▼
                   ┌────────────────────────────────────────┐
   ┌───────────────┤   Argo CD (delivery plane)             │──► tenant namespaces
   │               └────────────────────────────────────────┘
   │
   │  Terraform Enterprise + Sentinel (control plane)
   │               ┌────────────────────────────────────────┐
   │               │   GKE (private, regional, multi-tenant)│
   │               │   - Workload Identity                  │
   │               │   - Shielded + Confidential nodes      │
   │               │   - Network policy + Pod Security Std  │
   │               └───────────────┬────────────────────────┘
   │                               │
   │                               ▼
   │               ┌────────────────────────────────────────┐
   │               │   VPC (hub-spoke), Cloud KMS, Cloud NAT│
   │               └────────────────────────────────────────┘
   │
   │  Cross-cutting (defence-in-depth)
   │               ┌────────────────────────────────────────┐
   └──────────────►│   Sentinel policy (plan-time)          │
                   │   OPA Gatekeeper / Kyverno (admission) │
                   │   Cloud Audit Logs → SIEM              │
                   │   Prometheus / Grafana / Loki          │
                   └────────────────────────────────────────┘
```

## Threat model (high level)

| Threat | Mitigation | Where enforced |
| --- | --- | --- |
| Public exposure of API server | Private cluster, master authorized networks | `modules/gke-hardened` |
| Workload using static cloud credentials | Workload Identity binding required | `modules/gke-hardened` + OPA |
| Privileged container escape | Pod Security Standards `restricted`, shielded nodes | Cluster baseline + OPA |
| Tenant lateral movement | NetworkPolicy default-deny per namespace | `modules/tenant-namespace` |
| Drift from approved baseline | Argo CD self-heal + sync waves | `argocd/` |
| Unreviewed Terraform change | Sentinel policy + mandatory PR approval | `policies/sentinel` |
| Region drift / data residency | Sentinel deny outside approved regions | `policies/sentinel` |
| Unattested container image | Binary Authorization + `K8sRestrictedRegistries` | `modules/gke-hardened` + `policies/opa` |
| Workload bypassing platform admission | Pod Security Standards + Gatekeeper Constraints | `modules/tenant-namespace` + `policies/opa` |
| Untraceable platform action | All API calls to Cloud Audit Logs → SIEM | GCP-native, configured in `modules/gke-hardened` |

## What is intentionally not here

- **Service mesh.** Istio is great; it is also expensive operationally. Most regulated estates can get the same outcome with NetworkPolicy + mTLS via Workload Identity. Save it for tenants that genuinely need traffic shaping.
- **Multi-cluster.** A single regional cluster with proper node pools covers most workloads. Multi-cluster doubles the audit surface for marginal gain.
- **Self-service IAM.** Tenants cannot mutate their own IAM. They request, platform reviews, Sentinel approves.
