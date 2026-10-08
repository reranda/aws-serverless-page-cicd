locals {
  name        = "serverless-page-production"
  account_arn = "arn:aws:iam::${var.account_id}"
  lambda_arn  = "arn:aws:lambda:${var.region}:${var.account_id}:function:${local.name}"
  oidc_arn    = "${local.account_arn}:oidc-provider/token.actions.githubusercontent.com"
  state_key   = "production/terraform.tfstate"
  api_arn     = "arn:aws:apigateway:${var.region}::/apis/${aws_apigatewayv2_api.page.id}"
  roles       = { plan = "production-plan", deploy = "production" }
}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "tls" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Deny", Principal = "*", Action = "s3:*",
    Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }] })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_apigatewayv2_api" "page" {
  name          = local.name
  protocol_type = "HTTP"
}
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 30
}
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = 30
}
resource "aws_sns_topic" "alarms" {
  name = "${local.name}-alarms"
}
resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Sid    = "CloudWatchAlarms", Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" },
    Action = "sns:Publish", Resource = aws_sns_topic.alarms.arn,
    Condition = {
      StringEquals = { "aws:SourceAccount" = var.account_id },
      ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:${local.name}-*" }
    }
  }] })
}

resource "aws_iam_role" "runtime" {
  name = "${local.name}-runtime"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" }
  }] })
}
resource "aws_iam_role_policy" "runtime" {
  name = "write-own-logs"
  role = aws_iam_role.runtime.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"],
    Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
  }] })
}

resource "aws_iam_role" "ci" {
  for_each             = local.roles
  name                 = "${local.name}-${each.key}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = local.oidc_arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = var.enable_ci_trust ? (var.deployment_mode == "private-lab" ? "repo:${var.oidc_repository}:ref:refs/heads/main" : "repo:${var.oidc_repository}:environment:${each.value}") : "CI-TRUST-DISABLED"
    } }
  }] })
  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy" "state" {
  for_each = local.roles
  name     = "application-state-only"
  role     = aws_iam_role.ci[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.state.arn },
    { Effect = "Allow", Action = each.key == "plan" ? ["s3:GetObject"] : ["s3:GetObject", "s3:PutObject"],
    Resource = "${aws_s3_bucket.state.arn}/${local.state_key}" },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
    Resource = "${aws_s3_bucket.state.arn}/${local.state_key}.tflock" }
  ] })
}

resource "aws_iam_role_policy" "read" {
  for_each = local.roles
  name     = "read-application"
  role     = aws_iam_role.ci[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:GetFunctionCodeSigningConfig", "lambda:GetPolicy", "lambda:GetAlias", "lambda:ListAliases", "lambda:ListVersionsByFunction", "lambda:ListTags", "lambda:GetFunctionConcurrency"],
    Resource = [local.lambda_arn, "${local.lambda_arn}:*"] },
    { Effect = "Allow", Action = "apigateway:GET", Resource = [local.api_arn, "${local.api_arn}/*"] },
    { Effect = "Allow", Action = "cloudwatch:DescribeAlarms", Resource = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:${local.name}-*" },
    { Effect = "Allow", Action = "cloudwatch:ListTagsForResource", Resource = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:${local.name}-*" }
  ] })
}

resource "aws_iam_role_policy" "deploy" {
  name = "change-application"
  role = aws_iam_role.ci["deploy"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["lambda:CreateFunction", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:DeleteFunction", "lambda:PublishVersion", "lambda:CreateAlias", "lambda:UpdateAlias", "lambda:DeleteAlias", "lambda:AddPermission", "lambda:RemovePermission", "lambda:TagResource", "lambda:UntagResource", "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency"],
    Resource = [local.lambda_arn, "${local.lambda_arn}:*"] },
    { Effect = "Allow", Action = "iam:PassRole", Resource = aws_iam_role.runtime.arn,
    Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } } },
    { Effect = "Allow", Action = ["apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"],
    Resource = ["${local.api_arn}/integrations*", "${local.api_arn}/routes*"] },
    { Effect = "Allow", Action = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource", "cloudwatch:UntagResource"],
    Resource = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:${local.name}-*" },
  ] })
}

resource "aws_apigatewayv2_stage" "live" {
  api_id      = aws_apigatewayv2_api.page.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit   = 10
    throttling_rate_limit    = 5
    detailed_metrics_enabled = true
  }
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId", route = "$context.routeKey", status = "$context.status",
      latency   = "$context.responseLatency", integrationError = "$context.integrationErrorMessage"
    })
  }
}

