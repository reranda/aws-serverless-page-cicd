output "github_config" {
  value = {
    region            = var.region, account_id = var.account_id, state_bucket = aws_s3_bucket.state.id,
    api_id            = aws_apigatewayv2_api.page.id, api_endpoint = aws_apigatewayv2_api.page.api_endpoint,
    api_execution_arn = aws_apigatewayv2_api.page.execution_arn,
    alarm_topic_arn   = aws_sns_topic.alarms.arn,
    plan_role_arn     = aws_iam_role.ci["plan"].arn, deploy_role_arn = aws_iam_role.ci["deploy"].arn
  }
}

