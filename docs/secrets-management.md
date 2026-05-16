# Secrets management boundary

This blueprint deliberately avoids static cloud credentials. Workloads use
GKE Workload Identity to access Google Cloud services.

## Current boundary

| Secret class | Owner | Expected handling |
| --- | --- | --- |
| Cloud API access | Platform | Workload Identity, no service-account JSON keys |
| Argo CD OIDC client secret | Platform | Existing Kubernetes secret reference passed to Argo CD bootstrap |
| Argo CD repo credentials | Platform | Repository secrets created by bootstrap or injected by secure operator flow |
| Tenant application secrets | Tenant + platform guardrails | External Secrets Operator (v1.5+) — see below |
| KMS keys | Platform security | Created in bootstrap/security stack, access logged |

## Tenant secrets — External Secrets Operator (v1.5+)

External Secrets Operator (ESO) is installed by Argo CD at platform sync-wave
-1 via [argocd/apps/platform/external-secrets.yaml](../argocd/apps/platform/external-secrets.yaml).
It binds to GCP Secret Manager via Workload Identity. The full trade-off
rationale lives in [ADR-0005](adr/0005-external-secrets-for-tenant-secrets.md).

How a tenant onboards:

1. Platform team provisions a GCP Secret Manager *prefix* for the tenant
   (e.g. `payments/`) and grants `roles/secretmanager.secretAccessor` on
   that prefix only to the tenant GSA.
2. The `tenant-namespace` Terraform module's `secret_prefix` variable
   writes the allowed prefix as the `platform.idp/secret-prefix`
   annotation on the namespace.
3. The tenant Argo CD Application bundles a per-namespace `SecretStore`
   referencing the tenant GSA via Workload Identity.
4. The tenant's `ExternalSecret` resources reference remote keys under
   their prefix only — anything outside is refused at admission.

Two enforcement layers:

- **IAM** at the GSA → Secret Manager edge (`secretmanager.secretAccessor`
  on the prefix only).
- **Gatekeeper** at the K8s admission edge — the `K8sExternalSecretScope`
  ConstraintTemplate ([policies/opa/templates/k8sexternalsecretscope.yaml](../policies/opa/templates/k8sexternalsecretscope.yaml))
  refuses any `ExternalSecret` whose `remoteRef.key` or `dataFrom[].extract.key`
  is outside the namespace's `platform.idp/secret-prefix` annotation. Fails
  closed when the annotation is missing.

A tenant cannot read another tenant's Secret Manager path even if the
IAM binding on the GSA is mis-scoped — the admission gate refuses
cross-tenant access regardless.

## Non-negotiables

- Do not commit `Secret` manifests with literal credentials.
- Do not mount service-account JSON keys into pods.
- Do not allow tenants to create arbitrary IAM bindings from their own repos.
- Do not use wildcard Secret Manager access for tenant runtime identities.

