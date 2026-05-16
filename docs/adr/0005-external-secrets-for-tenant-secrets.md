# ADR 0005 — External Secrets Operator for tenant secrets

- **Status:** Accepted
- **Date:** 2026-05-16
- **Deciders:** Platform engineering
- **Tags:** secrets, identity, tenancy, audit
- **Supersedes:** the "out of scope for v1.0" note in [docs/secrets-management.md](../secrets-management.md)

## Context

The v1.0 launch wrote that tenant secrets were "out of scope" and that the trial walkthrough would simply use `kubectl create secret`. That works for a one-week trial; it does not survive an audit at scale because:

- Secrets are not in Git. There is no review trail, no diff on rotation, no "who changed this and why".
- Secrets are not separable by tenant at the storage layer. Every tenant runtime can read every cluster Secret if RBAC is misconfigured even once.
- Rotation is manual. Operators copy-paste credentials between tools, which is the dominant root cause of credential-leak incidents in 2025–2026 industry breach reports.
- The same secret material lives in N environments (dev / pre-prod / prod) with no way to enforce that values are consistent or correctly scoped.

The platform needs a single, audit-able way for a tenant to *reference* secret material that lives off-cluster, with the trust path running through the same Workload Identity story everything else uses.

Four candidates:

1. **External Secrets Operator (ESO).** A KSA in each tenant namespace impersonates a tenant-scoped GSA via Workload Identity. The GSA holds `secretmanager.secretAccessor` on a narrow path prefix. ESO syncs the chosen secrets into native Kubernetes Secrets. The K8s API server's existing RBAC continues to govern read access at the namespace level.
2. **Sealed Secrets (Bitnami).** Encrypt secrets in Git with a cluster-scoped key. Reverses the trust direction (Git becomes the source of truth for secrets). Per-tenant scoping requires per-tenant keys, which becomes a key-management problem the platform team has to own.
3. **SOPS via Argo CD plugin.** Same encrypted-in-Git story, with KMS-backed master keys. Works well for *platform-owned* secrets (cert-manager DNS01 tokens, Argo CD OIDC client secret) but pushes per-tenant key access into Git, which is the wrong place for tenant blast radius decisions.
4. **HashiCorp Vault.** Mature, comprehensive, expensive in operator-time. A bank deploying Vault correctly is a multi-quarter project and a Vault outage is a critical incident every team feels. For a blueprint that says "you can fork and deploy this", Vault is the wrong default; teams that already operate Vault can swap ESO's SecretStore to Vault without changing the tenant-facing contract.

## Decision

**External Secrets Operator (ESO) for tenant secrets, with GCP Secret Manager as the default SecretStore.**

The trust path:

```
  Tenant pod
      │
      │ KSA token, automounted (= Workload Identity)
      ▼
  KSA  ──annotated──▶  GSA  ──IAM──▶  Secret Manager prefix (e.g. payments/*)
                                 │
                                 │ secretmanager.secretAccessor
                                 ▼
                          Secret value
```

ESO runs as a platform-owned Deployment in its own `external-secrets` namespace (installed by `argocd/apps/platform/external-secrets.yaml` at sync-wave -1, alongside cert-manager and Gatekeeper).

Each tenant onboards by:

1. The platform team provisions a GCP Secret Manager *prefix* (e.g. `payments/`) and grants `roles/secretmanager.secretAccessor` on it to the tenant's GSA. Recorded in the tenant onboarding Terraform.
2. The tenant Argo CD Application bundles a per-namespace `SecretStore` referencing that GSA via Workload Identity.
3. The tenant's `ExternalSecret` resources reference remote keys under their prefix only.

Defence in depth — a Gatekeeper constraint (`K8sExternalSecretScope`, [policies/opa/templates/k8sexternalsecretscope.yaml](../../policies/opa/templates/k8sexternalsecretscope.yaml)) refuses admission for any `ExternalSecret` whose `remoteRef.key` is outside the namespace's `platform.idp/secret-prefix` annotation, regardless of what IAM says. If a misbinding ever grants a tenant GSA broader access than intended, the admission gate still refuses cross-tenant reads.

