# Launch write-up — `idp-banking-blueprint` v1.0

> A reference Internal Developer Platform on GKE, opinionated for the constraints of a regulated banking estate. v1.0 is the point at which the blueprint covers the full life-cycle: cluster → delivery → policy → operations → audit.

## What v1.0 is

Four months and three releases on, this repo is a credible starting point for a banking IDP. By that I mean: a senior platform engineer joining a Tier-1 bank could clone this repo, read the four ADRs, and use it as the *frame* for the platform their team is going to build. Not a copy-paste production deployment — but a frame.

The four ADRs are the spine:

- **ADR-0001** — Multi-tenant via namespace, not cluster. Cost, audit, on-call load.
- **ADR-0002** — Argo CD app-of-apps. One delivery plane, one audit story.
- **ADR-0003** — Sentinel + OPA, defence-in-depth. Resource type is the boundary, not severity.
- (ADR-0004 reserved for the first decision someone forks this and disagrees with.)

## What's in the box

| Layer | Artifact | What it does |
| --- | --- | --- |
| Cluster | `modules/gke-hardened` | Regional, private, WI-enabled GKE; CMEK on etcd + boot + backup; shielded + confidential nodes; Backup for GKE; Binary Authorization opt-in |
| Tenant | `modules/tenant-namespace` | Namespace + ResourceQuota + LimitRange + default-deny NetworkPolicy + KSA with WI binding |
| Bootstrap | `modules/argocd-bootstrap` | Argo CD HA via Helm — the *only* Helm release Terraform manages |
| Delivery | `argocd/` | App-of-apps. cert-manager, ingress-nginx, kube-prometheus-stack, Loki, Grafana, Gatekeeper. Two AppProjects — platform + tenant-default. Sync waves. Sync windows. |
| Tenant chart | `helm/sample-tenant-app` | What an onboarded team's chart looks like: PSS-restricted-compliant Deployment + Service + HPA + PDB + NetworkPolicies + ServiceMonitor |
| Plan-time policy | `policies/sentinel` | Region, CMEK, private cluster, Master Authorized Networks, labels |
| Admission policy | `policies/opa` | Resource limits, host network, privileged, tenant labels, KSA→GSA pinning, restricted registries |
| Runbooks | `docs/runbooks/` | Tenant onboarding; incident response (with Gatekeeper open-failure break-glass) |
| Compliance | `docs/compliance-notes.md` | Control-to-evidence map for SOX, PCI-DSS, ISO 27001, DORA |

## Decisions I made deliberately

These come up most often when someone reads the repo and asks "why?":

- **One regional cluster per environment, not per tenant.** The ADR-0001 trade-off — cost, audit, on-call load all favour shared. Tenants that need cluster isolation go through the dedicated-cluster exception process. Documented, not a default.
- **Argo CD owns *everything* in-cluster.** Including platform addons. Including Gatekeeper itself. The temptation to split (Terraform for addons, Argo CD for tenants) fragments the audit story. One plane.
- **Sentinel AND Gatekeeper.** Not one or the other. Resource type is the boundary — anything that lives as a Terraform resource gets a Sentinel gate; anything that lives as a Kubernetes object gets a Gatekeeper constraint.
- **`validatingWebhookFailurePolicy: Fail` for Gatekeeper.** Production *should* refuse new workloads when the gate is open. The incident runbook documents the break-glass procedure for the case where you genuinely need to override during a Sev-1.
- **Pull-based, not push.** No cluster credentials in CI. Argo CD pulls Git. CI runs Terraform validate / lint / Helm lint — it never has cluster-write capability.
- **`enable_backup` requires `backup_encryption_key`.** The validation rule will fail if you toggle backups on without supplying a CMEK key. Banking can't accept Google-managed-key backups for SOX-in-scope namespaces, and an implicit fallback would be a finding.

## Decisions I deliberately *didn't* make

These are open by design. The next person who forks this is expected to make them:

- **Backstage / portal.** Not in scope for v1.0. The platform is a delivery and policy substrate. The portal sits above it.
- **Service mesh.** Istio is great. It's also a 50% increase in operational surface for marginal gain on a NetworkPolicy + Workload Identity baseline. Save it for tenants that genuinely need traffic shaping.
- **Multi-cluster federation.** Adds an audit dimension without adding much resilience for most workloads. A regional cluster with multi-zone node pools covers most.
- **Vault / external secrets.** Workload Identity covers GCP-side secrets; tenant-side secrets are out of scope here. An ExternalSecrets installation is a natural v1.1.
- **CI/CD for tenant builds.** Not the platform's job. Each tenant runs their own build pipeline; the platform owns deployment.
- **Production `environments/prod`.** `environments/prod.example` now shows the intended production shape, but a real production stack still needs organisation-specific project, state, KMS, attestor, and change-control decisions.

## How I'd extend this if I owned it

In rough order of leverage:

1. **Real `environments/prod`** copied from `environments/prod.example` after the organisation-specific state, KMS, Binary Authorization, and change-control decisions are made.
2. **ExternalSecrets operator** in `argocd/apps/platform/` for tenant-side secret material. Pulls from Secret Manager via Workload Identity.
3. **Conftest pre-commit hook** that runs the Gatekeeper Constraints against tenant Helm renders before they ever reach a PR. Shortens the feedback loop from "PR fails" to "pre-commit fails."
4. **Cost dashboards in Grafana** that join `resource_labels` from billing exports against tenant namespaces. Makes the `cost-centre` label actively useful, not just audit-decoration.
5. **Federation Sentinel policies** to be shared across multiple Terraform Cloud workspaces (not just the cluster workspace), so an out-of-region resource provisioned by a sibling team is also caught.

## How I'd hand this off

A new joiner — senior platform engineer — should be productive within their first week. I'd point them at:

1. **Day 1 morning** — Read the four ADRs in order. Then `ARCHITECTURE.md`. Then `README.md`. Don't open `*.tf` yet.
2. **Day 1 afternoon** — Walk the `modules/gke-hardened/main.tf`. Stop at every `dynamic` block; understand why the toggle exists.
3. **Day 2** — Walk the `argocd/` tree end to end. Bootstrap an Argo CD instance against a sandbox cluster. Apply the root app.
4. **Day 3** — Walk `policies/`. Run `make policy-test`.
5. **Day 4** — Run through `docs/runbooks/tenant-onboarding.md` against the sandbox cluster.
6. **Day 5** — Ask three questions. The first two will be in the ADRs. The third is what you build next.

## Acknowledgements

- The design instincts come from years of production platform work in regulated financial services; the specific implementations are this repo's.
- The ADR template is adapted from Michael Nygard's original 2011 post.
- Multi-tenant trade-offs follow the [GKE enterprise multi-tenancy guide](https://cloud.google.com/kubernetes-engine/docs/best-practices/enterprise-multitenancy).

## License

Apache 2.0. Fork it. Improve it. If you find a sharper trade-off than the one I picked, please open a PR with the reasoning — that's the kind of pressure-test this repo benefits from.

---

**Sri Lingala** · Senior Platform Engineer, Banking & Fintech
[LinkedIn](https://www.linkedin.com/in/itsmesri) · [Portfolio](https://www.srilingala.dev/) · [GitHub](https://github.com/SriLingala)
CKA · HashiCorp Terraform Associate · GCP Associate Cloud Engineer · Harness CD Certified
