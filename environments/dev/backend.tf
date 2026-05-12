# Remote state lives in a dedicated state-only project (one of the few cross-cutting
# pieces of infrastructure provisioned manually). The bucket has:
#   - Uniform bucket-level access
#   - Versioning enabled
#   - CMEK encryption
#   - Object lifecycle = never delete
#
# Replace the placeholders below before terraform init.

terraform {
  backend "gcs" {
    bucket = "REPLACE-tf-state-idp-banking-blueprint"
    prefix = "env/dev"
  }
}