The annotation is written by the `tenant-namespace` Terraform module from a new `secret_prefix` variable, so it's declared as code at tenant onboarding and is reviewable in PRs.

## Consequences

### Positive

- **Secrets stop living in `kubectl create secret`.** Every tenant secret has a Git source of truth (the `ExternalSecret` manifest) plus an off-cluster value store (Secret Manager). The diff on rotation is `secretmanager-versions list`.
- **Per-tenant blast radius enforced at TWO layers.** IAM at the GSA → Secret Manager edge, *and* Gatekeeper at the K8s admission edge. Either layer alone bounds the radius; together they fail closed when one is misconfigured.
- **Same WI story as everything else.** No new identity primitive. Auditors who have understood the [Workload Identity Federation flow](0004-workload-identity-federation-for-cicd.md) understand the secrets flow.
- **Rotation is invisible to tenants.** Change the value in Secret Manager. ESO re-syncs on its refreshInterval (default 1h, configurable per-ExternalSecret). Pods that already-have the secret pick up the new value on next restart, or via `restartPolicy`-aware deployments.
- **Swap-friendly.** Tomorrow's Vault rollout replaces the `SecretStore` definition. The tenant's `ExternalSecret` manifest is identical.

### Negative

- **One more controller in the admission/control plane.** ESO's webhook is on the critical path for `ExternalSecret`/`SecretStore` admission. Failure policy is `Fail` (intentional — a broken manifest should be caught at admission, not three minutes later at reconcile). Outage of the webhook blocks tenants from updating manifests; existing ExternalSecrets continue to reconcile.
- **Secret Manager API quota.** Each ExternalSecret refresh consumes one `secretmanager.versions.access` call. Default refreshInterval is 1h; tenants with many secrets should batch via `dataFrom` rather than per-key `data`. Documented in the tenant onboarding runbook.
- **Tenant prefix is a string convention.** A typo on the annotation (`payments` vs `payments/`) opens or closes the tenant's access. The OPA tests cover this; tenant onboarding requires Terraform-managed Application manifests, which gets PR review.

## What we rejected and why

- **Sealed Secrets.** Reverses the trust direction (Git → cluster). Per-tenant key scoping requires per-tenant unsealing controllers, which scales poorly. Useful for the platform team's own bootstrap secrets, *not* for tenant material.
- **SOPS-in-Git.** Same trust-direction problem. Excellent for cluster-scoped operator configuration (we may still use it for the Argo CD OIDC client secret) but wrong for tenant data.
- **Vault.** Right answer for an estate that already runs Vault. Too much operational surface for a blueprint default. The ESO SecretStore abstraction means a tenant migrating *to* Vault swaps two lines, not their workload code.
- **Status quo (`kubectl create secret`).** Documented in v1.0 as a known gap. A blueprint that markets itself as banking-grade cannot ship without an answer here.

## How we'll know we got this wrong

- If we ever end up with a tenant whose `ExternalSecret` references another tenant's prefix and the admission gate failed to catch it, both the OPA template AND the namespace annotation generator are broken — revisit immediately.
- If Secret Manager API quota becomes a regular oncall page, ESO's refreshInterval is too aggressive or tenants are using `data` where `dataFrom` would batch. Adjust defaults in the onboarding runbook.
- If a tenant's secret-rotation workflow becomes a multi-step ticket, the abstraction has leaked too far — ESO should be invisible to tenants once their `SecretStore` is registered.

## References

- [External Secrets Operator documentation](https://external-secrets.io/latest/)
- [GCP Secret Manager access control via Workload Identity](https://cloud.google.com/secret-manager/docs/access-control)
- ADR-0001 — Multi-tenant by namespace (the per-tenant boundary this builds on)
- ADR-0003 — Sentinel + OPA defence in depth (the admission gate above belongs to the OPA half)
- ADR-0004 — Workload Identity Federation for CI/CD (the trust primitive)
