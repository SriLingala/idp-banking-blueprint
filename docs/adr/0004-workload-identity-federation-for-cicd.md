# ADR 0004 — Workload Identity Federation for CI/CD

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** Platform engineering
- **Tags:** identity, cicd, supply-chain, audit

## Context

The platform's audit story rests on every Terraform change being traceable to a reviewed PR, a known reviewer, and a specific apply event. Until now, applies have been operator-initiated from a laptop or the bastion, with `gcloud auth application-default login` providing the identity. That works for a trial; it does not survive an audit at scale because:

- The identity is the operator's personal Google account, which carries every other permission they have. Blast radius on any compromised laptop is the whole estate.
- Two-person review (PR approval → apply) is honoured by convention, not enforced by the system.
- There is no machine-readable join between *the apply that happened* and *the PR that authorised it*.

The industry-standard fix in 2026 is to move CI/CD to a delivery pipeline with a system identity. Three plausible identities for that pipeline:

1. **Static JSON service-account key in GitHub Secrets.** The traditional pattern, still common in older estates. Compromise of the repo's secrets = full GCP impersonation. Rotation is manual and tedious. Auditors hate it.
2. **Workload Identity Federation (WIF).** GitHub Actions presents its OIDC token to GCP; GCP exchanges it for a short-lived federated token bound by `attribute_condition` to a specific repo + ref. No static key exists.
3. **Terraform Cloud / Enterprise workspaces.** A separate SaaS in the trust chain. Mature audit features (Sentinel, cost estimation, drift). Costs money at scale and adds a vendor dependency.

## Decision

**GitHub Actions with Workload Identity Federation.**

The pool, OIDC provider, and `terraform-actions` service account live in the project that hosts the cluster (kept close to the resources they manage). The `attribute_condition` pins the trust to:

- `assertion.repository_owner == "<owner>"`
- `assertion.repository == "<owner>/<repo>"`
- `assertion.ref` ∈ `["refs/heads/main"]` *(by default; trial uses this exact list)*

The federated principal is granted `roles/iam.workloadIdentityUser` on the SA — and nothing else. The SA holds the project-level roles Terraform actually needs. **No key exists.**

The OIDC claims that get carried through to Cloud Audit Logs include `actor`, `repository`, `ref`, `workflow`, and `run_id` — so the join from `audit log → workflow run → PR → reviewer` is mechanical and complete.

## Consequences

### Positive

- **No static keys.** No rotation, no breach radius from leaked secrets, no key-management runbook to maintain.
- **Refs allowlist enforced by GCP.** A forked PR's workflow cannot mint a token, even if a misconfigured GitHub Action would let it try.
- **Audit completeness.** Every Cloud Audit Log entry the SA produces names the workflow run that produced it. Mapped against the PR via standard GitHub APIs.
- **Two-person rule.** A required-reviewer GitHub Environment guards the apply step; the PR author cannot approve their own apply. This is enforced by GitHub, not by trust.
- **Cost.** Zero. No additional SaaS.

### Negative

- **Pool/provider lives in *one* project.** Compromise of the project's IAM admin role can broaden the trust on the pool. Mitigated by: pinning project IAM admin to a small group, alerting on changes to the pool/provider via Cloud Audit Logs (filter on `iam.googleapis.com/WorkloadIdentityPool*` resource types).
- **The SA has broad project-level roles by default.** Splitting per-stack (separate SAs for `terraform-bootstrap`, `terraform-cluster`, `terraform-platform`) is the prod move; the trial uses a single SA for simplicity. Documented as a v2.0 follow-up.
- **GitHub-hosted runners can't reach the private cluster.** The `environments/dev-platform` and `environments/dev-tenants` stacks need a self-hosted runner inside the VPC. The bastion is the natural home. Adds an operational moving part: the runner registration.
- **Branch allowlist is binary.** Either a branch is allowed to mint a token or it isn't. PR-time *plan* workflows on feature branches need a separate read-only credential surface (different SA, different attribute_condition) — added in a follow-up PR.

## What we rejected and why

- **Static JSON service-account keys.** Auditor-hostile, rotation toil, the dominant cause of GCP credential leaks in 2024–2026 GitHub-monitored breach reports. Even with strict secret-scanning, a key that exists can be exfiltrated; a key that *never exists* cannot be.
- **Terraform Cloud workspaces.** Strong product. Adds a SaaS dependency in a regulated estate that already has a non-trivial CMDB. The Sentinel features are valuable, but Sentinel policies in this repo can be enforced in a separate Sentinel runner if needed (out of scope for v1.x). Reconsider at scale where TFC's drift detection + cost estimation pay for themselves.
- **Atlantis.** Excellent open-source PR-driven runner; would deploy inside the very cluster the platform manages (interesting recursive symmetry). Adds operational burden — you now operate Atlantis. Less common in regulated banking estates than GitHub Actions native + WIF.

## How we'll know we got this wrong

- If we ever ship a static SA key into a secret store to work around a WIF limitation, the trust model has broken — revisit immediately.
- If an audit cannot trace a specific Terraform apply back to its PR and reviewer using only Cloud Audit Logs + GitHub workflow run history, the claim-propagation is broken.
- If the federated SA's role surface grows past what one platform-engineer can reasonably review in a code change, split per-stack (already on the v2.0 list).

## References

- [Workload Identity Federation for deployment pipelines (Google Cloud)](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [GitHub Actions OIDC token claims reference](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
