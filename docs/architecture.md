# Architecture diagram

> v0.1 ships with this Mermaid placeholder. Replace `architecture.svg`
> with an Excalidraw export before pinning the repo to LinkedIn — recruiters
> notice diagrams that don't look auto-generated.

```mermaid
flowchart TB
    subgraph Consumers["Tenant developers"]
        Dev[Developer]
    end

    subgraph SoT["Source of truth"]
        Git[(Git monorepo)]
    end

    subgraph ControlPlane["Control plane"]
        TFE[Terraform Enterprise<br/>+ Sentinel]
        ArgoCD[Argo CD<br/>app-of-apps]
    end

    subgraph Runtime["GKE — private, multi-tenant"]
        direction LR
        NS1[Namespace<br/>tenant A]
        NS2[Namespace<br/>tenant B]
        NS3[Namespace<br/>tenant C]
        OPA[OPA Gatekeeper<br/>admission]
    end

    subgraph Foundation["Foundation"]
        VPC[VPC, Cloud NAT]
        KMS[Cloud KMS]
        IAM[IAM + Workload Identity]
    end

    subgraph Observe["Observability"]
        Prom[Managed Prometheus]
        Grafana[Grafana]
        Loki[Loki]
        Audit[(Cloud Audit Logs<br/>→ SIEM)]
    end

    Dev -->|PR| Git
    Git --> TFE
    Git --> ArgoCD
    TFE --> Runtime
    TFE --> Foundation
    ArgoCD --> NS1 & NS2 & NS3
    OPA -.admission.-> NS1 & NS2 & NS3
    Runtime --> Observe
    Foundation --> Runtime
```
