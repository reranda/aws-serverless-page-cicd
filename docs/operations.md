# Operations, recovery and costs

## Diagnose through AWS CLI

Use the environment's project name (default `slpage-dev` or `slpage-prod`) and
your personal account profile. Values below are examples, not deployed endpoints.

```powershell
aws lambda get-alias --function-name slpage-dev --name live --region eu-west-2
aws lambda list-versions-by-function --function-name slpage-dev --region eu-west-2
aws logs tail /aws/lambda/slpage-dev --since 15m --region eu-west-2
aws logs tail /aws/apigateway/slpage-dev --since 15m --region eu-west-2
aws cloudwatch describe-alarms --alarm-name-prefix slpage-dev- --region eu-west-2
aws apigateway get-account --region eu-west-2
```

Use request IDs to correlate errors. Avoid exporting logs with infrastructure
identifiers or any future sensitive content into a public repository. A failed
post-deployment smoke check leaves the applied state intact and marks the workflow
failed; the workflow does not silently attempt rollback or destroy resources.

## Reviewed rollback through Terraform

Record the known-good alias version and its release identity before changes.
Use the current reviewed main infrastructure and its exact package as inputs,
then select an **existing published** version through `alias_version_override`.

Prepare the same backend and tfvars used by deployment from the private bootstrap
configuration. Run Terraform using a personal CLI identity authorized for this
environment. Do not share the resulting state or plan.

```powershell
# LOCAL_CONFIG_JSON contains the environment object from bootstrap output.
$env:CONFIG_JSON = $LOCAL_CONFIG_JSON
python scripts/prepare.py --environment dev --role deploy
python scripts/build.py --commit (git rev-parse HEAD)
terraform -chdir=infrastructure/app init -backend-config=../../build/backend.hcl -lockfile=readonly
terraform -chdir=infrastructure/app plan -var-file=../../build/app.auto.tfvars.json -var="alias_version_override=KNOWN_GOOD_VERSION" -out=../../build/rollback.tfplan
# Confirm the intended alias change and any other proposed resources before apply.
terraform -chdir=infrastructure/app apply ../../build/rollback.tfplan
```

Replace `KNOWN_GOOD_VERSION` with a numeric version. Obtain its manifest using a
CLI Lambda invocation of `/health`, or a retained sanitized release record, then
run the smoke script against the API with that expected manifest. A default deploy
will follow main again and clear the override; review and repair the faulty code
before doing so. Keep an emergency rollback override in a reviewed configuration
until a replacement is ready.

For an urgent incident, a personal operator can move the alias with
`aws lambda update-alias --function-name ... --name live --function-version ...`.
This creates Terraform drift. Record the incident and immediately reconcile the
desired version through a reviewed Terraform plan. Never substitute `$LATEST`
for a known-good numbered release.

Example CLI invocation to capture a version's health response:

```powershell
'{"httpMethod":"GET","path":"/health","headers":{}}' | Out-File -Encoding ascii build/health-event.json
aws lambda invoke --function-name slpage-dev --qualifier KNOWN_GOOD_VERSION --payload fileb://build/health-event.json --region eu-west-2 build/version-health.json
```

The response body contains a JSON-encoded release manifest. Extract `commit` and
`content_sha256` into a local expected-release file and pass it to
`python scripts/smoke.py --url ACTUAL_API_URL --release LOCAL_EXPECTED_RELEASE.json`.

## State recovery and cleanup

Native S3 locking is mandatory. Do not manually delete a lock while a Terraform
job is running. For a stale lock, confirm the owning workflow has finished and
use Terraform's force-unlock procedure with the exact lock ID after review.

The state bucket is versioned, KMS-encrypted and protected from Terraform destroy.
Restore state only after confirming resource reality, lineage and serial. Test
state recovery in a disposable environment before relying on it for production.

Application destroy removes Lambda, routes/stages, application log groups and
alarms. Bootstrap retains API containers, state versions, KMS keys and IAM roles.
This preserves recovery metadata and isolates account-level changes, but it is
not a full account cleanup and does not eliminate all charges.

Final bootstrap cleanup must review both environments and any shared API Gateway
logging dependency, export necessary sanitized evidence, revoke GitHub trust,
and make a separate explicit decision about destroying retained state/key material.
Do not remove the existing shared GitHub OIDC provider from the earlier lab.

## Cost controls and remaining costs

The runtime uses 128 MiB, a five-second timeout, reserved concurrency five and
API throttles of five requests/second with burst ten. These are service limits,
not a spending cap. Actual sustainable Lambda/API quotas vary by account; verify
them before deploying. A new AWS account may need a concurrency quota increase
or a lower reservation reviewed with corresponding load expectations.

Budget for three customer-managed KMS keys in bootstrap, CloudWatch alarms and
detailed metrics, log storage/ingestion, tracing, API requests, Lambda execution
and S3 state/version storage. An unused API container has no request traffic,
but retained KMS keys and stored data remain billable. Key deletion has a waiting
period. No NAT gateway, VPC interface endpoint, always-on compute or WAF is created.

Use the [AWS Pricing Calculator](https://calculator.aws/) and regional service
pricing before deployment. Set an AWS Budget using AWS CLI with an explicitly
chosen notification destination, and verify alert delivery. No contact address,
subscription or arbitrary monthly spending limit is invented by this repository.

Alarm actions default to empty. Add only approved existing SNS topic ARNs through
`alarm_actions`, review the plan and test notification delivery. This lab has no
working on-call notification until that is done.
