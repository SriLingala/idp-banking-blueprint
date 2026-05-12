# Compliance notes

This document maps the platform's controls to common regulatory frameworks. It is the answer to "show me the evidence" from an auditor walking the estate for the first time.

The frameworks covered:

- **SOX (Sarbanes-Oxley)** — financial-reporting integrity. The relevant clauses for a platform team are change management, separation of duties, and audit logs.
- **PCI-DSS v4** — payment-card data. Network segmentation, key management, monitoring, vulnerability management.
- **ISO 27001:2022** — Annex A controls. We list the controls we *enforce as code* — there are many more that are policy/process and live in our InfoSec wiki.
- **DORA (EU Digital Operational Resilience Act)** — operational resilience for financial entities. ICT risk, third-party risk, incident reporting.

The control-to-evidence map below intentionally points at concrete artifacts in this repository. An evidence-gathering exercise becomes "open the repo and walk the file" rather than "ask which engineer remembers."

## Control matrix

### Change management & segregation of duties

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| SOX | Change is authorised | Every Terraform / Argo CD change is a PR with ≥1 platform reviewer and ≥1 security reviewer (when CODEOWNERS-matched); Sentinel hard-mandatory gates block apply without org-admin override | GitHub PR history; CODEOWNERS file; Terraform Cloud audit log; `policies/sentinel/` |
| SOX | Change is logged | Argo CD application sync history maps to Git commit SHAs; Terraform Cloud retains plan/apply records | Argo CD UI → app → History; TFC audit |
| SOX | Production access is segregated | Argo CD project RBAC limits tenants to their own AppProject; platform-admin role is a separate IDP group | `argocd/projects/`; IDP group membership |
| SOX | Emergency change is post-reviewed | Argo CD project sync windows allow `manualSync: true` during an incident; the action is audit-trailed | `argocd/projects/tenant-default.yaml`; incident runbook step 7 |
| ISO A.8.32 | Change management | Same as SOX rows above | Same |

### Identity & access management

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| PCI-DSS 8.2 | Identify users | Workload Identity binding for every pod; no static credentials on nodes (CMEK boot disks, no service-account JSON files); KSA→GSA pinning enforced at admission | `modules/tenant-namespace` (WI annotation + IAM binding); `policies/opa/templates/k8spinwiserviceaccount.yaml` |
| PCI-DSS 8.3 | Strong authentication | Argo CD SSO via OIDC issuer; cluster admin access via bastion + MFA-enforced IDP | `modules/argocd-bootstrap` (oidc_issuer); IDP MFA policy (outside this repo) |
| ISO A.5.18 | Access rights | RBAC + AppProject policies; CODEOWNERS for repo writes | `argocd/projects/*.yaml`; `CODEOWNERS` |
| ISO A.8.5 | Secure authentication | No static SA keys; WI everywhere | `policies/opa/templates/k8spinwiserviceaccount.yaml` |

### Encryption & key management

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| PCI-DSS 3.5 | Protect cardholder data with strong cryptography | CMEK on boot disks, etcd, and Backup for GKE; KMS keys managed in a separate stack with rotation policy | `modules/gke-hardened` (database_encryption + boot_disk_kms_key + backup_encryption_key) |
| PCI-DSS 3.6 | Cryptographic key management | KMS keys with rotation; access logged via Cloud Audit Logs | KMS key resources (separate stack); Cloud Logging |
| ISO A.8.24 | Cryptography | Same | Same |
| DORA Art.6 | Cryptography for in-flight + at-rest | TLS 1.2+ enforced at ingress; CMEK at rest | `argocd/apps/platform/ingress-nginx.yaml` (ssl-protocols); `modules/gke-hardened` |

### Network segmentation

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| PCI-DSS 1.2 | Segment cardholder data | Private cluster, private control plane, Master Authorized Networks lock-down; NetworkPolicy default-deny per namespace; Sentinel blocks 0.0.0.0/0 and 10.0.0.0/8 on MAN | `modules/gke-hardened`; `modules/tenant-namespace` (default-deny NetworkPolicy); `policies/sentinel/enforce-master-authorized-networks.sentinel` |
| PCI-DSS 1.4 | No direct access from untrusted networks | Master Authorized Networks; Cloud NAT for egress; ingress only via internal load balancer | `modules/gke-hardened`; `argocd/apps/platform/ingress-nginx.yaml` (annotation: Internal) |
| ISO A.8.20 | Network security | Same | Same |
| DORA Art.9 | Network resilience | Regional cluster; multi-zone node pools | `modules/gke-hardened` (regional cluster, 3 zones) |

