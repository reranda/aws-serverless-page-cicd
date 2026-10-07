output "api_url" {
  value = "https://${var.rest_api_id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
}

output "lambda_version" {
  value = aws_lambda_alias.live.function_version
}

output "function_name" {
  value = aws_lambda_function.page.function_name
}

output "package_sha256_base64" {
  value = aws_lambda_function.page.source_code_hash
}
