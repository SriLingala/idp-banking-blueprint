# Building an Internal Developer Platform Blueprint for Regulated Banking

Internal Developer Platforms are often described as a way to make developers faster. That is true, but in a regulated banking environment speed is only half the story.

The harder question is this:

How do you let engineering teams ship independently while still keeping every change reviewable, every workload isolated, every identity traceable, and every control enforceable as code?

That is the problem behind `idp-banking-blueprint`, an opinionated reference architecture for an Internal Developer Platform on Google Kubernetes Engine. It is not meant to be a one-click production deployment. It is a credible starting point: the kind of repository I would give to a senior platform engineer joining a banking platform team and say, "Read the ADRs first, then let us talk about the trade-offs."

Repository: https://github.com/SriLingala/idp-banking-blueprint

## What the Blueprint Does

At its core, the project defines a secure, multi-tenant platform foundation for application teams running on GKE.

It brings together:

- Terraform modules for a hardened GKE cluster, tenant namespaces, and Argo CD bootstrap
- GitOps delivery through Argo CD using the app-of-apps pattern
- Tenant isolation through namespaces, resource quotas, LimitRanges, NetworkPolicies, Pod Security Standards, and Workload Identity
- Policy-as-code with Sentinel at Terraform plan time and OPA Gatekeeper at Kubernetes admission time
- Platform add-ons such as cert-manager, ingress-nginx, kube-prometheus-stack, Grafana, Loki, and Gatekeeper
- A sample tenant Helm chart showing what a compliant tenant workload should look like
- Runbooks for tenant onboarding and incident response
- Compliance notes mapping platform controls to SOX, PCI-DSS, ISO 27001, and DORA

The key design goal is not just to provision infrastructure. It is to make the platform auditable, repeatable, and understandable.

In banking, a platform is not successful only because it works. It is successful when an auditor, security architect, platform engineer, and tenant team can all look at the same repository and understand what is allowed, what is blocked, and why.

## Why This Exists

Many public IDP examples assume an environment where developer convenience is the primary constraint. They focus on fast onboarding, self-service deployment, and simple abstractions.

Those things matter, but a banking platform starts from a different baseline.

Every change needs an audit trail. Every cluster decision affects compliance posture. Static credentials are unacceptable. Data residency matters. A tenant should not be able to accidentally exhaust shared resources or bypass platform controls. A platform engineer should not need to remember every rule manually at review time.

That is why the blueprint treats policy, identity, isolation, and evidence as first-class design elements.

The repository is built around a few principles:

- Self-service should cover the common path, while exceptions stay visible to platform engineering.
- Policy should be enforced by code, not remembered by humans.
- Infrastructure should be boring, predictable, and reviewable.
- Identity is the perimeter, so Workload Identity is preferred over static credentials.
- A single delivery plane creates a cleaner audit story than several overlapping tools.

This is the difference between "we can deploy an app" and "we can explain exactly how this platform behaves under audit, failure, and tenant growth."

## The Architecture in Plain English

The platform is layered.

At the bottom is Google Cloud infrastructure: VPC, subnets, Cloud NAT, KMS keys, a state bucket, and a bastion host for access to the private control plane. That bootstrap layer gives the platform a secure landing zone before the cluster exists.

Above that sits a regional private GKE cluster. The cluster is configured with private nodes, a private control plane endpoint, master authorized networks, Workload Identity, VPC-native networking, NetworkPolicy, CMEK-based encryption, shielded nodes, optional confidential nodes, managed logging, managed monitoring, Binary Authorization, and Backup for GKE.

Terraform owns the cloud infrastructure and the GKE cluster. It also installs Argo CD itself.

After that boundary, Argo CD owns the in-cluster world. Platform add-ons and tenant applications are expressed as Kubernetes manifests and Helm charts under the `argocd/` tree. Argo CD continuously reconciles those resources from Git.

That separation is deliberate:

- Terraform owns the substrate.
- Argo CD owns in-cluster delivery.
- Sentinel checks Terraform plans before cloud resources are created.
- Gatekeeper checks Kubernetes objects before they enter the cluster.

The result is a platform where each control runs at the point where it has the right visibility.

## Multi-Tenancy: Namespace First, Not Cluster First

One of the most important decisions in the repository is ADR-0001: multi-tenant by namespace, not cluster.

The blueprint assumes one regional GKE cluster per environment, with each tenant getting an isolated namespace. That namespace is not just a folder for Kubernetes objects. It carries the isolation model.

The tenant namespace module creates:

- Pod Security Standards labels set to `restricted`
- ResourceQuota to cap aggregate CPU, memory, pods, services, and PVCs
- LimitRange so containers cannot run unbounded
- Default-deny NetworkPolicy for ingress and egress
- Optional DNS egress so day-one debugging is not painful
- A tenant runtime Kubernetes service account
- Workload Identity binding to a tenant-scoped Google service account

This gives tenant teams a paved road while keeping the platform team in control of the dangerous boundaries.

Cluster-per-tenant is not wrong, but it has a cost: more control planes, more patching, more audit surface, more drift, and slower onboarding. The blueprint chooses shared regional clusters because that is often the better default for cost, auditability, and operational load.

It also documents the trade-off honestly. Some tenants may need dedicated clusters because of compliance, kernel-level dependencies, or unusual throughput requirements. Those should be explicit exceptions, not the default path.

