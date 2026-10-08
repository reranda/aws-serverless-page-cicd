locals {
  name   = "serverless-page-production"
  routes = toset(["GET /", "GET /index.html", "GET /health", "HEAD /", "HEAD /index.html", "HEAD /health"])
}

resource "aws_lambda_function" "page" {
  function_name                  = local.name
  role                           = var.runtime_role_arn
  handler                        = "handler.handler"
  runtime                        = "python3.13"
  architectures                  = ["arm64"]
  filename                       = "${path.module}/.build/page.zip"
  source_code_hash               = filebase64sha256("${path.module}/.build/page.zip")
  publish                        = true
  memory_size                    = 128
  timeout                        = 5
  reserved_concurrent_executions = 5
  description                    = "Git release ${var.release_sha}"
  logging_config {
    log_format = "JSON"
    log_group  = "/aws/lambda/${local.name}"
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.page.function_name
  function_version = aws_lambda_function.page.version
}

resource "aws_apigatewayv2_integration" "page" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.live.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_route" "page" {
  for_each           = local.routes
  api_id             = var.api_id
  route_key          = each.value
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.page.id}"
}

resource "aws_lambda_permission" "gateway" {
  for_each       = local.routes
  statement_id   = "Gateway${replace(replace(replace(each.value, " ", ""), "/", "Root"), ".", "Dot")}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.page.function_name
  qualifier      = aws_lambda_alias.live.name
  principal      = "apigateway.amazonaws.com"
  source_arn     = "${var.api_execution_arn}/$default/${split(" ", each.value)[0]}${split(" ", each.value)[1]}"
  source_account = var.account_id
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name}-lambda-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.page.function_name }
  alarm_actions       = [var.alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${local.name}-api-errors"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { ApiId = var.api_id, Stage = "$default" }
  alarm_actions       = [var.alarm_topic_arn]
}

