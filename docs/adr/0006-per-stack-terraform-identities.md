# ADR 0006 — Per-stack Terraform identities

- **Status:** Accepted
- **Date:** 2026-05-16
- **Deciders:** Platform engineering
- **Tags:** identity, cicd, audit, blast-radius
- **Builds on:** [ADR-0004 — Workload Identity Federation for CI/CD](0004-workload-identity-federation-for-cicd.md)

## Context

ADR-0004 introduced one apply SA (`terraform-actions`) and one read-only plan SA (`terraform-plan`). The apply SA carried the union of every stack's roles — project IAM admin (for bootstrap) plus container.admin (for cluster) plus container.developer + serviceAccountUser (for platform and tenants). It was deliberately documented as a v2.0 follow-up.

The trial-walkthrough doc and the v1.4 readiness review both flagged this as the single biggest "is this actually safe for prod?" gap:

- The SA needs the *union* of every stack's roles to apply *any* stack. Compromise of any workflow on `main` — supply chain attack on a Terraform provider, malicious commit that the merge-review missed, etc. — gives the attacker the union of all those roles, not just the role surface of the stack the workflow targets.
- Auditors reviewing IAM cannot tell from the SA's bindings which stack is operating. Cloud Audit Logs show `terraform-actions@... did $thing` whether the change came from `dev-bootstrap` or `dev-tenants`.
- A reviewer reading the role surface of the SA cannot reason about blast radius per stack — every role applies to every workflow.

The fix is what every regulated bank ends up doing for delivery-pipeline SAs: one apply SA per stack, each with the minimum role surface that stack actually needs.

## Decision

**Four per-stack APPLY service accounts, one shared read-only PLAN service account.**

All five live in the same Workload Identity Pool (`github-actions`) plus a separate pool for plan (`github-actions-plan`). The pool-level `attribute_condition` (repo + ref allowlist) is identical across SAs — what diverges is the IAM role surface on each:

| Service account        | Stack                              | Headline roles                                          |
|------------------------|------------------------------------|---------------------------------------------------------|
| `terraform-bootstrap`  | `environments/dev-bootstrap`       | project IAM admin, KMS admin, network admin, storage admin |
| `terraform-cluster`    | `environments/dev`                 | container admin, gkebackup admin, KMS encrypt/decrypt (NOT key admin) |
| `terraform-platform`   | `environments/dev-platform`        | container.developer (K8s API only), storage.objectAdmin |
| `terraform-tenants`    | `environments/dev-tenants`         | container.developer + iam.serviceAccountUser            |
| `terraform-plan`       | every stack (PR-time plans)        | viewer + securityReviewer (read-only)                   |

The full lists live in [environments/dev-bootstrap/variables.tf](../../environments/dev-bootstrap/variables.tf) as overridable variables — defaults are tuned for the trial topology; prod overrides per project.

The `modules/github-oidc-wif` module was extended with a `create_pool` toggle. The first call creates the pool + provider + the bootstrap SA; subsequent calls (cluster, platform, tenants, plan) reuse the pool via `pool_resource_name`. One pool = one trust boundary; per-SA role surfaces stay narrow.

The matching apply workflow (introduced separately) selects the SA by stack at job time via a `vars.GCP_TERRAFORM_<STACK>_SA` repository variable. The plan workflow continues to use the single shared `terraform-plan` SA because read-only roles compose cleanly.

## Consequences

### Positive

- **Blast radius capped per stack.** A compromise of the platform-apply workflow cannot recreate the project, rotate KMS keys, or destroy the cluster — those roles are not in `terraform-platform`'s surface.
- **Auditor-readable IAM.** Reading the role bindings on each SA tells you what the corresponding stack can change. No code reading required.
- **Cloud Audit Logs become stack-aware.** Every API call carries the per-stack SA name; `terraform-cluster@…` in the log means a cluster-stack change, full stop.
- **Per-stack rotation.** Rotating the cluster SA does not require rotating the bootstrap SA. Lower coordination cost during incident response.
- **Same WI primitive.** No new identity tech. Anyone who has read ADR-0004 understands this in one sitting.

### Negative

- **More bootstrap variables.** Five role lists where there was one. Trade-off: the lists are explicit, defaulted, and reviewable in PRs. ADR-0004's single `project_roles` list was tighter to read but hid the per-stack contract.
- **Apply workflow has to pick the right SA per stack.** A bug in the workflow's stack→SA mapping could grant the wrong identity. Mitigated by: workflow uses a `matrix` keyed on stack with the SA selected via `vars`, so there's one switch statement, not five copy-pasted auth blocks.
- **First-apply UX.** The bootstrap `github_actions_secrets` output now emits five `gh variable set ...` lines instead of two. Operator wets-finger-and-pastes once.

## Things we deliberately did NOT do

- **Per-workflow attribute_condition.** A tighter binding (`principal://…job_workflow_ref:owner/repo/.github/workflows/apply-cluster.yml@refs/heads/main`) would refuse to mint a cluster SA token from *any* workflow other than the cluster-apply workflow. Worth doing once apply workflows are shipped. Not in this ADR because the apply workflows aren't shipped yet; tightening this is straightforward when they are.
- **Per-stack pools.** Five separate pools, each with its own `attribute_condition`, would be the strongest split. We rejected it because the operational cost (five pool resource paths to wire into `gh variable set`, five attribute_conditions to keep in sync, five blast radii to monitor for IAM admin changes) outweighs the marginal trust gain over per-SA roles + per-workflow bindings.
- **Splitting the plan SA per stack.** Read-only roles compose cleanly. One plan SA is enough and simpler.

## How we'll know we got this wrong

- If a stack-apply workflow ever needs to call APIs the stack's SA cannot reach, the role lists are wrong (or the workflow is doing something out of scope). Fix the list, don't loosen the SA.
- If an audit cannot tell which stack changed a given resource using only Cloud Audit Logs, the SA-naming convention has broken — ensure the SA names always end in the stack name.
- If we ever add a sixth stack and the temptation is to "just use bootstrap" because it has the roles, the split has broken — add the sixth SA.

## References

- [GCP IAM least-privilege guidance for service accounts](https://cloud.google.com/iam/docs/best-practices-service-accounts)
- ADR-0004 — Workload Identity Federation for CI/CD (the primitive this splits)
- ADR-0001 — Multi-tenant by namespace (same blast-radius reasoning, different layer)
