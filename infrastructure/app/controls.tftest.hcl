mock_provider "aws" {
  mock_resource "aws_lambda_function" {
    defaults = { version = "7" }
  }
}

variables {
  environment         = "dev"
  expected_account_id = "123456789012"
  rest_api_id         = "api123abc"
  root_resource_id    = "root123abc"
  execution_role_arn  = "arn:aws:iam::123456789012:role/slpage-dev-runtime"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-2:123456789012:key/11111111-1111-1111-1111-111111111111"
}

run "stage_scoped_published_release" {
  command = apply
  assert {
    condition     = aws_lambda_alias.live.function_version == "7" && aws_lambda_permission.api.qualifier == "live"
    error_message = "The API must invoke the live alias of a published version."
  }
  assert {
    condition     = aws_lambda_permission.api.source_arn == "arn:aws:execute-api:eu-west-2:123456789012:api123abc/dev/*/*" && aws_lambda_permission.api.source_account == "123456789012"
    error_message = "Lambda invocation must select the exact API, stage and account."
  }
  assert {
    condition     = !aws_api_gateway_method_settings.page.settings[0].data_trace_enabled && aws_api_gateway_stage.page.xray_tracing_enabled
    error_message = "Request data tracing must stay disabled while tracing is enabled."
  }
}

run "reviewed_rollback_selects_numbered_version" {
  command = apply
  variables { alias_version_override = "3" }
  assert {
    condition     = aws_lambda_alias.live.function_version == "3"
    error_message = "Rollback must select the reviewed numbered version."
  }
}
