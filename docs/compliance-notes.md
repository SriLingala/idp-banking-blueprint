# Compliance notes (v1.0 — placeholder)

This document maps the platform's controls to common regulatory frameworks.
Populated in v1.0 once the policy layers (Sentinel + OPA) land.

## Frameworks covered

- SOX (Sarbanes-Oxley) — change management, separation of duties, audit logs
- PCI-DSS v4 — segmentation, key management, logging, vulnerability management
- ISO 27001:2022 — Annex A control mapping
- DORA (EU Digital Operational Resilience Act) — operational resilience for financial entities

## Control-to-evidence map

| Framework | Control | How it's met | Evidence location |
| --- | --- | --- | --- |
| SOX | Change is authorised | PR + reviewer + Sentinel gate | GitHub + TFE audit |
| PCI 8 | Identify users | Workload Identity, no shared SAs | IAM audit |
| ISO A.8.16 | Monitoring activities | Cloud Audit Logs → SIEM | Cloud Logging |
| DORA Art.6 | ICT risk management | Tier-based isolation + runbooks | This repo |

(To be filled out in v1.0.)
