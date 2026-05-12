terraform {
  required_version = ">= 1.5"

  backend "gcs" {
    # bucket is supplied via -backend-config at init time. Same bucket as
    # the cluster stack; different prefix.
    prefix = "env/dev-platform"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.27, < 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13, < 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
