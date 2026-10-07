output "github_configuration" {
  description = "Non-secret deployment metadata; store as GitHub repository variables, never in public source."
  value = { for environment in local.environments : environment => {
    environment        = environment
    project            = var.project
    account_id         = var.expected_account_id
    region             = var.aws_region
    state_bucket       = aws_s3_bucket.state.id
    state_key_arn      = aws_kms_key.state.arn
    plan_key_arn       = aws_kms_key.environment[environment].arn
    logs_key_arn       = aws_kms_key.environment[environment].arn
    plan_role_arn      = aws_iam_role.plan[environment].arn
    deploy_role_arn    = aws_iam_role.deploy[environment].arn
    execution_role_arn = aws_iam_role.runtime[environment].arn
    rest_api_id        = aws_api_gateway_rest_api.app[environment].id
    root_resource_id   = aws_api_gateway_rest_api.app[environment].root_resource_id
  } }
}

output "expected_oidc_subjects" {
  value = {
    plan = "${local.oidc_prefix}:ref:refs/heads/main"
    dev  = "${local.oidc_prefix}:environment:dev"
    prod = "${local.oidc_prefix}:environment:prod"
  }
}

output "api_gateway_cloudwatch_role_arn" {
  value = var.manage_api_gateway_account ? aws_iam_role.api_gateway_logs[0].arn : var.existing_api_gateway_cloudwatch_role_arn
}
