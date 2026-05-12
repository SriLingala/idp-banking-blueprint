# modules/gke-hardened

A regional, private, Workload-Identity-enabled GKE cluster with defaults
appropriate for a regulated banking estate.

## What you get

- Private cluster (private nodes + private control plane endpoint)
- Master authorized networks (no 0.0.0.0/0 access)
- Workload Identity bound to the project pool
- Shielded nodes (secure boot + integrity monitoring)
- Confidential nodes (AMD SEV) — on by default
- Pod Security Standards enforced cluster-wide
- VPC-native networking (required for NetworkPolicy)
- NetworkPolicy enabled (Calico)
- CMEK on node boot disks + application-layer etcd encryption
- Cloud Audit Logs → Cloud Logging for system, workloads, API server
- Managed Prometheus enabled
- Release channel REGULAR, weekend maintenance window

## Usage

```hcl
module "gke" {
  source = "../../modules/gke-hardened"

  project_id = var.project_id
  region     = "europe-west2"
  name       = "idp-dev"

  network    = module.vpc.network_self_link
  subnetwork = module.vpc.subnet_self_link

  pods_secondary_range_name     = "pods"
  services_secondary_range_name = "services"
  master_ipv4_cidr_block        = "172.16.0.0/28"

  master_authorized_networks = [
    {
      cidr_block   = "10.10.0.0/24"
      display_name = "platform-admin-bastion"
    },
  ]

  database_encryption_key = google_kms_crypto_key.etcd.id
  boot_disk_kms_key       = google_kms_crypto_key.nodes.id

  node_pools = {
    bronze = {
      machine_type  = "e2-standard-4"
      min_count     = 1
      max_count     = 5
      initial_count = 1
      taints = [{ key = "tier", value = "bronze", effect = "NO_SCHEDULE" }]
      labels = { tier = "bronze" }
    }
    silver = {
      machine_type  = "n2-standard-4"
      min_count     = 2
      max_count     = 10
      initial_count = 2
      labels = { tier = "silver" }
    }
  }

  labels = {
    env     = "dev"
    owner   = "platform-engineering"
    sox     = "in-scope"
  }
}
```

## Inputs

See `variables.tf` for the authoritative list. Required:

| Name | Type | Notes |
| --- | --- | --- |
| `project_id` | string | GCP project ID |
| `region` | string | GCP region (data-residency pinned) |
| `name` | string | Cluster name |
| `network` | string | VPC self-link |
| `subnetwork` | string | Subnet self-link with secondary ranges |
| `pods_secondary_range_name` | string | Secondary range name for Pods |
| `services_secondary_range_name` | string | Secondary range name for Services |
| `master_ipv4_cidr_block` | string | /28 for private control plane |
| `database_encryption_key` | string | KMS key for etcd CMEK |
| `boot_disk_kms_key` | string | KMS key for node boot disks |
| `node_pools` | map(object) | One entry per tier |

## Outputs

| Name | Notes |
| --- | --- |
| `cluster_name` | |
| `cluster_id` | |
| `endpoint` | Sensitive |
| `ca_certificate` | Sensitive |
| `workload_identity_pool` | |
| `location` | |
| `node_pool_names` | |

## What you must provide outside this module

- A VPC and subnet with secondary IP ranges named per the inputs
- KMS keys for etcd + boot disk CMEK (the IAM bindings to the GKE service agent must already exist)
- A Cloud NAT or private Google access route if nodes need to pull external images
- A bastion or VPN reachable from `master_authorized_networks`

## Known limitations

- Does not provision the VPC, KMS keys, or Cloud NAT. That belongs to the environment composition layer (`environments/dev`).
- Does not manage Binary Authorization attestors and policy — the cluster opts in via `enable_binary_authorization`, but the attestors are owned by platform IAM in a separate stack.

## Changelog

- **v0.3.1** — Widen default maintenance window (Sat+Sun 03:00→11:00 UTC, 16h/week) to satisfy GKE's 48h-per-32-day floor. The previous 4h/day default failed cluster creation with `maintenance policy would go longer than 32d without 48h maintenance availability`.
- **v0.3** — Binary Authorization: cluster opts in to BinAuthz via `enable_binary_authorization` (default true, `PROJECT_SINGLETON_POLICY_ENFORCE`).
- **v0.2** — Backup for GKE: in-cluster agent + baseline daily backup plan with CMEK and 35-day retention. Opt out with `enable_backup = false`. Caller must supply `backup_encryption_key` when enabled.
- **v0.1.2** — Fix `logging_config.enable_components` (`API_SERVER` → `APISERVER`) and move `confidential_nodes` back inside `node_config` on the node pool. Both were `terraform validate` failures.
- **v0.1** — Initial release.
