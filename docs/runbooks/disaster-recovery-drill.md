# Runbook — Disaster Recovery Drill

Use this runbook to prove that Backup for GKE is recoverable, not merely
configured.

## Scope

The drill restores one tenant namespace into a sandbox or recovery cluster
and validates that the workload, secrets, PVCs, and service wiring come back
as expected.

## Frequency

- Production: quarterly
- SOX in-scope tenants: at least twice per year
- After backup-plan or KMS changes: within 10 business days

## Prerequisites

- Backup for GKE baseline plan is enabled.
- Restore plan exists outside the cluster stack.
- Recovery cluster can access the same artifact registry and KMS keys.
- Tenant owner has approved the drill window.
- Security has confirmed the restored data classification is allowed in the recovery target.

## Steps

1. Select a tenant namespace and recent backup.

   ```bash
   gcloud beta container backup-restore backups list \
     --location <region> \
     --backup-plan <cluster>-baseline
   ```

2. Create a restore into the recovery namespace.

   ```bash
   gcloud beta container backup-restore restores create <restore-id> \
     --location <region> \
     --restore-plan <restore-plan-id> \
     --backup <backup-id> \
     --namespaces=<tenant-namespace>
   ```

3. Confirm namespace controls survived the restore.

   ```bash
   kubectl get ns <tenant-namespace> -o yaml
   kubectl -n <tenant-namespace> get resourcequota,limitrange,networkpolicy
   kubectl -n <tenant-namespace> get sa tenant-runtime -o yaml
   ```

4. Confirm workloads become ready.

   ```bash
   kubectl -n <tenant-namespace> get deploy,pod,pvc
   kubectl -n <tenant-namespace> wait --for=condition=Ready pod --all --timeout=10m
   ```

5. Validate application behavior with the tenant owner.

6. Record evidence in `docs/evidence/`:

   - backup ID
   - restore ID
   - namespace restored
   - start and finish time
   - validation commands
   - issues found

7. Destroy the restored namespace when the drill is complete and evidence is captured.

## Pass criteria

- Backup selected successfully.
- Restore completes without manual object editing.
- Restored pods reach Ready.
- Tenant owner confirms application-level smoke test.
- Evidence is captured and linked from the quarterly control review.

## Fail criteria

- Backup is older than the stated RPO.
- Restore requires undocumented manual steps.
- Workload Identity, NetworkPolicy, or secrets fail after restore.
- Tenant cannot perform a basic smoke test.

