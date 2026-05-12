# ADR 0002 — Argo CD app-of-apps for delivery

- **Status:** Accepted
- **Date:** 2026-05-12
- **Deciders:** Platform engineering
- **Tags:** delivery, gitops, argocd, audit

## Context

Once the cluster exists (see `modules/gke-hardened`), something has to install and continuously reconcile the long tail of in-cluster software: cert-manager, ingress-nginx, monitoring (kube-prometheus-stack + Grafana), logging (Loki), and the tenant applications themselves. A regulated estate adds two constraints:

1. **Every change is reviewable.** A human must be able to point at a Git commit and say "this is what changed in production at 14:07 UTC."
2. **Drift is suspicious.** A resource that exists in the cluster but not in Git is either a mistake or a finding.

Common options:

- **Terraform owns everything via `helm_release`.** Terraform's plan/apply model handles install fine, but it doesn't continuously reconcile and doesn't self-heal drift between applies.
- **A second tool (Argo CD or Flux) owns in-cluster software.** Continuous reconciliation, drift detection, pull-based, well-understood RBAC.
- **Both.** Some shops let Terraform install kube-prometheus-stack and let Argo CD install tenant apps. This fragments the audit story — there are now two places a change can land.

## Decision

**Use Argo CD with the app-of-apps pattern as the single in-cluster delivery plane.** Terraform installs Argo CD itself (`modules/argocd-bootstrap`). Argo CD installs everything else — including the observability stack, ingress controller, cert-manager, and every tenant application — by reconciling Git.

The "root" Application points at `argocd/apps/`. Argo CD discovers child Applications under `apps/platform/` and `apps/tenants/` and reconciles them in `sync-wave` order:

- **wave -1** — cert-manager + CRDs
- **wave 0** — ingress-nginx, kube-prometheus-stack, Loki, Grafana
- **wave 1** — tenant namespaces and apps

## Consequences

### Positive

- **One audit story.** Every in-cluster change is a Git commit. Argo CD's app sync history maps directly to commits.
- **Self-heal.** A pod restarting at 3am that mutates a deployment annotation is reverted within the sync interval.
- **Onboarding is a PR.** New tenant = one AppProject manifest + one Application manifest. The runbook (v0.3) automates the PR.
- **Project-scoped RBAC.** Tenants can sync their own Applications without touching the platform project, and they cannot create cluster-scoped resources.
- **Sync windows are first-class.** The default tenant AppProject denies syncs outside business hours UTC, with explicit manual override for paged incidents. Matches the banking change-freeze pattern.
- **Pull-based.** No cluster credentials in CI runners. The cluster pulls Git; CI never pushes to the cluster.

### Negative

- **Two reconciliation engines.** Terraform reconciles the cluster + Argo CD itself. Argo CD reconciles everything else. The boundary must be clear in code (one Helm release in Terraform; everything else in Argo CD) and clear in runbooks (incident triage starts by asking which plane owns the resource).
- **Argo CD is itself a workload.** It has its own HA topology, its own RBAC story, its own upgrade cadence. Production runs Argo CD HA (multi-replica controller, repo-server, server, redis-ha).
- **Argo CD's RBAC is bespoke.** Casbin-style policy strings. Less ergonomic than Kubernetes RBAC, but well-documented.
- **Sync waves are sequential, not transactional.** A failed wave-0 app does not roll back wave-(-1). Mitigated with `selfHeal` + retries; understood with runbooks.

## What we rejected and why

- **Terraform owns everything via `helm_release`.** Loses continuous reconciliation and drift detection. Every cluster-side change becomes a Terraform run, which means CI needs cluster credentials — a worse audit story.
- **Flux v2.** Comparable to Argo CD on capability. We picked Argo CD because (a) the UI is the strongest in class and reduces operator toil during incidents, (b) most banking platforms I've seen already standardised on it, (c) the AppProject model maps directly to our multi-tenant story. Flux is defensible; this is a coin-flip with a slight Argo CD lean.
- **Split ownership** (Terraform for platform addons, Argo CD for tenant apps). Tempting because Terraform handles the kubernetes provider bootstrap problem more cleanly for platform-critical addons. Rejected because it fragments the audit story and creates an inconsistent "is this in Git or Terraform?" question for engineers at 3am.

## How we'll know we got this wrong

- If more than 10% of platform-addon changes have to be done via `kubectl edit` because Argo CD's reconciliation loop conflicts with operator behaviour, we've picked a fight with operators and should re-scope what Argo CD manages.
- If Argo CD itself becomes a Sev-1 cause twice in a year (control plane wedged, sync hung, repo-server OOM), the operational cost has outweighed the audit-story benefit and we should evaluate Flux or a hybrid.
- If tenant developers consistently route around Argo CD (port-forward + kubectl apply, "I just need to try one thing"), our self-service story is broken and we need to invest in tenant-side UX, not delivery-plane changes.

## References

- [Argo CD app-of-apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Argo CD AppProject reference](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#projects)
- [ADR-0001 — Multi-tenant via namespace](0001-multi-tenant-by-namespace.md)
