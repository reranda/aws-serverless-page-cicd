locals {
  name = "${var.project}-${var.environment}"
}

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_338:Thirty-day lab retention bounds costs; production retention must follow the organization's audit requirements.
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 30
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_cloudwatch_log_group" "api" {
  #checkov:skip=CKV_AWS_338:Thirty-day lab retention bounds costs; production retention must follow the organization's audit requirements.
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = 30
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_lambda_function" "page" {
  #checkov:skip=CKV_AWS_117:Public static-content handler has no private-network dependencies; a VPC and NAT are unnecessary for this scoped lab.
  #checkov:skip=CKV_AWS_116:API Gateway invokes synchronously; an asynchronous dead-letter queue does not handle these requests.
  #checkov:skip=CKV_AWS_272:AWS Signer is a documented production extension; this lab verifies deterministic packages through reviewed encrypted release plans.
  function_name                  = local.name
  description                    = "Serve the HTML packaged with an immutable Git release"
  role                           = var.execution_role_arn
  filename                       = var.lambda_zip_path
  source_code_hash               = filebase64sha256(var.lambda_zip_path)
  handler                        = "handler.handler"
  runtime                        = "python3.13"
  architectures                  = ["arm64"]
  memory_size                    = 128
  timeout                        = 5
  reserved_concurrent_executions = 5
  publish                        = true
  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Reviewed API release; selects a numbered version"
  function_name    = aws_lambda_function.page.function_name
  function_version = var.alias_version_override == null ? aws_lambda_function.page.version : var.alias_version_override
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = var.rest_api_id
  parent_id   = var.root_resource_id
  path_part   = "{proxy+}"
}

locals {
  resources = { root = var.root_resource_id, proxy = aws_api_gateway_resource.proxy.id }
}

# Public read-only demonstration page. The handler allowlists paths and methods;
# authentication is required if the project is extended to private content.
resource "aws_api_gateway_method" "page" {
  #checkov:skip=CKV_AWS_59:This endpoint intentionally serves public fictional content; the handler restricts paths and rejects write methods.
  for_each             = local.resources
  rest_api_id          = var.rest_api_id
  resource_id          = each.value
  http_method          = "ANY"
  authorization        = "NONE"
  api_key_required     = false
  request_validator_id = aws_api_gateway_request_validator.page.id
}

resource "aws_api_gateway_request_validator" "page" {
  name                        = "${local.name}-parameters"
  rest_api_id                 = var.rest_api_id
  validate_request_parameters = true
  validate_request_body       = false
}

resource "aws_api_gateway_integration" "page" {
  for_each                = local.resources
  rest_api_id             = var.rest_api_id
  resource_id             = each.value
  http_method             = aws_api_gateway_method.page[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_alias.live.invoke_arn
  timeout_milliseconds    = 10000
}

resource "aws_api_gateway_gateway_response" "error" {
  for_each      = toset(["DEFAULT_4XX", "DEFAULT_5XX"])
  rest_api_id   = var.rest_api_id
  response_type = each.key
  response_parameters = {
    "gatewayresponse.header.Content-Type"              = "'application/json'"
    "gatewayresponse.header.Cache-Control"             = "'no-store'"
    "gatewayresponse.header.X-Content-Type-Options"    = "'nosniff'"
    "gatewayresponse.header.X-Frame-Options"           = "'DENY'"
    "gatewayresponse.header.Strict-Transport-Security" = "'max-age=31536000; includeSubDomains'"
  }
  response_templates = { "application/json" = "{\"message\":\"Request could not be completed\",\"requestId\":\"$context.requestId\"}" }
}

resource "aws_api_gateway_deployment" "page" {
  rest_api_id = var.rest_api_id
  triggers = {
    configuration = sha1(jsonencode({
      resources    = local.resources,
      methods      = aws_api_gateway_method.page,
      integrations = aws_api_gateway_integration.page,
      responses    = aws_api_gateway_gateway_response.error
    }))
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "page" {
  #checkov:skip=CKV_AWS_120:Managed API caching is disabled for fresh versioned HTML and to avoid a dedicated cache charge; HTTP ETag revalidation is implemented.
  #checkov:skip=CKV2_AWS_51:Lambda proxy integration uses AWS service invocation; a client certificate for an HTTPS backend is not applicable.
  rest_api_id          = var.rest_api_id
  deployment_id        = aws_api_gateway_deployment.page.id
  stage_name           = var.environment
  xray_tracing_enabled = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId", extendedRequestId = "$context.extendedRequestId",
      status    = "$context.status", responseLength = "$context.responseLength",
      latency   = "$context.responseLatency", integrationLatency = "$context.integrationLatency"
    })
  }
}

resource "aws_api_gateway_method_settings" "page" {
  #checkov:skip=CKV_AWS_225:HTTP ETags handle revalidation; managed method caching is deliberately disabled in this lab.
  rest_api_id = var.rest_api_id
  stage_name  = aws_api_gateway_stage.page.stage_name
  method_path = "*/*"
  settings {
    metrics_enabled        = true
    logging_level          = "ERROR"
    data_trace_enabled     = false
    throttling_rate_limit  = 5
    throttling_burst_limit = 10
    caching_enabled        = false
  }
}

resource "aws_lambda_permission" "api" {
  statement_id   = "ApiGatewayStageOnly"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.page.function_name
  qualifier      = aws_lambda_alias.live.name
  principal      = "apigateway.amazonaws.com"
  source_arn     = "arn:aws:execute-api:${var.aws_region}:${var.expected_account_id}:${var.rest_api_id}/${var.environment}/*/*"
  source_account = var.expected_account_id
}

locals {
  alarms = {
    lambda-errors    = { namespace = "AWS/Lambda", metric = "Errors", statistic = "Sum", threshold = 0, dimensions = { FunctionName = local.name } }
    lambda-throttles = { namespace = "AWS/Lambda", metric = "Throttles", statistic = "Sum", threshold = 0, dimensions = { FunctionName = local.name } }
    api-errors       = { namespace = "AWS/ApiGateway", metric = "5XXError", statistic = "Sum", threshold = 0, dimensions = { ApiName = local.name, Stage = var.environment } }
  }
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  for_each            = local.alarms
  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = "Investigate using the operations runbook. Notifications need a configured SNS topic."
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.threshold
  period              = 60
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "duration" {
  alarm_name          = "${local.name}-lambda-duration"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = local.name }
  extended_statistic  = "p95"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 4000
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions
}
