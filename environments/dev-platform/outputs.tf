output "argocd_namespace" {
  description = "Namespace where Argo CD is installed."
  value       = module.argocd.namespace
}

output "argocd_chart_version" {
  description = "Argo CD chart version that landed."
  value       = module.argocd.chart_version
}

output "next_steps" {
  description = "Operator-facing recap of how to reach Argo CD and bootstrap the root app."
  value       = <<-EOT

    Argo CD is installed in namespace '${module.argocd.namespace}'.

    Reach the UI:
      kubectl -n ${module.argocd.namespace} port-forward svc/argocd-server 8080:443
      # then https://localhost:8080  (cert is self-signed; OK for trial)

    Admin password (first login):
      kubectl -n ${module.argocd.namespace} get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d ; echo

    Apply the platform AppProject + root-app to start GitOps reconciliation
    of every other addon (cert-manager, ingress-nginx, kube-prometheus-stack,
    Loki, Grafana, Gatekeeper, sample-tenant-app):
      git clone https://github.com/SriLingala/idp-banking-blueprint.git
      cd idp-banking-blueprint
      make argocd-root
  EOT
}
