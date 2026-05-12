output "namespace" {
  description = "Name of the tenant namespace."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_account_name" {
  description = "Name of the tenant runtime KSA (workloads should set spec.serviceAccountName to this)."
  value       = kubernetes_service_account_v1.tenant_runtime.metadata[0].name
}

output "service_account_full" {
  description = "Fully-qualified KSA reference (namespace/name) for Workload Identity bindings."
  value       = "${kubernetes_namespace_v1.this.metadata[0].name}/${kubernetes_service_account_v1.tenant_runtime.metadata[0].name}"
}

output "tier" {
  description = "Tenant tier — useful when callers compose taints/tolerations elsewhere."
  value       = var.tier
}
