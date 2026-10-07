# Change controls and production responsibilities

## Solo review model

The maintainer owns this lab, reviews their own PRs and deliberately approves
their own environment deployments. The protection script requires PRs, passing
Checks, an up-to-date branch and resolved conversations. It prohibits force push
and deletion on main, applies enforcement to administrators and requires linear
history. Solo PR approval count is zero so the owner can merge their own work.

`CODEOWNERS` identifies the maintainer but does not provide independent review of
the maintainer's own PR. Dev and prod require a deliberate approval by the owner;
self-review is allowed. GitHub administrators may be able to change/bypass
environment controls. The owner is inside this lab's trust boundary.

To use independent review, add an authorized collaborator/team, enable at least
one required approving review and required CODEOWNER review, prevent deployment
self-review and disable administrator bypass where supported. Keep responsibility
for repository settings, bootstrap IAM and production approval with separate
people. No collaborator is invited by this project.

## Control matrix

| Area | Implemented in this repository | Requires setup or enterprise ownership |
| --- | --- | --- |
| Source control | PR template, CODEOWNERS, SHA-pinned actions, Dependabot update PRs | Enforced GitHub settings and supported plan/visibility |
| CI | Unit/packaging/security tests, Terraform format/validate, TFLint, offline Checkov | Review exceptions and tool updates |
| AWS authentication | OIDC with exact immutable repo IDs and audience; trust initially disabled | Verify real subjects and enable only after protection checks |
| Privilege | Separate plan/deploy/runtime policies; bounded PassRole; no IAM mutation by application roles | Review live IAM behavior and account guardrails |
| State | KMS encryption, versioning, public-access block, TLS-only bucket policy and native locking | Bootstrap state migration, retention and recovery exercise |
| Release | Immutable package, numbered version, live alias, encrypted saved plan, age/SHA/run checks | Review the actual plan and approve the environment |
| Promotion | Prod checks that dev serves the current commit and content digest | Separate production account and independent approval |
| Logging | KMS log groups, 30-day retention, minimal access-log fields, ERROR execution logs | Existing API Gateway account role and sensitive-log review |
| Detection | Lambda/API alarms and X-Ray | Approved SNS destinations, on-call ownership and alert exercise |
| Recovery | Numbered versions and documented Terraform/CLI rollback | Verify rollback with a real deployed version |
| Teardown | Exact typed destroy confirmation, environment approval, retained bootstrap | Account-wide resource review and retained-resource cleanup |
| Audit | Git/PR/workflow history and release identity | Account CloudTrail, organization controls and durable audit retention |
| Edge security | HTTPS, CSP, frame protection, throttles and concurrency | AWS WAF, custom domain and access design where needed |
| Cost | Bounded traffic, short timeouts and explicit cleanup scope | CLI-configured budgets, notifications and cost review |

## Narrow wildcard permissions

CloudWatch `DescribeAlarms`, Logs `DescribeLogGroups` and X-Ray telemetry writes
require wildcard scope for the selected API operations. They are read-only or
telemetry writes and do not grant access to application secrets. The account-level
API Gateway logging role uses AWS's service-role policy only when explicitly
created; it is not assumable by GitHub and should be reused when already present.

KMS policies use `Resource = "*"` inside a **single-key policy**; this refers to
that key. IAM permissions refer to exact KMS key ARNs and encryption contexts.
State permissions select only the target environment's key/lock object. The plan
identity can write a lock object, which is required for native S3 locking, but
cannot write the state itself.

Security scan exceptions, if present, must identify the specific check, reason,
scope and alternative control. A clean scan with exceptions does not prove that
the account or service is production-ready.

## Scoped Checkov exceptions

Exceptions are inline on the relevant Terraform resources, not global skip lists.
The offline scan still enforces all other applicable checks.

| Check | Scope and reason | Alternative control or production requirement |
| --- | --- | --- |
| CKV_AWS_338 | Lambda/API log groups use 30-day lab retention | KMS encryption; organization-defined production audit retention |
| CKV_AWS_117 | Static-content Lambda needs no private network resources | Minimal runtime permissions; add network controls for private dependencies |
| CKV_AWS_116 | API invokes Lambda synchronously | API/Lambda alarms and explicit error responses; DLQ needed for asynchronous events |
| CKV_AWS_272 | AWS Signer is outside this first lab | Reviewed deterministic package, authenticated plan bundle; add signing for production requirements |
| CKV_AWS_59 | Deliberately public, fictional HTML page | Allowlisted routes, rejected writes; require authorization for private content |
| CKV_AWS_120 / CKV_AWS_225 | Managed API caching is disabled | Fresh release content and HTTP ETag revalidation |
| CKV2_AWS_51 | Lambda integration has no HTTPS backend requiring a client certificate | AWS service invocation permission scoped to API/stage/account |
| CKV_AWS_18 | No separate state audit-log bucket in the isolated lab | Production account audit/access logging is a setup prerequisite |
| CKV_AWS_144 | Single-region state | Versioned state and 90-day noncurrent retention; define regional DR separately |
| CKV2_AWS_62 | No state event-notification consumer configured | Supply an approved audit integration before production use |

## GitHub availability

Required deployment reviewers are supported on public repositories with GitHub
Free/Pro/Team. Private environment protections depend on the plan; independent
production review may require a suitable organization/Enterprise plan. See the
[GitHub environment documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

Run `scripts/configure_github.py --verify-only` after settings changes. The
`DEPLOYMENT_CONTROLS_READY` variable is a fail-closed setup guard, not an independent
security boundary against the repository owner. IAM trust and actual environment
branch restrictions enforce access.
