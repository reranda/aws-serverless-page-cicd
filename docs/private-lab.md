# Private repository lab without approval gates

This mode is explicitly chosen for the current GitHub Free/private-repository lab. It uses neither GitHub environments nor enforced PR/deployment approvals. The reviewed workflow remains available separately. Repository visibility stays private.

CI still runs on PRs and main. Releases are dispatched manually on main, use separate scoped planning/deployment roles, apply the exact saved plan from the same run, serialize operations, check current main and plan age, and verify the deployed release. These are useful lab controls, but there is no independent approval or enforced branch protection.

## Repair provider installation on Windows

Pull the update containing the Windows and Linux checksums. From the repository root, replace only the downloaded provider directory, preserving backend metadata, state and variables:

```powershell
git switch main
git pull --ff-only
Remove-Item infrastructure/bootstrap/.terraform/providers -Recurse -Force
terraform "-chdir=infrastructure/bootstrap" init "-lockfile=readonly"
```

If the provider directory does not exist, skip `Remove-Item`. The new lock was generated using `terraform providers lock -platform=linux_amd64 -platform=windows_amd64` against the publisher's signed release metadata. Keep checksum verification enabled. If a fresh installation still fails, inspect any global plugin cache or mirror configuration before proceeding; do not whitelist an unexplained package hash.

## Bootstrap configuration and initial plan

Keep your existing account, bucket, region and repository values. Set this value in your ignored `infrastructure/bootstrap/terraform.tfvars`, adding the line only if it is absent:

```hcl
deployment_mode = "private-lab"
```

Keep `create_oidc_provider = false` when reusing the existing provider, and `enable_ci_trust = false` until the subject and workflow configuration are verified.

```powershell
terraform "-chdir=infrastructure/bootstrap" plan "-out=bootstrap.tfplan"
```

Review the resources and IAM policies. Apply the saved plan only after reviewing it, then migrate bootstrap state immediately using the instructions in `setup.md` (the state key remains `bootstrap/terraform.tfstate`). The private application uses the same isolated application key `production/terraform.tfstate`.

## Verify the OIDC subject before enabling trust

After the new workflows are on main:

```powershell
gh workflow run oidc-check.yml --ref main
gh run list --workflow oidc-check.yml --limit 3
gh run view RUN_ID --log
```

The workflow prints only `sub` and `aud`, never the raw token or credentials. It does not access AWS. The expected branch subject for this new repository is:

```text
repo:reranda@39367723/aws-serverless-page-cicd@1409182803:ref:refs/heads/main
```

GitHub introduced immutable IDs for newer repositories. If the observed subject instead uses the legacy name-only form, set this ignored bootstrap variable before enabling trust:

```hcl
oidc_repository = "reranda/aws-serverless-page-cicd"
```

Use the observed repository portion exactly. Trust matches the exact main-branch subject and `sts.amazonaws.com`, never a wildcard. Both lab roles share that subject: their distinct IAM permission sets support operational separation, but there is no reviewer-enforced separation of authority.

## Configure repository variables

Export the updated bootstrap output after it is applied, using the Python helper command in `setup.md`, then run:

```powershell
python scripts/configure_private_lab.py --config project-config.json
```

This stores non-secret `PROJECT_CONFIG`, enables `LAB_DEPLOYMENT_READY`, and leaves `DEPLOYMENT_CONTROLS_READY` false. It creates no environments or protection rules and does not change visibility. Configuration starts disabled and stays disabled if setup fails.

After verifying the subject and variables, set `enable_ci_trust = true`, generate a new bootstrap plan and apply that plan. The updated output includes the Lambda runtime role and deployment mode required by the release workflow.

## Plan or deploy using GitHub Actions

For a plan with no application apply:

```powershell
gh workflow run private-lab.yml --ref main -f operation=plan
```

Inspect the Plan job and its artifact. To deploy:

```powershell
gh workflow run private-lab.yml --ref main -f operation=deploy
```

**Dispatching deploy generates a fresh plan and then applies it automatically. There is no waiting approval step.** It does not reuse the preceding plan-only run's plan. Dispatching destroy likewise plans and applies automatically and requires the exact confirmation:

```powershell
gh workflow run private-lab.yml --ref main -f operation=destroy -f "confirmation=DESTROY serverless-page-production"
```

Use the operating guide for smoke checks, logs, alarms and retained bootstrap resources. The reviewed `release.yml` workflow stays disabled in this mode. To adopt reviews later, explicitly switch bootstrap to `reviewed`, configure eligible branch/environment controls and verify the corresponding environment OIDC subjects.

Primary references: [GitHub OIDC in AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [Terraform cross-platform provider locking](https://developer.hashicorp.com/terraform/cli/commands/providers/lock).

