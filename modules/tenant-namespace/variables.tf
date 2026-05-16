variable "tenant" {
  description = "Tenant identifier. Becomes the namespace name and the label/annotation value across resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.tenant))
    error_message = "tenant must be a DNS-1123 label (lowercase, 1-63 chars, alnum + dashes)."
  }
}

variable "tier" {
  description = "Tenant tier. Drives node selection via tolerations and informs quota defaults."
  type        = string
  default     = "silver"

  validation {
    condition     = contains(["bronze", "silver", "gold"], var.tier)
    error_message = "tier must be one of bronze, silver, gold."
  }
}

variable "project_id" {
  description = "GCP project hosting the cluster. Required to build the Workload Identity binding."
  type        = string
}

variable "gcp_service_account_email" {
  description = "GCP service account the tenant Kubernetes service account impersonates. Pass null to skip the Workload Identity binding (e.g. read-only tenants)."
  type        = string
  default     = null
}

variable "resource_quota" {
  description = "ResourceQuota for the tenant namespace. Override per-tenant when negotiated."
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    pods            = string
    services        = string
    pvc             = string
  })
  default = {
    requests_cpu    = "4"
    requests_memory = "8Gi"
    limits_cpu      = "8"
    limits_memory   = "16Gi"
    pods            = "50"
    services        = "20"
    pvc             = "10"
  }
}

variable "default_container_limits" {
  description = "LimitRange defaults applied to every container in the namespace. Prevents an unbounded pod from starving the node."
  type = object({
    default_cpu     = string
    default_memory  = string
    request_cpu     = string
    request_memory  = string
    max_cpu         = string
    max_memory      = string
    min_cpu         = string
    min_memory      = string
    max_pvc_storage = string
  })
  default = {
    default_cpu     = "500m"
    default_memory  = "512Mi"
    request_cpu     = "100m"
    request_memory  = "128Mi"
    max_cpu         = "4"
    max_memory      = "8Gi"
    min_cpu         = "10m"
    min_memory      = "16Mi"
    max_pvc_storage = "100Gi"
  }
}

variable "allow_dns_egress" {
  description = "Allow egress to kube-dns. Almost always true; off only for tenants with no in-cluster name resolution."
  type        = bool
  default     = true
}

variable "extra_labels" {
  description = "Extra labels applied to the namespace. Common: cost-centre, sox=in-scope, data-classification."
  type        = map(string)
  default     = {}
}

variable "secret_prefix" {
  description = "Secret Manager / SecretStore path prefix this tenant is allowed to read via External Secrets Operator. Written to the namespace as the platform.idp/secret-prefix annotation, which the K8sExternalSecretScope Gatekeeper constraint enforces at admission time. Leave empty to deny every ExternalSecret in this namespace (fail closed). Convention: \"<tenant>/\" — e.g. \"payments/\"."
  type        = string
  default     = ""
}

variable "allowed_gsa" {
  description = "Comma-separated list of GCP service-account emails this namespace is allowed to impersonate via Workload Identity. Written to the namespace as platform.idp/allowed-gsa, which the K8sPinWIServiceAccount Gatekeeper constraint enforces. Defaults to var.gcp_service_account_email when null."
  type        = string
  default     = null
}
