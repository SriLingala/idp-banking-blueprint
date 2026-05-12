###############################################################################
# Bastion VM
#
# Smallest viable jump host into the private VPC. Reached via gcloud's IAP
# TCP forwarding (no public IP on the bastion itself; SSH tunnels through
# Google's IAP service to localhost). The cluster's master_authorized_networks
# allow-lists the bastion's *internal* CIDR so kubectl works from the bastion.
#
# Image:    debian-12 (minimal; we apt-install gcloud + kubectl on first boot)
# Identity: a dedicated SA scoped to logging.viewer + container.viewer only;
#           the platform engineer's IAP-tunnelled session inherits *their*
#           identity for kubectl auth, not the SA's.
###############################################################################

resource "google_service_account" "bastion" {
  account_id   = "bastion"
  display_name = "Bastion VM"
  project      = google_project.this.project_id

  depends_on = [google_project_service.enabled]
}

# Minimum IAM for the bastion SA — log writing only. Cluster auth happens
# under the human operator's identity via IAP + gcloud.
resource "google_project_iam_member" "bastion_logwriter" {
  project = google_project.this.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

resource "google_project_iam_member" "bastion_metricwriter" {
  project = google_project.this.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

resource "google_compute_instance" "bastion" {
  name         = "bastion"
  project      = google_project.this.project_id
  zone         = "${var.region}-a"
  machine_type = var.bastion_machine_type

  tags = ["bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.dev.self_link
    # No access_config block = no public IP. IAP tunnel is the only way in.
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    # Block project-wide SSH keys; only OS-Login (via IAP) is allowed.
    block-project-ssh-keys = "TRUE"
    enable-oslogin         = "TRUE"
    # Cloud-init script installs gcloud + kubectl on first boot.
    user-data = <<-EOT
      #cloud-config
      package_update: true
      package_upgrade: false
      runcmd:
        - apt-get update
        - apt-get install -y apt-transport-https ca-certificates gnupg curl
        - curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
        - echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list
        - apt-get update
        - apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl
    EOT
  }

  labels = var.labels

  allow_stopping_for_update = true
}

# Grant the active gcloud user the IAP tunnel-user role so they can SSH in.
data "google_client_openid_userinfo" "me" {}

resource "google_iap_tunnel_instance_iam_member" "user_ssh" {
  project  = google_project.this.project_id
  zone     = google_compute_instance.bastion.zone
  instance = google_compute_instance.bastion.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "user:${data.google_client_openid_userinfo.me.email}"
}

# OS-Login admin so the user can `gcloud compute ssh` directly.
resource "google_project_iam_member" "user_oslogin" {
  project = google_project.this.project_id
  role    = "roles/compute.osAdminLogin"
  member  = "user:${data.google_client_openid_userinfo.me.email}"
}
