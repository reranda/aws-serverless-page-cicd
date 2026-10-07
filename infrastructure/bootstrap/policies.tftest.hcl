mock_provider "aws" {
  mock_resource "aws_api_gateway_rest_api" {
    defaults = { id = "api123abc", root_resource_id = "root123abc" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::slpage-tfstate-123456789012-eu-west-2" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-2:123456789012:key/11111111-1111-1111-1111-111111111111" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/slpage-dev-runtime" }
  }
}

variables {
  expected_account_id                      = "123456789012"
  existing_api_gateway_cloudwatch_role_arn = "arn:aws:iam::123456789012:role/existing-api-logs"
}

run "bootstrap_trust_starts_disabled" {
  command = apply
  assert {
    condition     = endswith(jsondecode(aws_iam_role.deploy["dev"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"], ":disabled")
    error_message = "GitHub must not assume deployment roles before change controls are verified."
  }
  assert {
    condition     = alltrue([for policy in aws_iam_policy.deploy : length(policy.policy) <= 6144])
    error_message = "Deployment managed policies exceed the AWS 6,144-character limit."
  }
  assert {
    condition     = alltrue([for policy in aws_iam_policy.plan : length(policy.policy) <= 6144])
    error_message = "Plan managed policies exceed the AWS 6,144-character limit."
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_policy.plan["dev"].policy).Statement :
      !contains(statement.Action, "s3:PutObject") || try(endswith(statement.Resource, ".tflock"), false)
    ])
    error_message = "The plan role must not write Terraform state; only the native lock object may be written."
  }
}

run "exact_trusted_subjects" {
  command = apply
  variables { enable_github_oidc = true }
  assert {
    condition     = jsondecode(aws_iam_role.plan["dev"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:reranda@39367723/aws-serverless-page-cicd@1409182803:ref:refs/heads/main"
    error_message = "Plan OIDC trust must select this immutable repository and main branch exactly."
  }
  assert {
    condition     = jsondecode(aws_iam_role.deploy["prod"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:reranda@39367723/aws-serverless-page-cicd@1409182803:environment:prod"
    error_message = "Production trust must select this immutable repository and environment exactly."
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_policy.deploy["dev"].policy).Statement :
      !contains(statement.Action, "iam:PassRole") || try(statement.Condition.StringEquals["iam:PassedToService"], "") == "lambda.amazonaws.com"
    ])
    error_message = "PassRole must be constrained to the Lambda service."
  }
}
