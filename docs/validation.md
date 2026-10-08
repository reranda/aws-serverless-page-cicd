# Validation record

Rebuild date: 2026-10-08.

## Credential-free checks

The rebuild runs:

```text
python -m unittest discover -s tests -v
python scripts/build.py --commit <full-40-character-sha>
terraform fmt -check -recursive
terraform init -backend=false -lockfile=readonly
terraform validate
terraform test
checkov --config-file .checkov.yaml
```

Confirmed locally: 12 Python tests passed; deterministic packaging passed; Terraform formatting passed; selected Checkov baseline: 21 passed, 0 failed, 0 skipped. Workflow YAML parsed and every external Action uses a full SHA pin.

Local Terraform schema validation/mock tests cannot run in this restricted runtime: the provider's Unix socket returns `operation not permitted`. GitHub-hosted CI is used for those checks. The dependency lock was independently checked using `terraform providers lock -platform=linux_amd64` against the signed HashiCorp release metadata.

Pull request: https://github.com/reranda/aws-serverless-page-cicd/pull/2
GitHub CI passed: https://github.com/reranda/aws-serverless-page-cicd/actions/runs/37731063758

Both Terraform roots validated successfully on the GitHub runner, and all three mocked Terraform control runs passed. These checks do not contact AWS or prove live IAM permissions.

## Live acceptance checks — pending

The subsequent private-lab update adds Windows and Linux locks generated from signed publisher metadata, an exact main-branch OIDC trust mode, configuration compatibility guards, and an OIDC subject diagnostic. Its local Python suite passes 17 tests, and Terraform formatting and workflow YAML checks pass. GitHub CI verifies provider-backed schema validation and four mocked Terraform runs before merge. Private mode deliberately defers branch/environment approval enforcement; the checklist below describes the later reviewed mode.

No AWS session is connected to the assistant. The rebuild has not created AWS resources or configured GitHub administration settings.

- Bootstrap state migrated to the separate remote key and verified.
- Branch and environment controls applied and read back with local administrator CLI.
- Initial plan reviewed, Apply approved, and API returns the exact HTML plus correct release SHA.
- API access logs and function logs arrive; error alarms deliver to the confirmed SNS subscriber.
- Repeat plan reports zero changes.
- A content-only PR changes the published page after a fresh reviewed release.
- A Git revert restores the previous content through the same approval process.
- Reviewed application destroy removes resources; retained bootstrap resources and costs documented.

