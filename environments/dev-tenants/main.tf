###############################################################################
# environments/dev-tenants
#
# Tenant compositions. One module call per tenant. Onboarding a new
# tenant = a PR that adds a module block here + a matching Application
# manifest under argocd/apps/tenants/.
#
# Where this runs:
#   Like environments/dev-platform, this stack speaks to the cluster's
#   private API endpoint and must be applied from the bastion (via
#   gcloud's IAP tunnel).
###############################################################################

data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

data "google_client_config" "this" {}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.this.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.this.access_token
}

###############################################################################
# Sample tenant
#
# Reference onboarding to demonstrate the tenant-namespace module end to
# end. The chart at helm/sample-tenant-app uses serviceAccountName
# `tenant-runtime`, which this module creates.
#
# Trial trade-off: gcp_service_account_email is null — no Workload
# Identity binding. Sample-tenant-app is stateless nginx and doesn't
# need GCP IAM. In prod, every tenant has a dedicated GSA provisioned
# in a separate IAM Terraform stack with reviewed scopes.
###############################################################################

module "tenant_sample" {
  source = "../../modules/tenant-namespace"

  tenant     = "sample"
  tier       = "silver"
  project_id = var.project_id

  gcp_service_account_email = null

  extra_labels = {
    "cost-centre"         = "9999-trial"
    "data-classification" = "internal"
    "sox"                 = "out-of-scope"
  }
}

output "sample_namespace" {
  description = "Tenant namespace name; cross-reference with sample-tenant-app Application destination."
  value       = module.tenant_sample.namespace
}

output "sample_service_account" {
  description = "Tenant KSA reference (namespace/name) — passed to Workload Identity bindings in prod."
  value       = module.tenant_sample.service_account_full
}
