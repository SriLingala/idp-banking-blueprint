###############################################################################
# KMS — three customer-managed keys
#
#   etcd    — application-layer encryption of K8s Secrets (database_encryption)
#   nodes   — node boot-disk CMEK
#   backup  — Backup for GKE encryption
#
# All three live in a single regional KeyRing, rotated automatically every
# 90 days. IAM bindings grant the GKE service agent + Backup service agent
# decrypt rights.
###############################################################################

resource "google_kms_key_ring" "idp" {
  name     = "idp"
  project  = google_project.this.project_id
  location = var.region

  depends_on = [google_project_service.enabled]
}

resource "google_kms_crypto_key" "etcd" {
  name            = "etcd"
  key_ring        = google_kms_key_ring.idp.id
  rotation_period = "7776000s" # 90 days
  purpose         = "ENCRYPT_DECRYPT"

  labels = var.labels

  lifecycle {
    prevent_destroy = false # set true once you're past the trial
  }
}

resource "google_kms_crypto_key" "nodes" {
  name            = "nodes"
  key_ring        = google_kms_key_ring.idp.id
  rotation_period = "7776000s"
  purpose         = "ENCRYPT_DECRYPT"

  labels = var.labels

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key" "backup" {
  name            = "backup"
  key_ring        = google_kms_key_ring.idp.id
  rotation_period = "7776000s"
  purpose         = "ENCRYPT_DECRYPT"

  labels = var.labels

  lifecycle {
    prevent_destroy = false
  }
}

###############################################################################
# Look up the GKE + Backup service agents in this project so we can bind them
# to the keys without hardcoding the project number.
###############################################################################

data "google_project" "this" {
  project_id = google_project.this.project_id
  depends_on = [google_project_service.enabled]
}

locals {
  gke_service_agent     = "service-${data.google_project.this.number}@container-engine-robot.iam.gserviceaccount.com"
  compute_service_agent = "service-${data.google_project.this.number}@compute-system.iam.gserviceaccount.com"
  backup_service_agent  = "service-${data.google_project.this.number}@gcp-sa-gkebackup.iam.gserviceaccount.com"
}

# Application-layer etcd encryption — GKE service agent needs encrypt/decrypt.
resource "google_kms_crypto_key_iam_member" "etcd_gke" {
  crypto_key_id = google_kms_crypto_key.etcd.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.gke_service_agent}"
}

# Node boot-disk CMEK — Compute service agent encrypts/decrypts disk metadata.
resource "google_kms_crypto_key_iam_member" "nodes_compute" {
  crypto_key_id = google_kms_crypto_key.nodes.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.compute_service_agent}"
}

# Backup for GKE — the gkebackup service agent encrypts backup objects.
resource "google_kms_crypto_key_iam_member" "backup_agent" {
  crypto_key_id = google_kms_crypto_key.backup.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.backup_service_agent}"
}
