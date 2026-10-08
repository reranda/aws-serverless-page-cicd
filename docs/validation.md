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

Record the confirmed outcomes and CI run link here before declaring the implementation validated.

## Live acceptance checks — pending

No AWS session is connected to the assistant. The rebuild has not created AWS resources or configured GitHub administration settings.

- Bootstrap state migrated to the separate remote key and verified.
- Branch and environment controls applied and read back with local administrator CLI.
- Initial plan reviewed, Apply approved, and API returns the exact HTML plus correct release SHA.
- API access logs and function logs arrive; error alarms deliver to the confirmed SNS subscriber.
- Repeat plan reports zero changes.
- A content-only PR changes the published page after a fresh reviewed release.
- A Git revert restores the previous content through the same approval process.
- Reviewed application destroy removes resources; retained bootstrap resources and costs documented.

