# Releases, recovery and teardown

The current private lab uses `private-lab.yml` with no approval gate. Follow [the private lab guide](private-lab.md) for setup, plan-only runs, deployment and teardown. Environment approval commands below apply only after switching to reviewed mode.

## Update the Git page

```powershell
git switch main
git pull --ff-only
git switch -c content/update-page
# Edit content/index.html.
git add content/index.html
git commit -m "Update the serverless demonstration page"
git push -u origin content/update-page
gh pr create --base main --fill
```

CI tests the actual ZIP and Terraform controls without AWS credentials. Merge the PR, then dispatch `private-lab.yml` on `main` with `operation=deploy`. This generates a fresh plan and applies it automatically. Use `operation=plan` for a plan-only run. Planning uses a read role (it may write/delete only the state lock); Apply uses a separate deployment role. In reviewed mode, dispatch `release.yml` instead; Apply waits for environment approval.

Inspect the Plan job and `plan.txt` from the matching run. In reviewed mode, the reviewer must do this before approving Apply. Saved plans can contain sensitive infrastructure data; artifacts are restricted to repository access and retained for one day. Do not put secrets into Terraform inputs. GitHub encrypts stored artifacts, but this project does not add application-level artifact encryption.

## Approve through CLI after reviewing

```powershell
gh api repos/reranda/aws-serverless-page-cicd/actions/runs/RUN_ID/pending_deployments
```

Identify the waiting **production** environment ID from that response. Create a temporary `approval.json`:

```json
{"environment_ids":[123456],"state":"approved","comment":"Reviewed the saved plan for this run."}
```

```powershell
gh api --method POST repos/reranda/aws-serverless-page-cicd/actions/runs/RUN_ID/pending_deployments --input approval.json
Remove-Item approval.json
```

Use the real run and environment ID. Approval comes from the authorized reviewer account. In team mode, the initiator cannot approve; GitHub enforces this. A plan older than six hours or a changed main branch requires a new run. Saved plans also fail if remote state changed after planning.

## Roll back

Revert the faulty content or infrastructure change in a new branch, open a PR, merge, and run a new deployment. This produces a fresh published Lambda version for the reverted content and moves the `live` alias. Reviewed mode additionally requires deployment approval. There is no automatic rollback. If smoke verification fails, inspect the logs and stop further release activity until the cause is known.

```powershell
aws logs tail /aws/lambda/serverless-page-production --since 15m --region eu-west-2
aws logs tail /aws/apigateway/serverless-page-production --since 15m --region eu-west-2
aws cloudwatch describe-alarms --alarm-name-prefix serverless-page-production --region eu-west-2
```

Logs do not include HTML contents, request bodies or query strings. AWS-generated diagnostic records may contain execution metadata. Keep log access restricted.

## Subscribe to alarms

Terraform creates the alarm topic and policy. To deliver alerts to an email address you control:

```powershell
aws sns subscribe --topic-arn TOPIC_ARN_FROM_PROJECT_CONFIG --protocol email --notification-endpoint YOUR_EMAIL_ADDRESS --region eu-west-2
```

Confirm the subscription in your inbox and test it. A topic without a confirmed subscriber does not deliver human notifications. This command is intentionally performed by the account owner; no subscription or email is sent automatically by the assistant.

## Destroy application resources

```powershell
gh workflow run private-lab.yml --ref main -f operation=destroy -f "confirmation=DESTROY serverless-page-production"
```

Private lab destroy plans and applies automatically. For reviewed mode, use `release.yml` and review and approve the destroy plan. Destroy removes the function, live alias, Lambda permissions, API integration/routes and alarms. The bootstrap API container/default stage, IAM roles, logs, SNS topic and state bucket remain. With no routes, the endpoint returns 404. Retained logs, versions of state objects and any other residual resources can still incur costs.

Bootstrap teardown is a separate owner task. Disable `enable_ci_trust` and the GitHub readiness variable first. Review a bootstrap destroy plan and handle the state bucket separately: `prevent_destroy` and versioned contents deliberately block casual deletion. Do not remove the bucket storing the state of resources you still need to manage. This project never automatically deletes its backend.

## Coordinate operations

The GitHub concurrency group serializes releases and destroy runs. S3 lock files coordinate Terraform state across clients. Avoid changing bootstrap settings during an application release; the roots use different state locks. Throttles and reserved concurrency are operational limits, not guaranteed spending caps. Set an account budget through your established AWS CLI/account process and inspect costs after the lab.

