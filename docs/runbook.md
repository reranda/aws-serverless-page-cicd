# CLI setup and deployment

These commands are intended for the maintainer's authenticated personal AWS
account. Use an AWS CLI named profile or IAM Identity Center session. Do not send
access keys, SSO tokens, state files or account-specific configuration to chat.

## 1. Review source and prerequisites

Review the implementation PR and CI results before merging. Keep the repository
private until the content and independent-lab scope are reviewed. GitHub Free
supports the required branch and environment approval features for **public**
repositories; private availability depends on the paid plan. The setup script
fails closed if GitHub cannot enforce the requested controls. Do not replace
required approval with an unenforced README checklist.

Install Git, GitHub CLI, AWS CLI v2, Terraform 1.16.5 and Python 3.13 from their
official sources. The examples below use PowerShell, one command per line.

```powershell
gh auth status
git clone https://github.com/reranda/aws-serverless-page-cicd.git
Set-Location aws-serverless-page-cicd
git switch main
git pull --ff-only
terraform version
aws --version
python --version
$env:AWS_PROFILE = "YOUR_PERSONAL_LAB_PROFILE"
aws sts get-caller-identity
aws iam list-open-id-connect-providers
aws apigateway get-account --region eu-west-2
```

Verify the account ID and the existing `token.actions.githubusercontent.com`
provider. This provider already exists in the earlier personal Terraform lab;
do not try to create it again. Inspect the regional `cloudwatchRoleArn`. If one
exists, reuse it. If none exists, explicitly opt in to Terraform managing the
account-wide logging role. Never overwrite another application's role blindly.

## 2. Bootstrap with GitHub trust disabled

Copy the sample inputs and edit only the local file. The real file is ignored.
Confirm project prefix, region, account and logging-role decision before planning.

```powershell
Copy-Item infrastructure/bootstrap/terraform.tfvars.example infrastructure/bootstrap/terraform.tfvars
# Edit terraform.tfvars locally. Leave enable_github_oidc = false.
terraform -chdir=infrastructure/bootstrap init
terraform -chdir=infrastructure/bootstrap plan -out=bootstrap.tfplan
# Review every resource, IAM policy and any account-wide change.
terraform -chdir=infrastructure/bootstrap apply bootstrap.tfplan
New-Item -ItemType Directory -Force build | Out-Null
terraform -chdir=infrastructure/bootstrap output -json | Out-File -Encoding utf8 build/bootstrap-outputs.json
```

The output is non-secret deployment metadata but contains account identifiers;
keep it local. Bootstrap creates separate dev/prod API containers, KMS keys and
identities. It does not publish a page or permit GitHub role assumption yet.

Move bootstrap state into its protected bucket after the first apply:

```powershell
Copy-Item infrastructure/bootstrap/backend.tf.example infrastructure/bootstrap/backend.tf
# Fill bucket and state KMS ARN from the private bootstrap output.
terraform -chdir=infrastructure/bootstrap init -migrate-state
terraform -chdir=infrastructure/bootstrap plan
```

The last command must show no unexpected changes. Keep a protected local recovery
copy until remote state and versioning are verified. `backend.tf`, local state and
plan files are ignored. Bootstrap uses a separate `bootstrap/terraform.tfstate`
key; application identities do not have access to it.

## 3. Configure GitHub change controls

The owner must run this using GitHub CLI. It configures main-branch PR and CI
requirements, squash merges, dev/prod approval gates, literal main-branch deployment
allowlists, read-only workflow defaults and Dependabot security updates. It reads
the settings back before enabling the release guard and stores the environment
metadata in repository variables. It creates no AWS access keys or GitHub secrets.

```powershell
python scripts/configure_github.py --bootstrap-output build/bootstrap-outputs.json
python scripts/configure_github.py --verify-only
gh workflow run oidc-claims.yml --ref main
gh run list --workflow oidc-claims.yml
```

Approve the diagnostic environment jobs through GitHub when they pause. Inspect
the safe OIDC subjects in their summaries and compare them with bootstrap's
`expected_oidc_subjects`. The workflow never prints the JWT.

If GitHub returns a feature/plan error, the release-ready flag remains false and
role trust stays disabled. Use a supported visibility/plan after reviewing the
repository, then repeat verification. Changing visibility is a separate owner
decision; this script does not make the repository public.

Now enable trust through another saved bootstrap plan:

```powershell
# Set enable_github_oidc = true in the local bootstrap terraform.tfvars.
terraform -chdir=infrastructure/bootstrap plan -out=enable-oidc.tfplan
# Confirm only the intended trust-policy change.
terraform -chdir=infrastructure/bootstrap apply enable-oidc.tfplan
```

For a new repository, subjects include `OWNER@OWNER-ID/REPO@REPO-ID`. Custom OIDC
subject settings, transfers or renamed repositories must be checked explicitly;
do not widen trust with a wildcard to work around an assumption failure.

## 4. Deploy dev, then promote the same commit

```powershell
gh workflow run deploy.yml --ref main -f environment=dev
gh run list --workflow deploy.yml
gh run view RUN_ID
```

Review the **Plan** job, including changes, IAM scope, deletions and cost impact.
Approve **Apply** in the dev environment. The same saved binary plan is decrypted
and applied. The workflow checks the running HTML/release and requires a clean
post-deployment Terraform plan. Approval after six hours requires a fresh run.

Once dev is verified:

```powershell
gh workflow run deploy.yml --ref main -f environment=prod
```

The production workflow checks that dev serves the exact current commit and page
digest before creating the production plan. Review and approve the prod plan.
Both environments are demonstrations in one account; real production should use
separate AWS accounts and independent approvers.

## 5. Change content

```powershell
git switch -c page-update
# Edit content/index.html with public demonstration content.
python scripts/build.py --commit (git rev-parse HEAD)
git add content/index.html
git commit -m "Update the demonstration page"
git push -u origin page-update
gh pr create --base main --fill
```

Wait for Checks, review the diff and PR template, then squash merge. Redeploy dev
and verify the new release before promoting prod. The workflow always packages
its actual source SHA; a local preview package is not the deployment artifact.

## 6. Guarded application teardown

```powershell
gh workflow run destroy.yml --ref main -f environment=dev -f "confirmation=DESTROY dev"
```

Review the destroy plan and approve its environment gate. Use `DESTROY prod` for
the production demonstration environment. The concurrency group prevents apply
and destroy from racing for the same environment.

State storage, KMS keys, IAM roles, API containers and any account-wide logging
configuration remain. See [operations](operations.md) for retention and final
cleanup. No workflow destroys bootstrap automatically.

## Local infrastructure checks

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-tools.txt
.venv\Scripts\python -m unittest discover -s tests -v
.venv\Scripts\python scripts/build.py --commit (git rev-parse HEAD)
terraform fmt -check -recursive
terraform -chdir=infrastructure/bootstrap init -backend=false -lockfile=readonly
terraform -chdir=infrastructure/bootstrap validate
terraform -chdir=infrastructure/app init -backend=false -lockfile=readonly
terraform -chdir=infrastructure/app validate
.venv\Scripts\checkov --config-file .checkov.yaml
```

Checkov runs offline: platform downloads, result uploads and external modules
are disabled. It uses local policies and documented, scoped exceptions.
