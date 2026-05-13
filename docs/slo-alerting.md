# SLO and alerting model

The blueprint ships observability components, but production readiness comes
from the service objectives and alerts wrapped around them.

## Platform SLOs

| Capability | SLO | Measurement |
| --- | --- | --- |
| Kubernetes API reachability | 99.9% monthly | GKE control-plane health and API probes from bastion/runner |
| Argo CD reconciliation | 99% of platform apps Synced + Healthy within 10 minutes | Argo CD application metrics |
| Gatekeeper admission | 99.9% webhook availability | webhook request success rate and latency |
| Ingress availability | 99.9% for platform-managed ingress | ingress-nginx 5xx/error budget |
| Tenant onboarding | 95% completed within 1 business day after prerequisites | onboarding ticket timestamps |
| Backup freshness | daily backup completed within 26 hours | Backup for GKE job status |

## High-signal alerts

| Alert | Severity | Why it matters |
| --- | --- | --- |
| `ArgoCDAppOutOfSyncTooLong` | Sev-2 platform, Sev-3 tenant | Git no longer matches cluster state |
| `ArgoCDAppUnhealthy` | Sev-2 platform, Sev-3 tenant | Reconciliation is not producing healthy workloads |
| `GatekeeperWebhookDown` | Sev-1 if failure policy is Fail | New workloads may be blocked |
| `GatekeeperDenySpike` | Sev-3 | Tenant or platform release is hitting admission policy |
| `Ingress5xxHigh` | Sev-1/2 by blast radius | Customer traffic is failing |
| `NodePoolSaturation` | Sev-2 | Tenants may go Pending despite valid manifests |
| `TenantQuotaNearLimit` | Sev-3 | Preventable tenant outage |
| `BackupPlanStale` | Sev-2 | Recovery objective is at risk |
| `PrometheusCardinalityHigh` | Sev-3 | Observability stack at risk from tenant metrics |

## Example Prometheus rules to add

The exact metric names depend on chart versions and enabled exporters. Keep
the rule intent stable even when metrics change:

```yaml
groups:
  - name: platform-argocd
    rules:
      - alert: ArgoCDAppOutOfSyncTooLong
        expr: argocd_app_info{sync_status!="Synced"} == 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Argo CD application has been OutOfSync for more than 10 minutes"

  - name: platform-gatekeeper
    rules:
      - alert: GatekeeperDenySpike
        expr: increase(gatekeeper_violations[10m]) > 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Gatekeeper denials spiked"
```

## Dashboard expectations

Minimum production dashboards:

- platform overview: cluster, Argo CD, Gatekeeper, ingress, backup freshness
- tenant overview: namespace quota, pod restarts, HPA state, ingress errors
- policy overview: Gatekeeper denials by constraint and namespace
- cost overview: tenant namespace cost and unallocated cost
- change overview: Argo CD sync history and recent production applies