### Logging & monitoring

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| SOX | All system access is logged | Cloud Audit Logs for system + workloads + API server → Cloud Logging → SIEM | `modules/gke-hardened` (logging_config) |
| PCI-DSS 10.2 | Log all access | Same; plus Argo CD sync history; plus Gatekeeper audit events | `argocd/apps/platform/gatekeeper.yaml` (emitAdmissionEvents + emitAuditEvents) |
| PCI-DSS 10.5 | Log retention | Cloud Logging → bucket sink with 1-year retention (separate stack) | Cloud Logging sinks (outside this repo) |
| ISO A.8.16 | Monitoring activities | kube-prometheus-stack + Loki; alerting via Alertmanager | `argocd/apps/platform/kube-prometheus-stack.yaml`; `argocd/apps/platform/loki.yaml` |

### Vulnerability & patch management

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| PCI-DSS 6.3 | Patch within 30 days | GKE release channel REGULAR; weekend maintenance window | `modules/gke-hardened` (release_channel + maintenance_policy) |
| PCI-DSS 6.4 | Test changes before production | Dev environment + Argo CD self-heal in dev before prod; staged Sentinel policy rollouts (advisory → soft → hard) | `environments/dev`; `policies/sentinel/sentinel.hcl` |
| ISO A.8.8 | Vulnerability management | Workload Identity removes a major credential-leakage class; Binary Authorization blocks unattested images; restricted-registries Constraint blocks images from outside the approved list | `modules/gke-hardened` (binary_authorization); `policies/opa/constraints/restricted-registries.yaml` |

### Backup & recovery

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| DORA Art.10 | Backup of ICT systems | Backup for GKE: daily, CMEK-encrypted, 35-day retention, 7-day delete-lock | `modules/gke-hardened` (google_gke_backup_backup_plan) |
| ISO A.8.13 | Information backup | Same | Same |
| PCI-DSS 12 | Business continuity | Same; plus regional cluster spans 3 zones | Same |

### Tenant isolation & multi-tenancy

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| PCI-DSS 1.3 | Isolate cardholder environment | Pod Security Standards `restricted`; NetworkPolicy default-deny; ResourceQuota + LimitRange caps; Workload Identity scoped per tenant | `modules/tenant-namespace`; `policies/opa/` |
| ISO A.8.21 | Security of network services | Same as PCI 1.2 | Same |
| ISO A.5.18 | Privileged access scoping | The **platform** Argo CD AppProject is allowed to write to `kube-system` (needed by kube-prometheus-stack to install scrape Services for coreDns and kubelet). **Tenant** AppProjects are never allowed to write to `kube-system` — the deny-by-default posture for tenants is unchanged. | `argocd/projects/platform.yaml` (allows); `argocd/projects/tenant-default.yaml` (denies) |
| PCI-DSS 2.2 / ISO A.8.9 | Read-only root filesystem on workloads | Enforced via Pod Security Standards `restricted` on tenant namespaces and via explicit container `securityContext` on platform components. **Exception: `ingress-nginx-controller`** runs with `readOnlyRootFilesystem: false` because the controller rewrites `/etc/nginx/nginx.conf` on every reload and the upstream chart does not ship a clean read-only-root mode for 1.11.x. Compensating controls retained: runAsNonRoot + uid 101, allowPrivilegeEscalation=false, capabilities drop ALL + add only NET_BIND_SERVICE, namespace PSS `baseline`. | `argocd/apps/platform/ingress-nginx.yaml` (exception); `policies/opa/templates/k8sdisallowprivileged.yaml` (general control) |

### Cost & label hygiene (audit + finance)

| Framework | Control | How it's met | Evidence |
| --- | --- | --- | --- |
| SOX | Financial attribution | Mandatory labels `cost-centre`, `owner`, `env`, `sox` on every cluster; Gatekeeper requires `platform.idp/tenant` + `platform.idp/tier` on every namespace | `policies/sentinel/enforce-labels.sentinel`; `policies/opa/constraints/require-tenant-labels.yaml` |
| SOX | SOX-in-scope marker | `sox=in-scope` label drives quarterly evidence collection | `enforce-labels.sentinel` |

## What this document does NOT claim

- It is not a SOC 2 / ISO certification. The platform team's controls are a precondition; the org-wide certification covers people, vendors, business processes, and offices.
- It does not cover physical security, employee onboarding, vendor due diligence, or BCM exercises. Those live in the InfoSec wiki.
- It does not cover applications running *on* the platform. Each tenant signs the Platform Service Agreement and inherits these controls; the tenant remains accountable for code-level controls in their workloads.

## How to use this document in an audit

1. Walk the auditor through this map in 20 minutes; it shows the platform's intent.
2. For any row the auditor asks about, open the linked file in the repo. The code itself is the evidence.
3. For evidence that lives outside the repo (Cloud Logging sinks, IDP MFA policy, KMS rotation policy), pull the link from the InfoSec wiki and walk through the live state.
4. For change-management evidence on a specific date, query the GitHub PR history and the Terraform Cloud / Argo CD audit log for that time range.
