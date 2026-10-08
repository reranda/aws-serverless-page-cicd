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

## Log delivery and alarm states — verified

The account owner's AWS CLI readback on 2026-10-08 showed records in both application log groups. The supplied Lambda platform reports had status `success`, used 42 MB of the configured 128 MB, and identified published version 1 through the `live` alias. The supplied API access records returned HTTP 200 for `GET /` and `GET /health`, with no integration errors. Both `serverless-page-production-api-errors` and `serverless-page-production-lambda-errors` were `OK`.

This verifies log delivery and the observed alarm states. It does not verify an alarm transition or notification delivery.

## Content update and rollback — verified

The content-only change in [PR #6](https://github.com/reranda/aws-serverless-page-cicd/pull/6) added one temporary paragraph. [PR #7](https://github.com/reranda/aws-serverless-page-cicd/pull/7) removed it after CI passed, restoring the original HTML bytes through a new commit.

| Release | Source commit | Lambda version | Deployment run | Page SHA-256 |
|---|---|---|---|---|
| Content update | `6b99a93bdddaabd36f918ac388e5234d71764686` | 2 | [37809048098](https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37809048098) | `1e090936ea78054a2a22f0a3ad42e9912c736dcc703b83ff5e7fbedff9374e4c` |
| Rollback | `67ae3e77cd32de96205b5771f9ec75f361800e7f` | 3 | [37810175688](https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37810175688) | `5ca3fe306a1a24392fc92b828ab8333a994a339982c2073d9520751de9182c73` |

Inspected Apply logs for both runs confirmed zero additions, two changes and zero deletions: the Lambda function and `live` alias were updated. Both runs passed the smoke check against the source HTML, release header and health data; their post-apply Terraform plans reported no changes. The account owner's separate health requests returned HTTP 200, the expected release commits and the page hashes above.

The rollback page hash matches the first release. Recovery used a fresh published version for the restored content, with `live` moved to version 3; it did not reset Git history or repoint the alias to version 1.

## SNS and alarm notification delivery — verified

The account owner's AWS CLI output and inbox confirmation on 2026-10-08 established:

- An email subscription was created on the bootstrap alarm topic and confirmed. Its endpoint and subscription identifier are intentionally omitted from this record.
- A direct SNS publish was accepted with message ID `5df1689f-3000-57b4-9126-0bdeed3f569c`; the account owner confirmed receipt of the test email.
- Both error alarms had actions enabled and targeted the expected alarm topic.
- Temporarily setting each alarm to `ALARM` produced a successful SNS action in CloudWatch alarm history, and the account owner confirmed receipt of the earlier alarm emails.
- The alarms still showed the injected `ALARM` state at the initial readback. The account owner explicitly restored both to `OK`, and the final AWS CLI readback confirmed both were `OK`.
- No recovery emails were expected: the configuration defines `alarm_actions` but no `ok_actions`.

This verifies the CloudWatch alarm action → SNS → email path for both alarms. The state overrides did not create application errors or test detection of a genuine metric threshold breach. The subscription was configured separately by the account owner; it is not managed by the application Terraform root.

## Follow-up acceptance checks — pending

- Exercise guarded application teardown and document retained bootstrap resources and costs.

Enforced branch and environment approval controls are intentionally deferred while this repository remains private on GitHub Free. They belong to the separate reviewed mode and are not claimed as active controls. The assistant has no direct AWS account session; bootstrap evidence comes from the account owner's CLI output, and application deployment evidence comes from the inspected GitHub Actions logs and supplied health response.
