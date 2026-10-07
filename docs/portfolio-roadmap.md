# Portfolio labs before the website

Build and validate useful projects before adding them to the profile's Featured
Projects or constructing the website. Only completed, public, reviewed work should
appear as a finished showcase. Preserve the profile's Core Technologies and What
I Work On sections as the project list grows.

| Order | Showcase | Repository/scope | Evidence needed |
| --- | --- | --- | --- |
| Complete | Infrastructure as Code – AWS Environment | Existing `reranda/terraform-aws-cicd-lab`; avoid duplicating the same lab under a new name | Existing architecture and deploy/destroy lifecycle evidence |
| 1 | Serverless API Page Delivery | This repository: API Gateway, Lambda, Terraform and reviewed GitHub Actions | CI plus CLI bootstrap, initial deploy, page change, prod promotion, rollback and destroy |
| 2 | AWS Edge Security Architecture | New `aws-edge-security-architecture` built independently from scratch | CloudFront, private S3/OAC, WAF rules, HTTPS, logging, positive/negative origin tests and teardown |
| 3 | Secure AWS SFTP Architecture | New `aws-secure-sftp-architecture` with Terraform and AWS Transfer Family | SSH key authentication, isolated S3 prefixes, per-user roles, encryption, audit logs, upload/download and denied cross-user access |
| 4 | Microsoft 365 / Intune Security Lab | New `microsoft365-security-lab` in a dedicated test tenant | Fictional users/devices, MFA/Conditional Access design, Intune compliance, baseline policies and sanitized validation; licensing-aware scope |
| 5 | Cloud Migration Architecture | New `cloud-migration-architecture-lab` using a fictional workload | Discovery assumptions, migration choices, landing-zone/network design, cutover/rollback plan, costs and a small reproducible migration exercise |

## Reusable completion standard

Each repository needs a clear problem statement, a readable architecture, reviewed
implementation/configuration, security decisions, explicit costs, operations and
recovery instructions, and truthful validation results. A design-only project
must say that clearly. Do not label a policy draft or unrun plan as deployed work.

Use the serverless project's PR controls, OIDC pattern, pinned dependencies,
documentation structure and evidence discipline as a starting point. Adapt the
service-specific permissions and tests; do not share deployment roles or copy an
overly broad trust policy across repositories.

## Boundaries and prerequisites

The older `aws-edge-security-lab` remains aside; do not reuse its employer-derived
history or publish it as this new project. Keep `DevOps` private. All labs use new,
generic code, fictional data and independently provisioned resources. No employer
or client identifiers, address plans, credentials or configurations belong here.

SFTP endpoints can incur ongoing hourly costs and should be deployed only for the
validation exercise with deliberate teardown. M365 work needs a test tenant and
appropriate licensing, and must not change a production tenant. Migration work
needs an explicit fictional source workload and measurable validation criteria.

After these projects have usable evidence, update the profile's Featured Projects,
pin the strongest repositories, then build the website from the verified material.
