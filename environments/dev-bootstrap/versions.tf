terraform {
  required_version = ">= 1.5"

  # Local state on purpose: this stack creates the GCS bucket that holds
  # the cluster stack's state. Chicken-and-egg. Commit nothing under
  # .terraform/ or terraform.tfstate — both are .gitignored.

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.30, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5, < 4.0"
    }
  }
}

provider "google" {
  # No project here — we create the project inside this stack and pass it
  # to per-resource provider blocks below.
  region = var.region
}

provider "google-beta" {
  region = var.region
}
