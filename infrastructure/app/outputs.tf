output "page_url" { value = var.api_endpoint }
output "health_url" { value = "${var.api_endpoint}/health" }
output "lambda_version" { value = aws_lambda_function.page.version }
output "release_sha" { value = var.release_sha }

