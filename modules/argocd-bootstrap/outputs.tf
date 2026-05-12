output "namespace" {
  description = "Namespace where Argo CD is installed."
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "release_name" {
  description = "Helm release name. Useful for tools that key off the release."
  value       = helm_release.argocd.name
}

output "chart_version" {
  description = "Chart version that landed. Echo so callers can audit upgrades."
  value       = helm_release.argocd.version
}
