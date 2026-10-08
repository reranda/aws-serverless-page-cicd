mock_provider "aws" {
  override_during = plan
  mock_resource "aws_apigatewayv2_api" {
    defaults = { id = "abc123" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::serverless-page-test-123456789012" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-2:123456789012:log-group:/aws/apigateway/serverless-page-production" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:eu-west-2:123456789012:serverless-page-production-alarms" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock-runtime" }
  }
}
variables {
  account_id   = "123456789012"
  state_bucket = "serverless-page-test-123456789012"
}
run "secure_bootstrap_defaults" {
  command = plan
  assert {
    condition     = alltrue([for role in aws_iam_role.ci : jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "CI-TRUST-DISABLED"])
    error_message = "CI trust must start disabled."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_acls && aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_public_access_block.state.ignore_public_acls && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    error_message = "State must block all public access."
  }
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State recovery requires versioning."
  }
  assert {
    condition     = aws_apigatewayv2_stage.live.default_route_settings[0].throttling_rate_limit == 5
    error_message = "Public page traffic must be throttled."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.state["plan"].policy).Statement[1].Action == ["s3:GetObject"]
    error_message = "Plan must not write application state."
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.deploy.policy, "iam:CreateRole") && !strcontains(aws_iam_role_policy.deploy.policy, "iam:PutRolePolicy")
    error_message = "Deployment must not manage IAM identities or policies."
  }
}
run "exact_oidc_subjects_when_enabled" {
  command = plan
  variables { enable_ci_trust = true }
  assert {
    condition     = jsondecode(aws_iam_role.ci["plan"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:reranda@39367723/aws-serverless-page-cicd@1409182803:environment:production-plan"
    error_message = "Planning trust must bind to the exact repository and environment."
  }
  assert {
    condition     = jsondecode(aws_iam_role.ci["deploy"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:reranda@39367723/aws-serverless-page-cicd@1409182803:environment:production"
    error_message = "Deployment trust must bind to the exact protected environment."
  }
}


run "private_lab_exact_main_subject" {
  command = plan
  variables {
    enable_ci_trust = true
    deployment_mode = "private-lab"
  }
  assert {
    condition     = alltrue([for role in aws_iam_role.ci : jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:reranda@39367723/aws-serverless-page-cicd@1409182803:ref:refs/heads/main"])
    error_message = "Private lab OIDC must bind to the exact repository and main branch without wildcard trust."
  }
  assert {
    condition     = output.github_config.runtime_role_arn == aws_iam_role.runtime.arn && output.github_config.deployment_mode == "private-lab"
    error_message = "The release configuration must include the runtime identity and selected mode."
  }
}
