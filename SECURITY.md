# Security

This independent portfolio lab serves a deliberately public HTML page. Never
place credentials, tenant information, personal data, employer code or client
infrastructure in the content or Terraform configuration.

Use GitHub private vulnerability reporting if enabled on this repository.
Otherwise contact the maintainer through their public profile without publishing
exploit details or credentials in an issue. No separate security contact has been
invented for this lab.

Pull requests do not receive AWS credentials or OIDC permissions. AWS deployment
uses exact repository identities, protected main-branch workflows and environment
gates. Secrets, local state, binary plans, account-specific inputs and build files
are excluded from source. Stored release plans use KMS envelope encryption and
authenticated AES-GCM; artifact retention is one day.

This lab demonstrates production practices. Independent reviewers, account-level
audit controls, notification routing, budget alerts and operational ownership
must be supplied before using it as an enterprise service. See
[the control matrix](docs/controls.md).
