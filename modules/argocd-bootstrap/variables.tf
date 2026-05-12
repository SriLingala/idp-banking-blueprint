variable "namespace" {
  description = "Kubernetes namespace for the Argo CD control plane. Created by this module."
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-helm/argo-cd chart version. Pin explicitly — bumps go through review."
  type        = string
  default     = "7.7.7"
}

variable "argocd_image_tag" {
  description = "Argo CD image tag. Leave null to track the chart default."
  type        = string
  default     = null
}

variable "ha" {
  description = "Run Argo CD HA (multi-replica controller, repo-server, server, redis-ha). Production default."
  type        = bool
  default     = true
}

variable "domain" {
  description = "Hostname used by Argo CD's ingress (`argocd.<domain>`). Leave null to disable ingress and rely on port-forward."
  type        = string
  default     = null
}

variable "tls_secret_name" {
  description = "Existing TLS secret to terminate on Argo CD's ingress. Required when domain is set."
  type        = string
  default     = null
}

variable "oidc_issuer" {
  description = "OIDC issuer URL for Argo CD SSO. Null disables OIDC and falls back to the admin password."
  type        = string
  default     = null
}

variable "oidc_client_id" {
  description = "OIDC client ID. Required when oidc_issuer is set."
  type        = string
  default     = null
}

variable "oidc_client_secret_kref" {
  description = "Kubernetes secret reference (`secret:name/key`) holding the OIDC client secret. Required when oidc_issuer is set."
  type        = string
  default     = null
}

variable "repositories" {
  description = "Git repositories Argo CD is pre-authorised to read. Each entry creates a `repo-creds` secret."
  type = list(object({
    name           = string
    url            = string
    ssh_secret_ref = optional(string) # name of existing secret with sshPrivateKey
    https_username = optional(string)
    https_password = optional(string)
  }))
  default = []
}

variable "extra_values" {
  description = "Free-form additional Helm values, merged last. Use sparingly — preference is to add a typed input."
  type        = string
  default     = ""
}
