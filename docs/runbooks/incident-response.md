# Runbook — Incident Response

> Platform-level incident. Use when something is broken in a way that affects multiple tenants, or any tenant in a customer-impacting way.

## Severity matrix (platform-side)

| Sev | Trigger | Time to acknowledge | Time to update |
| --- | --- | --- | --- |
| Sev-1 | Cluster unreachable; ingress fully down; multiple tenants impacted | 5 min | 15 min |
| Sev-2 | One tenant fully down; observability lost; Argo CD wedged | 15 min | 30 min |
| Sev-3 | Single workload broken; intermittent issue; degraded but functional | 30 min | 60 min |
| Sev-4 | Heads-up: a control failed open; backlog of audit findings | next business day | n/a |

The customer-facing Sev definitions live in the org-wide incident wiki — this matrix is what the platform-on-call uses to triage.

## On-call quick links

- PagerDuty escalation: `platform-engineering`
- Argo CD: `https://argocd.platform.example.bank` (SSO)
- Grafana: `https://grafana.platform.example.bank` (SSO)
- Cluster bastion: `bastion.platform.example.bank` (SSH via the platform jump host; MFA-enforced)
- Status page: `status.platform.example.bank`

## Step 1 — Acknowledge and assess

```bash
# Confirm the cluster is alive.
gcloud container clusters describe <cluster> --region <region> --format='value(status)'

# Confirm Argo CD is reachable.
kubectl -n argocd get deploy

# Confirm critical Applications are Healthy + Synced.
argocd app list -o name | xargs -I{} argocd app get {} --output json | jq -r '.metadata.name + " " + .status.sync.status + " " + .status.health.status'
```

If any of these fail, escalate to Sev-1.

## Step 2 — Decide who owns it

Use this table. Wrong call wastes the first 10 minutes.

| Symptom | Owner | Why |
| --- | --- | --- |
| `gcloud container clusters describe` returns DEGRADED / ERROR | Google support + platform | Control-plane issue |
| Cluster healthy but Argo CD wedged (`argocd app sync` hangs) | Platform | Argo CD repo-server / controller issue |
| Argo CD healthy but a platform Application stuck `OutOfSync` | Platform | Chart or values issue; reconciliation failing |
| A tenant Application stuck OutOfSync | Tenant + platform liaison | Tenant chart issue; we help diagnose |
| Ingress returns 5xx for one host | Tenant first, ingress-nginx logs second | Likely a tenant deployment |
| Ingress returns 5xx for **all** hosts | Platform | ingress-nginx itself or LB |
| Pods stuck Pending across multiple tenants | Platform | Node-pool / autoscaler issue |
| Pods stuck Pending in one namespace | Tenant + ResourceQuota check | Likely a quota or nodeSelector mismatch |
| Gatekeeper webhook denying everything | Platform — emergency | See "Gatekeeper open-failure" below |

## Step 3 — Common diagnostics

### Argo CD repo-server hung

```bash
kubectl -n argocd rollout restart deploy/argocd-repo-server
# Wait for both replicas Ready; retry the sync.
```

### A platform Application stuck OutOfSync after a chart bump

1. `argocd app diff <app>` — see what changed.
2. If the diff is benign drift (annotation churn), set `ignoreDifferences` in the Application. PR the change.
3. If the diff is an upgrade gone wrong: `argocd app rollback <app> <previous-history-id>`.

### A tenant pod is denied at admission

- Gatekeeper denial: read the deny message. The Constraint name is logged. Walk the tenant to the `policies/opa/templates/*.yaml` and explain.
- Pod Security Standards denial: namespace has `pod-security.kubernetes.io/enforce: restricted` (this is correct). Tenant fixes `securityContext`.

### Backup for GKE — restore

```bash
# List recent backups for the baseline plan.
gcloud beta container backup-restore backups list \
  --location <region> --backup-plan <cluster>-baseline

# Restore a specific namespace from a backup. Requires a restore plan
# (separate Terraform resource) — confirm one exists for the target cluster.
gcloud beta container backup-restore restores create <restore-id> \
  --location <region> \
  --restore-plan <restore-plan-id> \
  --backup <backup-id> \
  --namespaces=<ns>
```

The restore plan deliberately lives outside the cluster module so a destructive change to the cluster cannot also wipe the restore configuration.

## Step 4 — Communicate

| Audience | Channel | When |
| --- | --- | --- |
| Platform Slack | `#platform-incidents` | Immediately, in the on-call thread |
| Affected tenants | per-tenant Slack channel or paged tenant lead | Within first communication window (15 min Sev-1) |
| Status page | public | Sev-1 only, after first 15 min |
| Compliance / Risk | DORA-major-incident threshold (≥ 2h Sev-1 or material customer impact) | Within 1 hour; DORA Art.19 reporting kicks in |

Templates for each message live in the org-wide incident wiki.

## Step 5 — Stabilise

- Prefer **rollback** to forward-fix during the incident. Argo CD app rollback, Terraform Cloud workspace previous-apply, Helm rollback — whichever applies.
- If a Sentinel hard-mandatory gate is blocking the fix, the org-admin override is logged. Use it; the audit trail is the point.
- If Gatekeeper itself is the cause and is denying critical workloads, see **Gatekeeper open-failure** below.

## Step 6 — Resolve and close

- Confirm the originally-reported symptoms are gone.
- Confirm related metrics in Grafana are back in green band.
- Mark the PagerDuty incident resolved.
- Update the public status page (Sev-1 only) within 30 min of resolve.

## Step 7 — Post-mortem

Sev-1 and Sev-2 require a written post-mortem within 5 business days. Template:

1. **Summary.** One paragraph, plain language, customer-impact framing.
2. **Timeline.** UTC, minute-resolution. Include the first signal, first acknowledgement, first comms, mitigation steps, resolution.
3. **Root cause.** Not "what failed" — *why* it could fail. Stop at 5 whys or when the answer is process / structure, not blame.
4. **What we did well.** Resist the urge to skip this.
5. **What we'd do differently.** Action items, each with an owner and a target date.
6. **How a Sentinel or Gatekeeper policy could have prevented this.** If yes, draft the policy in a follow-up PR. This is the most common omission.

Post-mortems are filed in `docs/post-mortems/YYYY-MM-DD-<slug>.md`. They are not blameless of process; they are blameless of *people*. The platform-engineering reviewer ensures the language reflects that.

## Gatekeeper open-failure (break glass)

If Gatekeeper's webhook is denying every workload — e.g. a Constraint bug, a malformed template, or the webhook pod is unreachable — production cannot accept any new pod until you intervene. This is by design (`validatingWebhookFailurePolicy: Fail`) and is *correct* outside an incident.

To unblock during an incident:

```bash
# Temporarily disable the validating webhook. AUDITED ACTION.
kubectl -n gatekeeper-system patch validatingwebhookconfiguration \
  gatekeeper-validating-webhook-configuration \
  --type='json' \
  -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'
```

You **must** then:

1. Page the security on-call so they know the gate is open.
2. Fix the underlying Constraint or webhook.
3. Re-enable: replace `Ignore` with `Fail` in the patch above.
4. Write up the break-glass use in the post-mortem.

Argo CD will see drift on the webhook and try to revert it. During the incident, set the corresponding Application to `selfHeal: false` and re-enable after the fix. Don't forget step 4.
