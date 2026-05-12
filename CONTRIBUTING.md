# Contributing

This is primarily a personal reference repo, but contributions are welcome.

## Before opening a PR

- Run `make fmt` — all Terraform must be canonical.
- Run `make validate ENV=dev` — must pass.
- If you change behaviour, write or update an ADR in `docs/adr/`.
- If you change inputs/outputs, update the module README.

## What good PRs look like

- A short PR description that links to the ADR or issue it addresses.
- A diff that's easy to read on one screen. Big rewrites are easier to review as a sequence of small PRs.
- A note in the description if the change requires re-running `terraform apply` or affects the audit story.

## What we won't merge

- Multi-cloud abstractions. This repo is GCP-only by design.
- Hardcoded secrets, even examples. Use Vault references or KMS.
- Removal of audit logging, NetworkPolicy, or Pod Security Standards. These are non-negotiable defaults; if you need an exception, document it in an ADR.

## Filing issues

Please include:
- Terraform version (`terraform version`)
- Provider versions (`terraform providers`)
- What you ran
- What you expected
- What actually happened (with the redacted plan/error output)
