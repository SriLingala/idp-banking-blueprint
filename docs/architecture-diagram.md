# Architecture diagram

This diagram shows the intended operating model for the platform: Terraform
owns the cloud substrate, Argo CD owns in-cluster delivery, and policy gates
run at the point where they have the right visibility.

```mermaid
flowchart TB
  dev["Tenant developers"]
  pr["GitHub pull requests<br/>review + audit trail"]
  repo["Platform Git repository<br/>Terraform + Argo CD + Helm + policy"]

  subgraph ci["CI validation"]
    tfvalidate["terraform validate"]
    tflint["tflint"]
    helmlint["helm lint/template"]
    yamllint["yamllint"]
  end

  subgraph tfc["Terraform Cloud / Enterprise"]
    plan["Terraform plan"]
    sentinel["Sentinel policy gates<br/>region, CMEK, private cluster, labels, MAN"]
    apply["Terraform apply"]
  end

  subgraph gcp["Google Cloud foundation"]
    project["GCP project + APIs"]
    vpc["VPC + subnet + secondary ranges"]
    nat["Cloud Router + Cloud NAT"]
    kms["Cloud KMS<br/>etcd, node boot, backup"]
    state["GCS Terraform state bucket"]
    bastion["IAP bastion<br/>private control plane access"]
  end

  subgraph gke["Private regional GKE cluster"]
    cluster["GKE control plane<br/>private endpoint + MAN"]
    nodes["Tiered node pools<br/>shielded / confidential nodes"]
    wi["Workload Identity"]
    backup["Backup for GKE"]
    binauthz["Binary Authorization"]
  end

  subgraph delivery["In-cluster delivery plane"]
    argocd["Argo CD HA<br/>installed once by Terraform"]
    root["Root app<br/>app-of-apps"]
    platform["Platform apps<br/>cert-manager, ingress-nginx,<br/>kube-prometheus-stack, Loki, Grafana, Gatekeeper"]
    tenantapps["Tenant applications<br/>Helm / manifests"]
  end

  subgraph tenant["Tenant isolation boundary"]
    ns["Tenant namespace"]
    quota["ResourceQuota + LimitRange"]
    netpol["Default-deny NetworkPolicy"]
    pss["Pod Security Standards<br/>restricted"]
    ksa["tenant-runtime KSA<br/>pinned to tenant GSA"]
  end

  subgraph policy["Admission and evidence"]
    gatekeeper["OPA Gatekeeper admission<br/>limits, privileged, hostNetwork,<br/>tenant labels, registry allowlist, WI pinning"]
    logs["Cloud Audit Logs + Argo CD history"]
    obs["Prometheus / Grafana / Loki"]
    runbooks["Runbooks + compliance notes"]
  end

  dev --> pr --> repo
  repo --> ci
  repo --> plan --> sentinel --> apply
  apply --> project
  apply --> vpc
  apply --> nat
  apply --> kms
  apply --> state
  apply --> bastion
  apply --> cluster
  cluster --> nodes
  cluster --> wi
  cluster --> backup
  cluster --> binauthz
  apply --> argocd
  repo --> root
  argocd --> root
  root --> platform
  root --> tenantapps
  tenantapps --> ns
  ns --> quota
  ns --> netpol
  ns --> pss
  ns --> ksa
  platform --> gatekeeper
  gatekeeper --> tenantapps
  cluster --> logs
  platform --> obs
  logs --> runbooks
  obs --> runbooks
```

## Trust boundaries

| Boundary | Owner | Main controls |
| --- | --- | --- |
| Git / review | Platform + security reviewers | PR review, branch protection, CODEOWNERS, CI |
| Terraform apply | Platform engineering | Terraform Cloud, Sentinel, state isolation |
| Cloud substrate | Platform engineering | private networking, KMS, IAM, audit logs |
| In-cluster delivery | Platform engineering | Argo CD AppProjects, sync windows, app-of-apps |
| Tenant namespace | Tenant team within platform guardrails | quotas, NetworkPolicy, PSS, Workload Identity |
| Admission | Platform security | Gatekeeper constraints, Binary Authorization |
| Evidence | Platform + risk/compliance | logs, Argo CD history, runbooks, compliance mapping |

## Main data/control flows

1. Developers open pull requests against the platform or tenant repositories.
2. CI validates Terraform, Helm, and YAML before merge.
3. Terraform plans are evaluated by Sentinel before infrastructure can be applied.
4. Terraform creates the cloud substrate, GKE cluster, and Argo CD control plane.
5. Argo CD pulls from Git and reconciles platform add-ons and tenant applications.
6. Gatekeeper evaluates Kubernetes API writes before workloads land in the cluster.
7. Audit logs, Argo CD history, and observability signals provide operational and compliance evidence.

