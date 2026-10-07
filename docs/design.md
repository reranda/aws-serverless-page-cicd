# Design and decisions

## A reviewed Git file becomes a published Lambda release

`scripts/build.py` packages exactly three files: the handler, the HTML page and a
release manifest. ZIP timestamps, file modes and entry ordering are deterministic.
The manifest contains the full source commit and the page SHA-256. The handler
verifies the packaged content when the execution environment starts.

GET and HEAD are supported for `/` and `/index.html`. `/health` reports the release
identity. Other paths return 404, and write methods return 405. Request paths
never become filesystem paths. HTML is UTF-8, limited to 256 KiB and sent with
CSP, frame protection, nosniff, HSTS and revalidation headers.

The handler has no application dependencies, repository token or runtime network
fetch. A page change is a code release with the same review and recovery process.

## REST API and alias

A Regional REST API is used because this portfolio sequence includes direct AWS
WAF integration and tracing. HTTP APIs cost less for simpler workloads, but do
not offer the same feature set. WAF is a future edge-security extension and is
**not enabled by this lab**.

The API invokes the `live` alias, which always selects a numbered Lambda version.
Terraform publishes a version when the package changes. The invocation permission
is scoped to the exact API, stage and AWS account. No Function URL is created.

The public page intentionally uses no user authentication. An API key would not
be an adequate authentication control. Private content requires an explicit
authorization design and corresponding tests before it is added.

## Bootstrap ownership and least privilege

Bootstrap creates the API containers, runtime identities, state bucket and KMS
keys. It may configure the regional API Gateway account logging role only through
an explicit opt-in after checking the existing setting with AWS CLI.

Application roles cannot change IAM policies, OIDC providers, the state bucket,
KMS policies or account settings. They operate on a known API ID and one resource
prefix. `iam:PassRole` selects only the environment's runtime role and Lambda
service. The runtime role can write its log streams and X-Ray telemetry; it does
not read GitHub, S3, secrets or arbitrary application data.

Plan roles can read infrastructure, read state and create/delete only the S3 lock
object. They cannot write the state object or change application resources.
Deployment roles can apply changes and write their environment's state.
Read APIs and X-Ray writes that require wildcard resource scope are documented
in [the control matrix](controls.md).

GitHub trust is disabled during initial bootstrap. It is enabled through a
separate reviewed bootstrap plan after GitHub protections are verified. New
repositories use immutable owner and repository IDs in OIDC subjects; this
repository's defaults match its actual IDs. A diagnostic workflow exposes only
safe identity fields so the real claims can be checked before enabling trust.

## Reviewed saved plans

PR CI has read-only repository permissions and no OIDC token or AWS identity.
AWS workflows are manually dispatched from main. One concurrency group serializes
deploy and destroy for each environment and does not interrupt an active apply.

The plan job builds the package, obtains its read-oriented identity and saves a
binary Terraform plan. It envelope-encrypts the plan and exact package/configuration
using a KMS data key and AES-256-GCM. The encryption context binds environment,
operation, source SHA, workflow run and creation time. Only ciphertext and its
envelope are stored as a one-day GitHub artifact.

After the environment gate, Apply obtains its own identity, decrypts that run's
artifact and checks its metadata. Plans older than six hours and runs whose main
commit changed are rejected. Apply executes the saved plan without replanning.
Terraform also checks the state lineage/serial and obtains the S3 state lock.

These controls reduce accidental or unauthorized changes within the lab's trust
model. The repository owner can alter settings and code. Independent ownership
and reviewers are needed for enterprise separation of duties.

## Observability

Lambda and API access logs use environment-specific KMS encryption and 30-day
retention. Access logs omit request bodies, headers and client addresses. API
execution logging is ERROR with data tracing disabled; execution errors can still
contain infrastructure metadata. Review logging behavior before adding sensitive
content. X-Ray is enabled for the API and Lambda.

Alarms cover function errors, throttles, API 5xx responses and function duration.
Notification actions are empty until an approved SNS topic is supplied. The
deployment verifies HTML bytes, release identity, headers, HEAD, errors and ETag,
then requires a Terraform plan with no remaining changes.

## Official references

- [API Gateway REST and HTTP feature comparison](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html)
- [Lambda Python ZIP packaging](https://docs.aws.amazon.com/lambda/latest/dg/python-package.html)
- [Supported Lambda runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)
- [GitHub OIDC subject formats](https://docs.github.com/en/actions/reference/security/oidc)
- [GitHub OIDC with AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [Deployment environment protection](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Terraform S3 backend locking](https://developer.hashicorp.com/terraform/language/backend/s3)
