###############################################################################
# environments/dev-platform
#
# Post-cluster stack. Installs Argo CD into the cluster created by
# environments/dev. Argo CD then owns everything else (cert-manager,
# ingress-nginx, kube-prometheus-stack, Loki, Grafana, Gatekeeper,
# sample-tenant-app) via the app-of-apps pattern under argocd/.
#
# Where this runs:
#   The GKE control plane is private (enable_private_endpoint = true).
#   This stack must be applied from a host inside the VPC — typically
#   the bastion (provisioned by environments/dev-bootstrap), reachable
#   via gcloud's IAP tunnel.
###############################################################################

###############################################################################
# Read the live cluster — its endpoint + CA cert are how the kubernetes /
# helm providers authenticate. Using a data source (not terraform_remote_state)
# means this stack does not need read access to the cluster stack's state.
###############################################################################

data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

data "google_client_config" "this" {}

###############################################################################
# Kubernetes + Helm providers — pointed at the just-created private cluster.
# The access token comes from the active gcloud identity (the operator on
# the bastion).
###############################################################################

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.this.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.this.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.this.endpoint}"
    cluster_ca_certificate = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.this.access_token
  }
}

###############################################################################
# Argo CD control plane.
#
# We keep the trial config minimal: no OIDC, no ingress, no repo
# credentials. After this lands, the operator runs `make argocd-root`
# from inside the bastion to apply the platform AppProject + root-app,
# which kicks off everything else.
###############################################################################

module "argocd" {
  source = "../../modules/argocd-bootstrap"

  chart_version = var.argocd_chart_version
  ha            = var.argocd_ha

  # Trial: no domain → no ingress → port-forward access from the bastion.
  domain          = null
  tls_secret_name = null

  # Trial: no SSO. Use the chart-generated admin password (printed in
  # the README of modules/argocd-bootstrap).
  oidc_issuer             = null
  oidc_client_id          = null
  oidc_client_secret_kref = null

  # The platform repo is public, so no repo credentials needed for the
  # canonical platform / sample-tenant Applications.
  repositories = []
}
