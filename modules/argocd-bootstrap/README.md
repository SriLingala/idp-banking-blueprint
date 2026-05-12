# modules/argocd-bootstrap

Installs the Argo CD control plane via the official `argo-helm/argo-cd`
chart. This is the **only** Helm release Terraform manages directly —
everything else (cert-manager, ingress-nginx, kube-prometheus-stack, Loki,
tenant apps) is delivered by Argo CD via the app-of-apps pattern.

See [ADR-0002](../../docs/adr/0002-argocd-app-of-apps.md) for the trade-offs.

## What you get

- Argo CD installed into the `argocd` namespace, labelled for Pod Security
  Standards `restricted`
- HA topology by default (2x controller, 2x repo-server, 2x server, redis-ha)
- Optional ingress, with cert-manager-issued TLS, when `domain` is set
- Optional OIDC SSO, falling back to the chart-generated admin password
- Project-scoped RBAC default of `role:readonly` (project admin policies
  live in `argocd/projects/*.yaml`)
- Repository credential secrets, one per Git repository Argo CD is allowed
  to read

## Usage

```hcl
module "argocd" {
  source = "../../modules/argocd-bootstrap"

  chart_version = "7.7.7"
  ha            = true

  domain          = "platform.example.bank"
  tls_secret_name = "argocd-tls"

  oidc_issuer             = "https://login.example.bank"
  oidc_client_id          = "argocd"
  oidc_client_secret_kref = "$argocd-oidc:clientSecret"

  repositories = [
    {
      name           = "platform"
      url            = "git@github.com:example-bank/platform.git"
      ssh_secret_ref = "argocd-platform-deploy"
    },
  ]
}
```

## Bootstrapping note

The `kubernetes` and `helm` providers must be configured against the
already-created cluster. Wire this in a **separate Terraform stack**
(e.g. `environments/dev-platform/`) that runs after the cluster stack and
takes the cluster outputs via `terraform_remote_state` or a published
data source. Don't co-locate this with the cluster resource — fresh
`apply` will fail because the kubernetes provider can't resolve the
cluster endpoint at plan time.

## Inputs

See `variables.tf`. Notable inputs:

| Name | Default | Notes |
| --- | --- | --- |
| `namespace` | `argocd` | Created by this module |
| `chart_version` | `7.7.7` | Pin explicitly; bumps go through review |
| `ha` | `true` | HA topology + redis-ha |
| `domain` | `null` | Enables ingress at `argocd.<domain>` |
| `tls_secret_name` | `null` | Required when domain is set |
| `oidc_issuer` | `null` | Enables OIDC SSO when paired with `client_id` and `client_secret_kref` |
| `repositories` | `[]` | One `repo-<name>` secret per entry |

## Outputs

| Name | Notes |
| --- | --- |
| `namespace` | Argo CD namespace |
| `release_name` | Helm release name |
| `chart_version` | Echo of the installed chart version |
