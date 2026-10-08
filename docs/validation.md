# Validation record

Validation date: 2026-10-08. Current mode: **private-lab**, private repository, approval controls deferred.

## Credential-free checks

The private-lab code update passed [GitHub CI](https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37755332734): 17 Python tests, deterministic ZIP packaging, Terraform formatting, validation of both Terraform roots, four mocked control runs, and the selected Checkov security baseline. Workflow YAML and shell steps were also checked locally; external Actions use full SHA pins.

Both provider locks were regenerated against signed HashiCorp publisher metadata for `linux_amd64` and `windows_amd64`, keeping AWS provider 6.68.0. The account owner confirmed successful Windows initialization with checksum verification enabled.

The original rebuild is recorded in [PR #2](https://github.com/reranda/aws-serverless-page-cicd/pull/2) and [its CI run](https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37731063758). Private mode and cross-platform locking were added in [PR #4](https://github.com/reranda/aws-serverless-page-cicd/pull/4).

## Bootstrap and OIDC — verified

The account owner's AWS CLI/Terraform output confirmed:

- Bootstrap created 20 resources with no changes or deletions.
- Local bootstrap state migrated to S3 at `bootstrap/terraform.tfstate`; all 20 resources remained in state, and a subsequent refresh/plan reported no changes.
- The existing GitHub OIDC provider was reused.
- Repository variables were configured for private lab mode without environment protections.
- The [OIDC diagnostic](https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37804480840) reported the exact immutable repository/main-branch subject and audience `sts.amazonaws.com`.
- Enabling CI trust updated only the two CI role trust policies: zero additions, two changes, zero deletions.
- The [plan-only run](https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37805360477) authenticated through OIDC, planned 17 application additions, and skipped Apply.

## First live application release — verified

[Deployment run 37806115128](https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37806115128) completed successfully. Its Plan and Apply jobs used their respective OIDC roles. Apply created 17 application resources, with no changes or deletions.

- Deployed source commit: `75ad96385234301a7b0ebde13712f57cb4a2f5a2`.
- [Page](https://7rui87ai19.execute-api.eu-west-2.amazonaws.com/) and [health endpoint](https://7rui87ai19.execute-api.eu-west-2.amazonaws.com/health).
- The smoke check verified HTML bytes exactly matched `content/index.html`, the HTML content type, release SHA header, health status/commit/page hash, the `nosniff` header, and a 404 for an unknown route.
- The post-apply Terraform plan returned no changes.
- The account owner's separate `curl.exe` health request returned HTTP 200 and the same release SHA.
- Observed page SHA-256: `5ca3fe306a1a24392fc92b828ab8333a994a339982c2073d9520751de9182c73`.
- The health response included CSP, HSTS, `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer` and `Cache-Control: no-store`.

The private workflow generates a fresh plan and applies it automatically for deploy/destroy. This release demonstrates operational separation of role permissions, not independent reviewer-enforced approval. Application state uses the isolated `production/terraform.tfstate` key.

## Follow-up acceptance checks — pending

- Read back API and Lambda logs and alarm states through AWS CLI.
- Confirm an SNS subscriber and test notification delivery.
- Publish a content-only change through PR, CI and a fresh release.
- Revert that content change and verify rollback through a fresh release.
- Exercise guarded application teardown and document retained bootstrap resources and costs.

Enforced branch and environment approval controls are intentionally deferred while this repository remains private on GitHub Free. They belong to the separate reviewed mode and are not claimed as active controls. The assistant has no direct AWS account session; bootstrap evidence comes from the account owner's CLI output, and application deployment evidence comes from the inspected GitHub Actions logs and supplied health response.
