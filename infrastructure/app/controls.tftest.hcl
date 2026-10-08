mock_provider "aws" {
  override_during = plan
  mock_resource "aws_lambda_function" {
    defaults = {
      version    = "1"
      arn        = "arn:aws:lambda:eu-west-2:123456789012:function:serverless-page-production"
      invoke_arn = "arn:aws:apigateway:eu-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-2:123456789012:function:serverless-page-production/invocations"
    }
  }
  mock_resource "aws_lambda_alias" {
    defaults = {
      invoke_arn = "arn:aws:apigateway:eu-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-2:123456789012:function:serverless-page-production:live/invocations"
    }
  }
}
variables {
  account_id        = "123456789012"
  api_id            = "abc123"
  api_endpoint      = "https://abc123.execute-api.eu-west-2.amazonaws.com"
  api_execution_arn = "arn:aws:execute-api:eu-west-2:123456789012:abc123"
  runtime_role_arn  = "arn:aws:iam::123456789012:role/serverless-page-production-runtime"
  alarm_topic_arn   = "arn:aws:sns:eu-west-2:123456789012:serverless-page-production-alarms"
  release_sha       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
run "immutable_release_and_restricted_routes" {
  command = plan
  assert {
    condition     = aws_lambda_function.page.publish && aws_lambda_alias.live.function_version != "$LATEST"
    error_message = "The live alias must target a published Lambda version."
  }
  assert {
    condition     = aws_lambda_function.page.timeout <= 5 && aws_lambda_function.page.reserved_concurrent_executions == 5
    error_message = "Keep execution duration and concurrency bounded."
  }
  assert {
    condition     = alltrue([for route in aws_apigatewayv2_route.page : startswith(route.route_key, "GET ") || startswith(route.route_key, "HEAD ")])
    error_message = "Only read routes are permitted."
  }
  assert {
    condition     = alltrue([for p in aws_lambda_permission.gateway : p.source_account == var.account_id && !strcontains(p.source_arn, "*")])
    error_message = "Lambda invocation must be restricted to this account and exact API routes."
  }
  assert {
    condition     = aws_apigatewayv2_integration.page.payload_format_version == "2.0"
    error_message = "The handler expects HTTP API payload format 2.0."
  }
}

