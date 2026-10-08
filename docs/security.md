# Controls and scope

This is an anonymous public **read-only demonstration page**. It has no login, personal/customer data, database, writable API, or runtime GitHub access. Use a dedicated AWS lab account. It is not a complete production landing zone.

The currently selected [private lab mode](private-lab.md) keeps the source repository private and explicitly defers branch/environment approval enforcement. Its exact branch-bound OIDC subject replaces environment subjects, and a manually dispatched deploy applies its generated plan automatically. The environment approval and administrator-enforcement statements below describe the separate reviewed mode, not active private lab controls.

## Enforced in code

- Exact OIDC audience and environment subjects; trust disabled by default.
- Separate plan/deploy roles; plan cannot write state except its lock file.
- Deployment has no IAM identity/policy management, only `PassRole` to the pre-created Lambda runtime identity.
- Deployment Lambda permissions are restricted to one function and its versions; API writes target this API's integration and route paths. The API container is managed by bootstrap.
- Runtime IAM allows only writes to its own function log group. No wildcard AWS managed runtime policy.
- State encryption, versioning, public access blocks, TLS-only policy, native locking and bootstrap deletion protection.
- Full commit pins for Actions, committed Terraform provider checksum locks and weekly Dependabot update PRs.
- Saved-plan apply, same-run artifact, current-main guard, expiry and serialized releases.
- Public traffic throttle of 5 requests/second with burst 10, Lambda concurrency 5, timeout 5 seconds.
- Read-only route allowlist and exact API/account-bound Lambda invocation permissions.
- No JavaScript or external assets in the example page; inline CSS is authorized using its SHA-256 CSP hash.
- JSON access/function logging, retention, error alarms, and exact source account/alarms on the SNS topic policy.

## Account controls configured separately

`scripts/configure_github.py` applies and verifies branch/environment protections through an administrator's local GitHub CLI. The assistant's connector does not expose these writes. In team mode, require one independent PR approval, require the `Checks` context from the GitHub Actions app (ID 15368), dismiss stale reviews, resolve conversations, block force pushes/deletions, and enforce admins. Production approval prevents self review and bypass. CODEOWNERS identifies ownership; code owner approval itself is not required because the single owner authors this project's PRs.

Both OIDC subjects rely on verified GitHub environment policies allowing only the `main` **branch**, not tags or pull request merge refs. A readiness repository variable is an operational switch, not a replacement for those protections. Administrators capable of changing GitHub settings or bootstrap IAM remain trusted actors. This is not a sandbox for hostile administrators.

## Scanner scope

Checkov runs a specific baseline: S3 encryption, private ACL, versioning and four public access block settings; OIDC trust conditions; and IAM policies preventing broad write permissions/resource wildcards. The selected IDs are recorded in `.checkov.yaml`. Terraform mock tests additionally check exact OIDC subjects, disabled initial trust, read-only state access, immutable releases, invocation bounds and public throttling. This targeted baseline does not claim to pass every Checkov rule or certify the account. Mock tests validate configuration without proving real AWS IAM/API behavior.

## Explicit limits and next production decisions

- HTTP APIs use managed HTTPS and support this response format. Direct AWS WAF integration is not provided here. For an enterprise internet service, make a separate decision on REST API/WAF or a supported edge architecture and custom domain. Do not place confidential content behind this anonymous endpoint.
- No private VPC or NAT is needed for a function reading local content. VPC attachment would add no protection to the public API by itself.
- CloudWatch log groups and SNS use service defaults. S3 uses SSE-S3. Customer-managed KMS keys, private network endpoints and central log archival are organization-specific extensions, not claims of this lab.
- The SNS topic contains operational alarm notifications and is not configured with a customer-managed encryption key. Human notification delivery needs a confirmed subscriber and a test.
- Binary plans/state can expose resource attributes. Keep repository/artifact/state access restricted. Public repository approval eligibility does not make plan contents confidential; do not deploy secrets from this public showcase.
- No AWS deployment has been performed during the rebuild. First live deployment must verify IAM coverage, API logging delivery, smoke tests, alarms, a repeat no-change plan, rollback and teardown.
- The `live` alias targets a published version. A first deployment can have a brief propagation window while API routes and permissions are created. Changes to multiple cloud resources are not an atomic transaction. This project does not implement canary release or multi-region recovery.
- The lab has one application environment. Add separately isolated dev/staging accounts/state before a real enterprise rollout; an environment named `production` alone does not provide that separation.

Primary references: [HTTP API Lambda integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html), [HTTP API logging](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-logging.html), [GitHub environment protection and plan eligibility](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments), [Terraform S3 locking and IAM permissions](https://developer.hashicorp.com/terraform/language/backend/s3).

