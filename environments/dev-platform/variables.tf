variable "project_id" {
  description = "GCP project hosting the cluster."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster created by environments/dev."
  type        = string
  default     = "idp-dev"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version. Pin explicitly."
  type        = string
  default     = "7.7.7"
}

variable "argocd_ha" {
  description = "Run Argo CD HA. On for production; can be off for a trial cluster to save resources."
  type        = bool
  default     = true
}
