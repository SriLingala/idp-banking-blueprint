output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully-qualified ID of the cluster."
  value       = google_container_cluster.this.id
}

output "endpoint" {
  description = "Private endpoint of the control plane."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Cluster CA certificate (base64)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload Identity pool the cluster is bound to."
  value       = "${var.project_id}.svc.id.goog"
}

output "location" {
  description = "Cluster region."
  value       = google_container_cluster.this.location
}

output "node_pool_names" {
  description = "Names of the managed node pools."
  value       = [for np in google_container_node_pool.this : np.name]
}

output "backup_plan_id" {
  description = "ID of the baseline Backup for GKE plan (null when enable_backup is false)."
  value       = var.enable_backup ? google_gke_backup_backup_plan.baseline[0].id : null
}