## GitOps as the Delivery Plane

ADR-0002 explains another major choice: Argo CD app-of-apps.

Terraform installs Argo CD through the `argocd-bootstrap` module. After that, Argo CD installs everything else inside the cluster:

- cert-manager
- ingress-nginx
- kube-prometheus-stack
- Grafana
- Loki
- Gatekeeper
- tenant applications

The root Argo CD application points at the `argocd/apps` directory and discovers child applications recursively. Sync waves control ordering, so namespaces and CRDs land before the components that depend on them.

This matters because regulated platforms need a clean audit story. If Terraform installs some Helm charts, Argo CD installs others, and CI occasionally applies manifests directly, it becomes harder to answer a simple question: "What changed in production?"

With this model, in-cluster changes are Git changes. Argo CD sync history maps back to commits. Drift is visible. Self-healing is possible. Tenant onboarding becomes a pull request.

The tenant AppProject is intentionally restrictive. It pins tenants to their namespace, disallows cluster-scoped resources, uses project-scoped roles, and includes a weekend change-freeze window with manual override for incidents.

That is a very banking-shaped design: autonomy, but inside a controlled operating model.

## Policy-as-Code in Two Places

The most important security idea in the repository is ADR-0003: Sentinel and OPA Gatekeeper together.

This is not duplication. It is separation of responsibility.

Sentinel runs at Terraform plan time. It can see cloud infrastructure before it is created. In this blueprint, Sentinel policies enforce controls such as:

- approved regions for data residency
- customer-managed encryption keys
- private GKE clusters
- master authorized networks
- required audit and finance labels

Gatekeeper runs at Kubernetes admission time. It can see workloads before they enter the cluster. The Gatekeeper policies enforce controls such as:

- every container must define CPU and memory limits
- pods cannot use host networking
- privileged containers are denied
- tenant namespaces must carry required labels
- Workload Identity service accounts must be pinned to the namespace
- images must come from approved registries

The boundary is not "important policies go here and less important policies go there." The boundary is resource type.

If it is Terraform-managed cloud infrastructure, Sentinel is the gate. If it is a Kubernetes object, Gatekeeper is the gate.

That gives the platform defence in depth without pretending one policy engine can see everything.

## What a Tenant Gets

The sample tenant chart is useful because it shows what "good" looks like for an onboarded team.

It includes:

- a restricted, non-root deployment
- a ClusterIP service
- HPA enabled by default
- a PodDisruptionBudget for safer node upgrades
- NetworkPolicies that opt back into ingress and explicit egress
- a ServiceMonitor for Prometheus scraping
- optional ingress

The chart is not trying to be every application. It is a reference shape.

That distinction matters. A good platform does not hide every detail from developers. It gives them a safe default and makes the secure path easier than the insecure one.

## Operations and Audit Are Part of the Platform

One thing I like about this repository is that it does not stop at infrastructure.

The `docs/runbooks` directory includes tenant onboarding and incident response. The onboarding runbook describes the PRs, identity-provider groups, cost-centre checks, CI requirements, and post-merge validation steps. The incident response runbook covers severity, ownership, diagnostics, communication, rollback preference, backup restore, post-mortems, and Gatekeeper break-glass handling.

The compliance notes map controls to evidence across SOX, PCI-DSS, ISO 27001, and DORA. That does not make the platform certified, and the document is careful not to claim that. What it does do is turn the repo into an evidence map.

For example:

- change management maps to GitHub PRs, Terraform Cloud audit logs, and Argo CD sync history
- identity controls map to Workload Identity and Argo CD RBAC
- encryption maps to CMEK-backed etcd, node boot disks, and Backup for GKE
- network segmentation maps to private clusters, authorized networks, and namespace NetworkPolicies
- monitoring maps to Cloud Audit Logs, kube-prometheus-stack, Loki, and Grafana

In real regulated environments, this is where platform engineering earns trust. The code is not just code. It is evidence.

## What I Deliberately Left Out

The blueprint is opinionated, but it is not pretending to be complete.

It deliberately leaves out:

- Backstage or a developer portal
- service mesh
- multi-cluster federation
- tenant build pipelines
- tenant-side secret management
- a production environment folder with copied defaults

Those omissions are useful. A reference architecture should have boundaries. Otherwise it becomes a demo that tries to cover everything and teaches nothing.

Backstage can sit above this. ExternalSecrets could be a natural next step. Cost dashboards could connect billing exports to tenant labels. Conftest could bring Gatekeeper feedback earlier into the developer workflow. Disaster-recovery drill runbooks would make Backup for GKE more operationally complete.

But the foundation is already there: cluster, delivery, policy, operations, and audit.

## The Bigger Lesson

The biggest lesson from building this blueprint is that an IDP for banking is not just a developer experience project. It is an operating model encoded in code.

The platform has to answer questions like:

- Who can deploy?
- Where can workloads run?
- What happens if a tenant forgets resource limits?
- How do we prove a change was reviewed?
- What happens if the admission controller fails?
- How do we isolate teams without creating unnecessary clusters?
- How do we make the right path easy without making the platform opaque?

Those are not only technical questions. They are platform governance questions.

This repository is my answer to those questions for a GKE-based banking platform. It is not the only valid answer, but it is a deliberate one.

And that is what good platform engineering should be: not a pile of tools, but a set of choices that can survive production, audit, and the next engineer reading the repo.

