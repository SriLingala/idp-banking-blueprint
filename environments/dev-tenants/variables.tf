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
  description = "GKE cluster name (from environments/dev)."
  type        = string
  default     = "idp-dev"
}
