# Portfolio before website construction

Finish and validate each repository before presenting it as a featured project. All materials must be independent lab work with sanitized example identities, domains and diagrams.

| Project | Deliverable | Evidence to capture |
|---|---|---|
| Infrastructure as Code – AWS Environment | Existing `terraform-aws-cicd-lab`: network/S3, OIDC workflow, recruiter-readable README | Architecture, successful deploy/destroy and empty state |
| AWS Serverless Page CI/CD | This new implementation: Terraform API Gateway/Lambda, HTML from Git, reviewed Actions release | PR checks, saved plan, approval, live release SHA, content update, rollback and teardown |
| AWS Edge Security Architecture | Separate Route 53, CloudFront and WAF lab with documented DNS, geo and rate-limit behavior | Request/response tests, WAF logs, architecture and teardown |
| Secure AWS SFTP Architecture | Transfer Family VPC endpoint, S3 home mappings, public keys and least-privilege IAM | Sanitized key authentication, home isolation and network restriction tests |
| Microsoft 365 / Intune Security Lab | Separate sanitized policy examples and test-device configuration guide | Enrollment, compliance, conditional access and policy exception tests |
| Cloud Migration Architecture | Independent Google Workspace → M365 sample migration design/runbook | Discovery, identity/data mapping, validation, cutover and rollback checklists |

The remaining rows are planned work, not implemented repositories. Complete the serverless lab first, then build the other projects one at a time. Build the portfolio website after the featured repositories have verified evidence.

