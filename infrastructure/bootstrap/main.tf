locals {
  environments = toset(["dev", "prod"])
  oidc_arn     = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${var.expected_account_id}:oidc-provider/token.actions.githubusercontent.com"
  oidc_prefix  = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}"
  state_bucket = "${var.project}-tfstate-${var.expected_account_id}-${var.aws_region}"
}

resource "terraform_data" "prerequisites" {
  lifecycle {
    precondition {
      condition     = var.manage_api_gateway_account || can(regex("^arn:aws:iam::${var.expected_account_id}:role/.+$", var.existing_api_gateway_cloudwatch_role_arn))
      error_message = "Inspect aws apigateway get-account first. Supply its existing CloudWatch role ARN or explicitly opt in to manage_api_gateway_account if none exists."
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_kms_key" "state" {
  description             = "${var.project} Terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Sid       = "AccountAdministration", Effect = "Allow",
      Principal = { AWS = "arn:aws:iam::${var.expected_account_id}:root" },
      Action    = "kms:*", Resource = "*"
    }]
  })
  lifecycle { prevent_destroy = true }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:State access logging is a documented account-audit prerequisite; this isolated lab does not create a second audit bucket.
  #checkov:skip=CKV_AWS_144:Single-region lab uses encrypted versioned state; cross-region disaster recovery requires a separate production design.
  #checkov:skip=CKV2_AWS_62:State change notifications require an approved audit integration; no notification consumer is configured in this lab.
  bucket        = local.state_bucket
  force_destroy = false
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "retain-recovery-versions"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*",
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"],
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# These API containers and execution identities are owned by bootstrap. Application
# roles cannot create arbitrary APIs, IAM roles, policies, or account-wide settings.
resource "aws_api_gateway_rest_api" "app" {
  for_each = local.environments
  name     = "${var.project}-${each.key}"
  endpoint_configuration { types = ["REGIONAL"] }
  tags = { Environment = each.key }
  lifecycle { create_before_destroy = true }
}

resource "aws_kms_key" "environment" {
  for_each                = local.environments
  description             = "${var.project}-${each.key} logs and encrypted release plans"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      {
        Sid       = "AccountAdministration", Effect = "Allow",
        Principal = { AWS = "arn:aws:iam::${var.expected_account_id}:root" },
        Action    = "kms:*", Resource = "*"
      },
      {
        Sid       = "ApplicationLogEncryption", Effect = "Allow",
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" },
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"], Resource = "*",
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = [
            "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/lambda/${var.project}-${each.key}",
            "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/apigateway/${var.project}-${each.key}"
          ] }
        }
      }
    ]
  })
  tags = { Environment = each.key }
}

resource "aws_kms_alias" "environment" {
  for_each      = local.environments
  name          = "alias/${var.project}-${each.key}"
  target_key_id = aws_kms_key.environment[each.key].key_id
}

resource "aws_iam_policy" "runtime" {
  for_each = local.environments
  name     = "${var.project}-${each.key}-runtime"
  policy = jsonencode({
    Version = "2012-10-17", Statement = [
      {
        Effect   = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/lambda/${var.project}-${each.key}:*"
      },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role" "runtime" {
  for_each             = local.environments
  name                 = "${var.project}-${each.key}-runtime"
  permissions_boundary = aws_iam_policy.runtime[each.key].arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole"
    }]
  })
  tags = { Environment = each.key }
}

resource "aws_iam_role_policy_attachment" "runtime" {
  for_each   = local.environments
  role       = aws_iam_role.runtime[each.key].name
  policy_arn = aws_iam_policy.runtime[each.key].arn
}

