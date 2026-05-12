# ADR 0003 — Sentinel + OPA in defence-in-depth

- **Status:** Accepted
- **Date:** 2026-05-12
- **Deciders:** Platform engineering · Security architecture
- **Tags:** policy, security, governance, defence-in-depth

## Context

A banking platform has to express controls as code in two places, because two different classes of mistake can land bad configuration in production:

1. **Misconfigured infrastructure** lands in cloud at Terraform `apply`. Example: a GKE cluster created with `enable_private_endpoint = false`, or a Cloud SQL instance in `us-central1` (data-residency violation).
2. **Misconfigured workloads** land in the cluster at `kubectl apply`. Example: a Pod with `hostNetwork: true`, or a Deployment without `resources.limits`.

A single policy engine can only see one of these. Sentinel runs at Terraform plan time and never sees `kubectl`. Gatekeeper runs at Kubernetes admission and never sees a Terraform plan. Picking one and not the other leaves an obvious blind spot — and auditors will find it.

## Decision

**Run both layers, each enforcing the controls it can actually see.**

- **Sentinel** is the gate on Terraform Cloud / Enterprise. Hard-mandatory policies block apply for: non-approved regions, missing CMEK, public clusters, public master-authorized-networks, missing audit labels.
- **OPA Gatekeeper** is the gate at Kubernetes admission. ConstraintTemplates and Constraints under `policies/opa/` enforce: container resource limits, no host network, no privileged containers, tenant-label requirement, Workload-Identity pinning, restricted registry list.

The boundary between them is the resource type, not the severity of the rule. Anything that exists as a Terraform resource gets a Sentinel policy. Anything that exists as a Kubernetes object gets a Gatekeeper constraint.

## Consequences

### Positive

- **No blind spots.** Every regulated control has a code-enforced gate at the moment it can land.
- **Auditors can read both layers.** Sentinel is HCL-flavoured; Gatekeeper constraints are YAML + Rego. Both are reviewable and version-controlled.
- **Failure modes are different.** A Sentinel breakage stops new infrastructure; a Gatekeeper breakage stops new workloads. Neither cascades into the other.
- **Defence-in-depth.** A configuration mistake has to bypass two gates to land. Realistic threat models assume one gate fails; two simultaneous failures are exceptional.
- **Independent ownership.** Platform-infra team owns Sentinel; platform-security team can own Gatekeeper. Coordination via CODEOWNERS, not via merge conflict.

### Negative

- **Two policy languages.** Sentinel (Sentinel Lang) and Rego are similar enough to confuse engineers; neither is a daily language. Mitigated with curated, well-commented examples in `policies/` and a 30-minute primer in onboarding.
- **Gatekeeper itself is a workload.** Its webhook is in the admission critical path. We run it HA (2 replicas), set `validatingWebhookFailurePolicy: Fail` (so a Gatekeeper outage *blocks* new pods), and document the override procedure in the incident runbook.
- **Sentinel requires Terraform Cloud or Enterprise.** Free-tier or OSS Terraform deployments cannot run Sentinel. Acceptable in a banking estate; would be a blocker for a startup.
- **Constraint drift.** A platform-team Constraint change affects every tenant. Tested before merge in a staging cluster.

## What we rejected and why

- **OPA Gatekeeper only.** Loses Sentinel's plan-time enforcement. A Terraform apply can still create a non-compliant GCP resource; Gatekeeper sees nothing because no Kubernetes object is involved.
- **Sentinel only.** Loses the admission-time gate. `kubectl apply` of a bad Pod manifest succeeds, and the noisy-neighbour or escape is only caught after the fact (or not at all).
- **Kyverno instead of Gatekeeper.** Kyverno is comparable on most policies and ships better mutating support. We chose Gatekeeper because (a) Constraints feel closer to Kubernetes-native CRDs, which audit teams find easier to walk through, (b) the OPA project is the better-supported policy engine across the broader stack (Conftest, Gatekeeper, Styra), so investing in Rego pays off twice. Kyverno is defensible; this is a coin-flip with a slight Gatekeeper lean.
- **Binary Authorization alone for image policy.** BinAuthz is the *deny-by-default* gate for unsigned images; the `K8sRestrictedRegistries` constraint is the *allowlist* gate for which registries are even acceptable. They complement each other; we run both.

## Sentinel enforcement levels

| Level | Behaviour | When we use it |
| --- | --- | --- |
| `hard-mandatory` | Blocks apply; no override | Region, CMEK, private cluster, MAN — anything that is a regulatory requirement |
| `soft-mandatory` | Blocks apply; org-admin override audit-trailed | Labels — strongly enforced but exceptions exist (legacy projects mid-migration) |
| `advisory` | Warns, does not block | Reserved for new policies during rollout |

## How we'll know we got this wrong

- If platform engineers routinely use the soft-mandatory override more than once per month for the same policy, the policy is wrong or the exception list needs codifying.
- If a Sev-1 incident's post-mortem identifies a control that should have been enforced as code but wasn't, that's a Sentinel or Gatekeeper gap; track it in the next quarter's policy sprint.
- If tenant teams report that the policy gates feel arbitrary or that error messages don't tell them how to fix the violation, our error UX has failed. Constraints should include `metadata.gatekeeper.sh/title` and `description`; Sentinel `print` statements should be specific.

## References

- [HashiCorp Sentinel docs](https://developer.hashicorp.com/sentinel)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [ADR-0001 — Multi-tenant via namespace](0001-multi-tenant-by-namespace.md)
- [ADR-0002 — Argo CD app-of-apps](0002-argocd-app-of-apps.md)
