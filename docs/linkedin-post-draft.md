I built `idp-banking-blueprint`: an opinionated Internal Developer Platform reference for regulated banking on GKE.

Most IDP examples optimise for developer speed. That matters, but in banking the platform also has to answer harder questions:

- Can every change be reviewed and audited?
- Can tenants deploy independently without escaping their boundary?
- Can policy be enforced by code instead of remembered by humans?
- Can we explain the platform clearly to security, risk, and audit teams?

This repo brings together:

- hardened private GKE with Workload Identity, CMEK, NetworkPolicy, Binary Authorization, Backup for GKE, and audit logging
- Terraform modules for the cluster, Argo CD bootstrap, and tenant namespaces
- Argo CD app-of-apps for in-cluster delivery
- namespace-based multi-tenancy with quotas, LimitRanges, default-deny NetworkPolicies, and Pod Security Standards
- Sentinel policies at Terraform plan time
- OPA Gatekeeper policies at Kubernetes admission time
- a sample tenant Helm chart showing the “paved road”
- runbooks for onboarding and incident response
- compliance notes mapping controls to SOX, PCI-DSS, ISO 27001, and DORA evidence

The main design choice: Terraform owns the substrate, Argo CD owns the in-cluster world, Sentinel blocks bad cloud infrastructure before apply, and Gatekeeper blocks bad workloads before admission.

This is not a one-click production deployment. It is a blueprint: the kind of repo I would hand to a new senior platform engineer and say, “Read the ADRs first. Then let’s discuss the trade-offs.”

Repo: https://github.com/SriLingala/idp-banking-blueprint

Medium write-up: <paste Medium link here>

#PlatformEngineering #DevOps #Kubernetes #GKE #Terraform #GitOps #ArgoCD #CloudSecurity #PolicyAsCode #BankingTechnology #SRE