locals {
  read_statements = { for environment in local.environments : environment => [
    {
      Effect   = "Allow", Action = ["lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:GetPolicy", "lambda:GetAlias", "lambda:ListAliases", "lambda:ListVersionsByFunction", "lambda:ListTags", "lambda:GetFunctionConcurrency", "lambda:GetFunctionCodeSigningConfig"],
      Resource = ["arn:aws:lambda:${var.aws_region}:${var.expected_account_id}:function:${var.project}-${environment}", "arn:aws:lambda:${var.aws_region}:${var.expected_account_id}:function:${var.project}-${environment}:*"]
    },
    {
      Effect   = "Allow", Action = ["apigateway:GET"],
      Resource = ["arn:aws:apigateway:${var.aws_region}::/restapis/${aws_api_gateway_rest_api.app[environment].id}", "arn:aws:apigateway:${var.aws_region}::/restapis/${aws_api_gateway_rest_api.app[environment].id}/*"]
    },
    { Effect = "Allow", Action = ["logs:DescribeLogGroups", "cloudwatch:DescribeAlarms"], Resource = "*" },
    {
      Effect   = "Allow", Action = ["logs:DescribeLogStreams", "logs:ListTagsForResource"],
      Resource = ["arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/lambda/${var.project}-${environment}:*", "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/apigateway/${var.project}-${environment}:*"]
    },
    { Effect = "Allow", Action = ["cloudwatch:ListTagsForResource"], Resource = "arn:aws:cloudwatch:${var.aws_region}:${var.expected_account_id}:alarm:${var.project}-${environment}-*" },
    {
      Effect    = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.state.arn,
      Condition = { StringLike = { "s3:prefix" = ["${environment}/*"] } }
    },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.state.arn}/${environment}/terraform.tfstate" },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.state.arn}/${environment}/terraform.tfstate.tflock" },
    {
      Effect    = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.state.arn,
      Condition = { StringEquals = { "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com" } }
    },
    {
      Effect    = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = aws_kms_key.environment[environment].arn,
      Condition = { StringEquals = { "kms:EncryptionContext:Project" = var.project, "kms:EncryptionContext:Environment" = environment } }
    }
  ] }
  write_statements = { for environment in local.environments : environment => [
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.state.arn}/${environment}/terraform.tfstate" },
    {
      Effect   = "Allow", Action = ["lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:PublishVersion", "lambda:CreateAlias", "lambda:UpdateAlias", "lambda:DeleteAlias", "lambda:AddPermission", "lambda:RemovePermission", "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency", "lambda:TagResource", "lambda:UntagResource"],
      Resource = ["arn:aws:lambda:${var.aws_region}:${var.expected_account_id}:function:${var.project}-${environment}", "arn:aws:lambda:${var.aws_region}:${var.expected_account_id}:function:${var.project}-${environment}:*"]
    },
    {
      Effect    = "Allow", Action = ["iam:PassRole"], Resource = aws_iam_role.runtime[environment].arn,
      Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
    },
    {
      Effect   = "Allow", Action = ["apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"],
      Resource = "arn:aws:apigateway:${var.aws_region}::/restapis/${aws_api_gateway_rest_api.app[environment].id}/*"
    },
    {
      Effect   = "Allow", Action = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:AssociateKmsKey", "logs:DisassociateKmsKey", "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup"],
      Resource = ["arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/lambda/${var.project}-${environment}", "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/lambda/${var.project}-${environment}:*", "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/apigateway/${var.project}-${environment}", "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/apigateway/${var.project}-${environment}:*"]
    },
    {
      Effect   = "Allow", Action = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource", "cloudwatch:UntagResource"],
      Resource = "arn:aws:cloudwatch:${var.aws_region}:${var.expected_account_id}:alarm:${var.project}-${environment}-*"
    }
  ] }
}

resource "aws_iam_policy" "plan" {
  for_each = local.environments
  name     = "${var.project}-${each.key}-plan"
  policy   = jsonencode({ Version = "2012-10-17", Statement = local.read_statements[each.key] })
}

resource "aws_iam_policy" "deploy" {
  for_each = local.environments
  name     = "${var.project}-${each.key}-deploy"
  policy   = jsonencode({ Version = "2012-10-17", Statement = concat(local.read_statements[each.key], local.write_statements[each.key]) })
}

resource "aws_iam_role" "plan" {
  for_each             = local.environments
  name                 = "${var.project}-${each.key}-plan"
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.plan[each.key].arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect    = "Allow", Principal = { Federated = local.oidc_arn }, Action = "sts:AssumeRoleWithWebIdentity",
      Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = var.enable_github_oidc ? "${local.oidc_prefix}:ref:refs/heads/main" : "${local.oidc_prefix}:disabled" } }
    }]
  })
  tags = { Environment = each.key }
}

resource "aws_iam_role" "deploy" {
  for_each             = local.environments
  name                 = "${var.project}-${each.key}-deploy"
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.deploy[each.key].arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect    = "Allow", Principal = { Federated = local.oidc_arn }, Action = "sts:AssumeRoleWithWebIdentity",
      Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = var.enable_github_oidc ? "${local.oidc_prefix}:environment:${each.key}" : "${local.oidc_prefix}:disabled" } }
    }]
  })
  tags = { Environment = each.key }
}

resource "aws_iam_role_policy_attachment" "plan" {
  for_each   = local.environments
  role       = aws_iam_role.plan[each.key].name
  policy_arn = aws_iam_policy.plan[each.key].arn
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each   = local.environments
  role       = aws_iam_role.deploy[each.key].name
  policy_arn = aws_iam_policy.deploy[each.key].arn
}

resource "aws_iam_role" "api_gateway_logs" {
  count = var.manage_api_gateway_account ? 1 : 0
  name  = "${var.project}-api-gateway-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Effect = "Allow", Principal = { Service = "apigateway.amazonaws.com" }, Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_logs" {
  count      = var.manage_api_gateway_account ? 1 : 0
  role       = aws_iam_role.api_gateway_logs[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "logging" {
  count               = var.manage_api_gateway_account ? 1 : 0
  cloudwatch_role_arn = aws_iam_role.api_gateway_logs[0].arn
  depends_on          = [aws_iam_role_policy_attachment.api_gateway_logs]
  lifecycle { prevent_destroy = true }
}
