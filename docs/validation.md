# Validation evidence

Status is recorded as evidence becomes available. Mock-provider tests validate
Terraform configuration and policies without provisioning AWS; they are not a
substitute for live deployment, permissions and recovery validation.

## Implementation checks

| Check | Result |
| --- | --- |
| Python packaged-handler, deterministic-build and release-control tests | 13 passed locally on 2026-10-07; CI uses Lambda's Python 3.13 runtime |
| Encrypted-plan roundtrip and tampering | Passed using real AES-GCM; only the KMS exchange was mocked |
| Terraform format | Passed locally |
| Terraform provider installation/checksums | HashiCorp-signed AWS 6.67.0 provider installed; canonical provider checksums retained |
| Offline Checkov | 122 passed, 0 failed, 12 scoped skips, 0 parsing errors on 2026-10-07 |
| Terraform validate and policy tests | Pending GitHub Actions; this workspace prevents the provider's local Unix socket |
| TFLint | Pending GitHub Actions |
| GitHub branch/environment protections | Prepared by CLI script; not yet activated/verified |

## Required live lifecycle evidence

- [ ] Personal-account and existing OIDC/logging prerequisite checks completed.
- [ ] Bootstrap plan reviewed/applied, state migrated and bucket recovery settings verified.
- [ ] GitHub protections read back successfully and real OIDC subjects confirmed.
- [ ] GitHub role trust enabled through a separate reviewed bootstrap plan.
- [ ] First dev deployment succeeds using the plan and deploy roles.
- [ ] Page digest, source SHA, headers and HTTP behavior verified through API Gateway.
- [ ] Terraform returns no changes after deployment.
- [ ] A page-change PR runs Checks, merges and deploys a new numbered version.
- [ ] Prod promotion verifies the exact current dev release.
- [ ] Known-good numbered-version rollback is tested and reconciled with Terraform.
- [ ] Alarms/logs verified; notification destination and alert exercise recorded if configured.
- [ ] Guarded destroy removes application resources and retained bootstrap resources are accounted for.

Add workflow/run links, sanitized HTTP results, relevant version/commit identifiers
and concise lessons learned. Do not upload state, decrypted plans, temporary
credentials, account identifiers, full logs or client/employer data as evidence.

The lab is not marked deployed or production-ready until the relevant live checks
have actually been performed.
