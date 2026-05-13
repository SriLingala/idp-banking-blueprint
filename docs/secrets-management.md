# Secrets management boundary

This blueprint deliberately avoids static cloud credentials. Workloads use
GKE Workload Identity to access Google Cloud services.

## Current boundary

| Secret class | Owner | Expected handling |
| --- | --- | --- |
| Cloud API access | Platform | Workload Identity, no service-account JSON keys |
| Argo CD OIDC client secret | Platform | Existing Kubernetes secret reference passed to Argo CD bootstrap |
| Argo CD repo credentials | Platform | Repository secrets created by bootstrap or injected by secure operator flow |
| Tenant application secrets | Tenant + platform guardrails | Out of scope for v1.0; use External Secrets in the next increment |
| KMS keys | Platform security | Created in bootstrap/security stack, access logged |

## Recommended v1.1 extension

Install External Secrets Operator through Argo CD and bind it to Secret
Manager using Workload Identity:

1. Platform installs `external-secrets` as a platform Application.
2. Each tenant gets a namespace-scoped `SecretStore` or `ClusterSecretStore`
   reference approved by platform security.
3. Tenants create `ExternalSecret` resources in their namespace.
4. Gatekeeper constrains `ExternalSecret` references so tenants cannot read
   another tenant's Secret Manager path.

## Non-negotiables

- Do not commit `Secret` manifests with literal credentials.
- Do not mount service-account JSON keys into pods.
- Do not allow tenants to create arbitrary IAM bindings from their own repos.
- Do not use wildcard Secret Manager access for tenant runtime identities.

