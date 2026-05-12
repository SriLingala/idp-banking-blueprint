###############################################################################
# modules/tenant-namespace
#
# One namespace per tenant — the smallest unit of isolation on a shared
# regional GKE cluster (see ADR-0001). Everything in here is designed so a
# tenant cannot exfiltrate, exhaust, or escape without an explicit platform
# decision.
#
# What this module creates:
#   - Namespace, labelled for Pod Security Standards `restricted` and tagged
#     for OPA admission policies that pin workload identity to namespace.
#   - ResourceQuota — hard cap on aggregate cpu/mem/pods/PVCs.
#   - LimitRange — every container gets defaults; nothing runs unbounded.
#   - NetworkPolicy default-deny ingress and egress, with an explicit
#     allow-list for kube-dns (off-by-flag).
#   - ServiceAccount with Workload Identity annotation, bound to the
#     tenant's GCP service account at the project level (caller passes the
#     email; the GCP binding lives here because it's tenant-scoped).
#
# What this module does NOT create:
#   - The GCP service account itself. Platform engineering provisions and
#     scopes that via a separate Terraform stack with explicit IAM review.
#   - RBAC roles for tenant humans. That's onboarding (v0.3 runbook).
#   - The Argo CD AppProject. That's a separate manifest under argocd/.
###############################################################################

locals {
  ksa_name = "tenant-runtime"

  base_labels = {
    "app.kubernetes.io/managed-by"       = "terraform"
    "platform.idp/tenant"                = var.tenant
    "platform.idp/tier"                  = var.tier
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/audit"   = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
  }

  labels = merge(local.base_labels, var.extra_labels)
}

###############################################################################
# Namespace
###############################################################################

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = var.tenant
    labels = local.labels

    annotations = {
      "platform.idp/tier"                           = var.tier
      "platform.idp/owner"                          = var.tenant
      "platform.idp/created-by"                     = "modules/tenant-namespace"
      "scheduler.alpha.kubernetes.io/node-selector" = "tier=${var.tier}"
    }
  }
}

###############################################################################
# ResourceQuota — hard cap. The defaults assume a "silver" tenant; gold
# tenants override at module-call site.
###############################################################################

resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "${var.tenant}-quota"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    hard = {
      "requests.cpu"           = var.resource_quota.requests_cpu
      "requests.memory"        = var.resource_quota.requests_memory
      "limits.cpu"             = var.resource_quota.limits_cpu
      "limits.memory"          = var.resource_quota.limits_memory
      "pods"                   = var.resource_quota.pods
      "services"               = var.resource_quota.services
      "persistentvolumeclaims" = var.resource_quota.pvc
    }
  }
}

###############################################################################
# LimitRange — every container gets sensible defaults so a tenant can't ship
# an unbounded pod that schedules and then evicts a neighbour.
###############################################################################

resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "${var.tenant}-limits"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = var.default_container_limits.default_cpu
        memory = var.default_container_limits.default_memory
      }

      default_request = {
        cpu    = var.default_container_limits.request_cpu
        memory = var.default_container_limits.request_memory
      }

      max = {
        cpu    = var.default_container_limits.max_cpu
        memory = var.default_container_limits.max_memory
      }

      min = {
        cpu    = var.default_container_limits.min_cpu
        memory = var.default_container_limits.min_memory
      }
    }

    limit {
      type = "PersistentVolumeClaim"

      max = {
        storage = var.default_container_limits.max_pvc_storage
      }
    }
  }
}

###############################################################################
# NetworkPolicy — default-deny everything; opt back in via tenant-owned
# NetworkPolicies. Egress to kube-dns is allowed by default because the
# alternative is an unhelpful debugging experience on day one.
###############################################################################

resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_dns" {
  count = var.allow_dns_egress ? 1 : 0

  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
  }
}

###############################################################################
# ServiceAccount + Workload Identity binding
#
# The KSA is annotated to impersonate the supplied GCP SA. The IAM binding
# itself (roles/iam.workloadIdentityUser on the GSA) is created in the
# google provider — tenant-scoped, so it lives in this module.
###############################################################################

resource "kubernetes_service_account_v1" "tenant_runtime" {
  metadata {
    name      = local.ksa_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels

    annotations = var.gcp_service_account_email == null ? {} : {
      "iam.gke.io/gcp-service-account" = var.gcp_service_account_email
    }
  }

  automount_service_account_token = false
}

resource "google_service_account_iam_member" "wi_binding" {
  count = var.gcp_service_account_email == null ? 0 : 1

  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.tenant}/${local.ksa_name}]"
}
