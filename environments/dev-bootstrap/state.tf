###############################################################################
# GCS state bucket
#
# Holds Terraform state for the *cluster* and *platform* stacks (this
# bootstrap stack itself runs on local state — chicken and egg).
# Uniform bucket-level access + versioning are non-negotiable for a state
# bucket; lifecycle prunes object versions older than 365 days.
###############################################################################

resource "google_storage_bucket" "tfstate" {
  name     = "${google_project.this.project_id}-tfstate"
  project  = google_project.this.project_id
  location = upper(var.region)

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 30
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age        = 365
      with_state = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  depends_on = [google_project_service.enabled]
}
