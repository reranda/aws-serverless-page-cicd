# CLI-only setup

For the currently selected **GitHub Free/private repository without approval gates**, follow [the private lab guide](private-lab.md). This guide's environment protection steps apply to the separate reviewed mode. Both modes use the same bootstrap resources and state migration process.

Use PowerShell 7, Python 3.13, Terraform 1.16.5, AWS CLI v2, Git, and GitHub CLI (`gh`). The checked-in provider locks select AWS provider 6.68.0; update them through a PR rather than deleting them.

The GitHub connector can publish code and PRs, but does not expose repository-administration writes or an AWS account session. These commands perform the remaining setup from your authenticated workstation. Do not paste access keys or tokens into chat or commit them.

## 1. Get the new implementation

For review before merging:

```powershell
git clone --branch rebuild/serverless-page-v2 https://github.com/reranda/aws-serverless-page-cicd.git
Set-Location aws-serverless-page-cicd
gh auth status
aws sts get-caller-identity
python --version
terraform version
```

AWS credentials must be a temporary/bootstrap administrator identity in your own lab account. Deployment credentials are created separately and cannot administer IAM. GitHub CLI needs repository administration, environment administration and variable write permissions for `scripts/configure_github.py`.

Do not use the earlier `serverless-v1` branch or apply its configuration. If any earlier attempt created AWS resources or state, inspect them first; never discard state and create a second owner for the same resource. This rebuild uses its own state bucket and names.

## 2. Review repository eligibility for approval controls

This repository remains private. GitHub Free, Pro and Team offer required environment reviewers only on **public** repositories. A private repository needs a plan supporting those controls. The script fails instead of silently dropping an approval requirement. Decide separately when to publish the portfolio repository; this project does not change visibility.

For team mode, choose an existing collaborator with write access who can independently review your PRs and deployments. A PR author cannot approve their own PR. In solo mode, the script explicitly sets PR approvals to zero while retaining required PRs/checks and permits self approval of environment deployments. Solo mode demonstrates the mechanics; it does not provide independent approval.

## 3. Bootstrap AWS with Terraform

Find your account ID and check the existing GitHub OIDC provider from the first Terraform project:

```powershell
$LabAccountId = aws sts get-caller-identity --query Account --output text
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${LabAccountId}:oidc-provider/token.actions.githubusercontent.com"
Copy-Item infrastructure/bootstrap/terraform.tfvars.example infrastructure/bootstrap/terraform.tfvars
```

Edit the new, ignored `terraform.tfvars`: replace the account ID and choose a unique bucket such as `serverless-page-tfstate-<account-id>-eu-west-2`. Keep `enable_ci_trust = false`. If the OIDC provider is absent, set `create_oidc_provider = true`. An existing provider remains owned by its original project; do not import it here unless deliberately transferring ownership.

```powershell
terraform "-chdir=infrastructure/bootstrap" init -lockfile=readonly
terraform "-chdir=infrastructure/bootstrap" plan "-out=bootstrap.tfplan"
terraform "-chdir=infrastructure/bootstrap" apply bootstrap.tfplan
python -c 'import pathlib,subprocess; pathlib.Path("project-config.json").write_bytes(subprocess.check_output(["terraform","-chdir=infrastructure/bootstrap","output","-json","github_config"]))'
```

Review the plan before applying. It creates a separate state bucket, API container and default stage, logs, runtime role, plan/deploy roles, and an alarm topic. It does not deploy a page yet. Log-delivery setup occurs here using the bootstrap administrator; CI does not receive account-wide log-policy administration.

The initial bootstrap uses local state only because its bucket does not exist yet. **Migrate it immediately, before leaving this workstation.** Create `infrastructure/bootstrap/backend.hcl` with your bucket and account:

```hcl
bucket = "serverless-page-tfstate-123456789012-eu-west-2"
key = "bootstrap/terraform.tfstate"
region = "eu-west-2"
encrypt = true
use_lockfile = true
allowed_account_ids = ["123456789012"]
```

```powershell
Copy-Item infrastructure/bootstrap/backend.tf.example infrastructure/bootstrap/backend.tf
terraform "-chdir=infrastructure/bootstrap" init -migrate-state "-backend-config=backend.hcl"
terraform "-chdir=infrastructure/bootstrap" state list
```

On future clones, create both bootstrap backend files and run `init "-backend-config=backend.hcl"` **before any bootstrap plan/apply**, so Terraform opens existing remote state instead of recreating resources. Bootstrap state uses `bootstrap/terraform.tfstate`; application state uses `production/terraform.tfstate`. CI has no access to bootstrap state.

## 4. Merge the implementation after CI and review

Review the new pull request, check CI, and merge using squash. If you enable branch protection before this first merge, ensure your chosen peer can approve it. The release workflow becomes dispatchable only after it is present on `main`.

```powershell
git switch main
git pull --ff-only
```

## 5. Configure and verify GitHub controls

Team mode, replacing the reviewer placeholder with the real collaborator's login:

```powershell
python scripts/configure_github.py --config project-config.json --reviewer PEER_GITHUB_LOGIN
```

For an explicitly chosen solo portfolio demonstration:

```powershell
python scripts/configure_github.py --config project-config.json --reviewer reranda --solo-lab
```

The script first disables releases, requires PRs/checks, blocks force pushes/deletions and admin bypass, limits both environments to the `main` branch, configures the deployment reviewer, verifies the result, and finally saves the non-secret bootstrap output as `PROJECT_CONFIG`. It does not invite users or alter visibility. If any API request fails, `DEPLOYMENT_CONTROLS_READY` stays false; fix the reported entitlement/permission issue and rerun.

## 6. Enable the exact OIDC trust

Only after step 5 succeeds, set `enable_ci_trust = true` in your local bootstrap `terraform.tfvars`.

```powershell
terraform "-chdir=infrastructure/bootstrap" plan "-out=bootstrap.tfplan"
terraform "-chdir=infrastructure/bootstrap" apply bootstrap.tfplan
```

In reviewed mode, set `deployment_mode = "reviewed"`. Trust allows only the exact `production-plan` and `production` environment subjects for the selected OIDC repository identity. Newer repositories include immutable owner/repository IDs. Verify the actual subject format before enabling trust; see the private lab guide for the branch-subject check. GitHub's verified environment branch policies restrict reviewed environment subjects to `main`.

## 7. Deploy and capture evidence

```powershell
gh workflow run release.yml --ref main -f operation=deploy
gh run list --workflow release.yml --limit 5
gh run view RUN_ID
gh run download RUN_ID --name reviewed-plan-RUN_ID --dir review-plan
Get-Content review-plan/plan.txt
```

Review `plan.txt` for changes and replacements. Approve the waiting `production` deployment through GitHub's review prompt, or use the GitHub CLI REST endpoint after reviewing the exact run (see the operating guide). Apply uses that saved plan, then verifies the page, health response, release SHA and a zero-change plan.

Get the URL from the workflow summary and check it with `curl.exe -i "https://API_ID.execute-api.eu-west-2.amazonaws.com/"`. Open it in a browser and capture the page, successful CI, plan, approval, and verified apply for the README. Record run URLs and date in `docs/validation.md`; do not claim live validation until these pass.

