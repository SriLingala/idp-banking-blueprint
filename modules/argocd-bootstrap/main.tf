###############################################################################
# modules/argocd-bootstrap
#
# Installs the Argo CD control plane via the official argo-helm chart. This
# is the *only* Helm release Terraform manages directly — everything else
# (cert-manager, ingress-nginx, kube-prometheus-stack, Loki, tenant apps) is
# delivered by Argo CD via the app-of-apps pattern under `argocd/`.
# See ADR-0002 for the trade-offs.
#
# Bootstrapping note:
#   The kubernetes + helm providers must be configured against the
#   already-created cluster. The calling environment composition does this
#   in a separate stack ("platform" stack) that runs after the cluster
#   stack — see the v0.2 wiring note in the top-level README.
###############################################################################

locals {
  ingress_enabled = var.domain != null

  oidc_enabled = (
    var.oidc_issuer != null &&
    var.oidc_client_id != null &&
    var.oidc_client_secret_kref != null
  )

  # Compose Helm values from typed inputs. We deliberately keep this small
  # — every value here represents a platform decision, not a tenant knob.
  values = yamlencode({
    global = {
      domain = var.domain
    }

    controller = {
      replicas = var.ha ? 2 : 1
    }

    server = {
      replicas = var.ha ? 2 : 1

      ingress = {
        enabled          = local.ingress_enabled
        ingressClassName = "nginx"
        hostname         = local.ingress_enabled ? "argocd.${var.domain}" : null
        tls              = local.ingress_enabled && var.tls_secret_name != null
        annotations = local.ingress_enabled ? {
          "nginx.ingress.kubernetes.io/backend-protocol" = "GRPC"
        } : {}
      }

      extraArgs = local.ingress_enabled ? [] : ["--insecure"]

      config = local.oidc_enabled ? {
        "oidc.config" = yamlencode({
          name         = "platform-sso"
          issuer       = var.oidc_issuer
          clientID     = var.oidc_client_id
          clientSecret = var.oidc_client_secret_kref
          requestedScopes = [
            "openid",
            "profile",
            "email",
            "groups",
          ]
        })
      } : {}
    }

    repoServer = {
      replicas = var.ha ? 2 : 1
    }

    applicationSet = {
      replicas = var.ha ? 2 : 1
    }

    redis-ha = {
      enabled = var.ha
    }

    redis = {
      enabled = !var.ha
    }

    configs = {
      params = {
        # Required when server runs behind a TLS-terminating ingress that
        # speaks gRPC to the pod.
        "server.insecure" = !local.ingress_enabled
      }

      cm = {
        # Keep the resource exclusion list short and explicit — Argo CD's
        # default excludes Cilium identities, etc.
        "application.instanceLabelKey" = "argocd.argoproj.io/instance"
      }

      rbac = {
        "policy.default" = "role:readonly"
        # Project-scoped admin policies live in argocd/projects/*.yaml.
      }
    }
  })
}

###############################################################################
# Namespace — we manage it explicitly so labels and annotations are codified.
###############################################################################

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "platform.idp/component"             = "argocd"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

###############################################################################
# Argo CD chart release
###############################################################################

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  # `atomic` and a sensible timeout — upgrades that fail half-way are worse
  # than upgrades that roll back cleanly.
  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = compact([
    local.values,
    var.extra_values,
  ])

  dynamic "set" {
    for_each = var.argocd_image_tag == null ? [] : [1]
    content {
      name  = "global.image.tag"
      value = var.argocd_image_tag
    }
  }
}

###############################################################################
# Repository credentials — one secret per Git repository Argo CD is allowed
# to read. Public HTTPS repos do not need an entry.
###############################################################################

resource "kubernetes_secret_v1" "repo_creds" {
  for_each = { for r in var.repositories : r.name => r }

  metadata {
    name      = "repo-${each.value.name}"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
      "app.kubernetes.io/managed-by"   = "terraform"
    }
  }

  type = "Opaque"

  data = merge(
    {
      url  = each.value.url
      name = each.value.name
    },
    each.value.ssh_secret_ref != null ? {} : {},
    each.value.https_username != null ? { username = each.value.https_username } : {},
    each.value.https_password != null ? { password = each.value.https_password } : {},
  )
}
