###############################################################################
# Project + APIs
#
# Creates a new GCP project with a 6-char random suffix on project_id, links
# the supplied billing account, and enables the APIs the cluster + bastion
# need.
###############################################################################

resource "random_id" "project_suffix" {
  byte_length = 3
}

resource "google_project" "this" {
  name            = var.project_name
  project_id      = "${var.project_id_prefix}-${random_id.project_suffix.hex}"
  billing_account = var.billing_account
  labels          = var.labels

  # No org/folder — personal account creates projects at the user level.
  # If you have an org, set org_id or folder_id here.
}

locals {
  # Convenience: the APIs every other resource in this stack (and the
  # downstream cluster + platform stacks) needs enabled.
  required_apis = [
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudkms.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "gkebackup.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "iap.googleapis.com",
    "serviceusage.googleapis.com",
    "storage-api.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.required_apis)

  project                    = google_project.this.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}
