# idp-banking-blueprint

> An opinionated reference for an Internal Developer Platform on GKE,
> built around the constraints of a regulated banking environment.

[![Terraform Validate](https://github.com/SriLingala/idp-banking-blueprint/actions/workflows/terraform-validate.yml/badge.svg)](https://github.com/SriLingala/idp-banking-blueprint/actions/workflows/terraform-validate.yml)
[![TFLint](https://github.com/SriLingala/idp-banking-blueprint/actions/workflows/tflint.yml/badge.svg)](https://github.com/SriLingala/idp-banking-blueprint/actions/workflows/tflint.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

---

## Why this exists

Most open-source Internal Developer Platform (IDP) references assume an unregulated environment: any change can ship, any region is fine, any identity can do anything inside the cluster. Real banking platforms start from the opposite assumption — **every change is audited, every cluster is multi-tenant, and every policy must be enforceable as code.**

This repository is the platform I would hand a new joiner on day one at a Tier 1 bank and say: *read the ADRs, then ask me questions.*

It is **not** a tutorial. It is a credible starting point.

## Architecture

The architecture is documented in:

- [ARCHITECTURE.md](ARCHITECTURE.md) — layered overview and threat model
- [docs/architecture-diagram.md](docs/architecture-diagram.md) — Mermaid architecture diagram and trust boundaries

## Design principles

1. **Self-service for the 80%.** Tenant teams onboard via a paved road. The 20% exception cases go through platform engineering.
2. **Policy-as-code enforces what humans should never have to remember.** Sentinel runs at plan time. OPA runs at admission time.
3. **Boring infrastructure.** Surprises are a security finding.
4. **Audit-trail before convenience.** Every change is reviewable, every action is logged, every break-glass is a paged event.
5. **Identity is the perimeter.** Workload Identity in, IAM out, no static credentials anywhere.
6. **One way to do each thing.** Multiple GitOps tools fragment the audit story. Pick Argo CD; commit.

## Repo layout

```
.
├── README.md                       ← You are here
├── ARCHITECTURE.md                 ← Layered overview + threat model
├── docs/
│   ├── adr/                        ← Architecture Decision Records
│   ├── runbooks/                   ← Tenant onboarding · Incident response · Trial walkthrough
│   ├── compliance-notes.md         ← SOX / PCI-DSS / ISO 27001 / DORA mapping
│   └── launch-writeup.md           ← v1.0 launch write-up · trade-offs · what I'd extend next
├── modules/                        ← Reusable Terraform modules
│   ├── gke-hardened/               ← Production-shape GKE cluster (v0.1)
│   ├── tenant-namespace/           ← Per-tenant Kubernetes namespace (v0.2)
│   └── argocd-bootstrap/           ← Argo CD control plane (v0.2)
├── environments/
│   ├── dev-bootstrap/              ← Pre-cluster: project, VPC, KMS, state bucket, bastion (v1.1)
│   ├── dev/                        ← Reference cluster composition (v0.1)
│   ├── dev-platform/               ← Post-cluster: Argo CD bootstrap (v1.2)
│   ├── dev-tenants/                ← Per-tenant tenant-namespace module calls (v1.3)
│   └── prod.example/               ← Production-shaped example; copy into a real prod stack
├── argocd/
│   ├── projects/                   ← Multi-tenant AppProjects (v0.2)
│   └── apps/                       ← App-of-apps: platform addons + tenant apps (v0.2)
├── helm/
│   └── sample-tenant-app/          ← What an onboarded team's app looks like (v0.2)
└── policies/
    ├── sentinel/                   ← Terraform Enterprise policies (v0.3)
    └── opa/                        ← Gatekeeper ConstraintTemplates + Constraints (v0.3)
```

In-cluster software (observability, ingress, cert-manager, tenant apps) is **not** a Terraform module — Argo CD owns it via the app-of-apps pattern. See [ADR-0002](docs/adr/0002-argocd-app-of-apps.md).

## Operational readiness

- [Cost model](docs/cost-model.md)
- [SLO and alerting model](docs/slo-alerting.md)
- [Secrets management boundary](docs/secrets-management.md)
- [Disaster recovery drill](docs/runbooks/disaster-recovery-drill.md)
- [Evidence capture checklist](docs/evidence/README.md)

## Local checks

```bash
make fmt
make helm-lint
make opa-test        # requires opa
make sentinel-test   # requires sentinel
```

## Getting started

```bash
# 1. Authenticate to GCP
gcloud auth application-default login

# 2. Copy the example variables file and edit
cd environments/dev
cp terraform.tfvars.example terraform.tfvars

# 3. Plan and apply
make plan ENV=dev
make apply ENV=dev

# 4. Onboard a tenant team (once v0.3 lands)
make onboard-tenant TENANT=acme ENV=dev
```

## What this is NOT

- It is **not** a tutorial. Read the ADRs first.
- It is **not** multi-cloud. GKE is the substrate. Multi-cloud is consultant-speak; one cloud done well is platform engineering.
- It is **not** a Backstage replacement. Backstage sits above this and is out of scope for v1.
- It is **not** "click here for free production-grade infrastructure." Every value in `terraform.tfvars.example` is a decision *you* must make.

## Versioning

| Version | Status | Scope |
| --- | --- | --- |
| v0.1 | **Released** | Hardened GKE module · dev env · ADR-0001 · CI |
| v0.2 | **Released** | Tenant-namespace module · Argo CD bootstrap + app-of-apps · sample tenant Helm chart · Backup for GKE · ADR-0002 |
| v0.3 | **Released** | Sentinel policies · OPA Gatekeeper templates + constraints · tenant onboarding runbook · Binary Authorization · ADR-0003 |
| v1.0 | **Released** | Compliance notes (SOX/PCI/ISO/DORA) · incident-response runbook (with Gatekeeper break-glass) · [launch write-up](docs/launch-writeup.md) |
| v1.1 | **In progress** | CODEOWNERS · policy tests · production-shaped example · cost/SLO/DR/secrets documentation |

## Architecture Decision Records

| ID | Decision | Status |
| --- | --- | --- |
| [0001](docs/adr/0001-multi-tenant-by-namespace.md) | Multi-tenant via namespace, not cluster | Accepted |
| [0002](docs/adr/0002-argocd-app-of-apps.md) | Argo CD app-of-apps for delivery | Accepted |
| [0003](docs/adr/0003-sentinel-opa-defence-in-depth.md) | Sentinel + OPA in defence-in-depth | Accepted |

ADRs document the **trade-offs**, not the implementation. Read them first.

## Contributing

This is primarily a personal reference, but pull requests that improve clarity, fix bugs, or share an alternative trade-off (with reasoning) are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Author

**Sri Lingala** — Senior Platform Engineer · Banking & Fintech
[LinkedIn](https://www.linkedin.com/in/itsmesri) · [Portfolio](https://www.srilingala.dev/) · [GitHub](https://github.com/SriLingala)

CKA · HashiCorp Terraform Associate · GCP Associate Cloud Engineer · Harness CD Certified

## License

Apache 2.0. See [LICENSE](LICENSE).
