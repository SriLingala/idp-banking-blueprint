# ADR 0001 — Multi-tenant via namespace, not cluster

- **Status:** Accepted
- **Date:** 2026-05-11
- **Deciders:** Platform engineering
- **Tags:** isolation, cost, multi-tenancy

## Context

A regulated banking platform needs to host workloads from many engineering teams (tenants) on a shared substrate. The two common patterns are:

1. **Cluster-per-tenant** — every team gets its own GKE cluster.
2. **Namespace-per-tenant** — one regional cluster, every team gets one or more isolated namespaces.

Both are defensible. The choice has long-tail consequences for cost, blast radius, audit, on-call load, and how easily auditors can be walked through the estate.

## Decision

**Namespace-per-tenant on a single regional GKE cluster per environment**, with isolation enforced by:

- Kubernetes NetworkPolicy (default deny ingress and egress)
- Pod Security Standards (`restricted`) cluster-wide
- Resource quotas and LimitRanges per namespace
- OPA Gatekeeper / Kyverno admission policies that pin tenant identity to namespace
- Workload Identity bindings scoped per tenant
- Separate node pools per "tenant tier" (gold / silver / bronze) using taints and tolerations, not per-tenant node pools

## Consequences

### Positive

- **Cost.** A regional GKE cluster has a fixed control plane cost. Hosting 30 tenant namespaces on one cluster is materially cheaper than 30 clusters.
- **Auditability.** Auditors review one cluster, one set of admission policies, one observability stack. The story is much shorter.
- **On-call load.** One control plane to patch, one upgrade window to plan, one set of node pool decisions to manage.
- **Faster onboarding.** Tenant onboarding is "create a namespace + bindings", not "provision a cluster".
- **Cross-tenant policy uniformity.** A new security control is one change, not thirty.

### Negative

- **Noisy-neighbour is now your problem forever.** A tenant's misconfigured pod that exhausts node CPU affects others. Mitigated with quotas, LimitRanges, and tier-based node pools — but cannot be eliminated. The platform team must own this.
- **Blast radius of a control-plane upgrade is wider.** A bad upgrade affects all tenants simultaneously. Mitigated with release channel = REGULAR and prod environments lagging dev by at least one release window.
- **Tenants that genuinely need cluster-level isolation** (specific compliance regimes, kernel-level dependencies, or unusually high throughput) must go through an exception process. That process must exist and be documented; otherwise it becomes shadow IT.
- **Tooling that assumes one tenant per cluster** (some service mesh installs, some operator patterns) needs extra care.

## What we rejected and why

- **Cluster-per-tenant.** Cost-prohibitive at scale, multiplies on-call surface, makes platform-wide changes a thirty-cluster rollout, and signals to tenants that they "own" their cluster — which leads to drift from platform standards and a poorer audit story.
- **Virtual cluster (vcluster) per tenant.** Promising, but in 2026 the operational maturity in regulated estates is not yet there. Revisit at v2.0.
- **GKE Autopilot only.** Reduces operational toil but removes the node-pool tiering we use for noisy-neighbour control. Acceptable for dev environments; not the default.

## How we'll know we got this wrong

- If platform-on-call pages exceed two tenant-isolation incidents per quarter, the namespace-only boundary is insufficient and we should escalate the loudest tenants to dedicated node pools or a dedicated cluster.
- If a single Sev-1 in one tenant's namespace causes correlated impact in three or more other tenants in a year, the shared cluster is the wrong shape for the workload mix.

## References

- [GKE multi-tenancy best practices (Google)](https://cloud.google.com/kubernetes-engine/docs/best-practices/enterprise-multitenancy)
- [Kubernetes multi-tenancy SIG](https://github.com/kubernetes-sigs/multi-tenancy)
