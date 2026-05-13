# Cost model

This is a planning model, not a bill. Prices vary by region, discounts,
committed use, logging volume, tenant workload shape, and retained metrics.
Use it to make the cost assumptions explicit before a platform review.

## Baseline monthly drivers

| Component | Dev trial posture | Production posture | Cost driver |
| --- | --- | --- | --- |
| GKE regional cluster | 1 regional control plane | 1 regional control plane per environment | control-plane fee |
| Node pools | small bronze/silver pools | silver/gold pools across zones | vCPU, memory, disk, uptime |
| Persistent disks | Prometheus, Alertmanager, Loki, tenant PVCs | same, larger retention | provisioned GiB |
| Cloud NAT | one NAT gateway | HA/NAT scale by egress | gateway + processed traffic |
| Cloud KMS | etcd, node, backup keys | same, with rotation | key versions + operations |
| Backup for GKE | optional in dev | required in prod | retained backup storage |
| Cloud Logging | audit + workload logs | audit + workload + platform logs | ingested and retained GiB |
| Artifact Registry | sample only | tenant images | storage + egress |

## Production example assumptions

| Assumption | Value |
| --- | --- |
| Region | `europe-west2` |
| Cluster count | 1 per environment |
| Silver pool | 3 to 12 `n2d-standard-4` nodes |
| Gold pool | 3 to 18 `n2d-standard-8` nodes |
| Prometheus retention | 15 days |
| Backup retention | 35 days |
| Log retention | organisation-owned sink outside this repo |

## Chargeback labels

The platform requires labels because cost attribution is an audit concern as
well as a finance concern:

- `env`
- `owner`
- `cost-centre`
- `sox`
- `platform.idp/tenant`
- `platform.idp/tier`

In production, export billing data to BigQuery and join GKE usage labels to
tenant namespace labels. The expected dashboard views are:

- monthly platform baseline cost
- monthly cost by tenant namespace
- cost by tenant tier
- unallocated spend
- SOX in-scope spend

## Optimization levers

| Lever | When to use | Risk |
| --- | --- | --- |
| Spot nodes | non-prod and interruptible bronze workloads | tenant disruption |
| Reduce Prometheus retention | high-cardinality tenants or trial clusters | weaker incident forensics |
| Tiered node pools | noisy-neighbour control | over-provisioning if tiers are too granular |
| Logging exclusion filters | noisy debug logs | accidental evidence loss |
| Separate tenant backup plans | tenant-specific RPO/RTO | more restore-plan complexity |

## Review questions

Before production approval, answer:

1. What is the monthly platform baseline before tenant workloads?
2. Which tenants are expected to be top 20% of resource consumers?
3. Which labels are mandatory for cost allocation?
4. What log and metric retention is required for audit?
5. Which workloads can safely use spot capacity?

