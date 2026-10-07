variable "project" {
  description = "Dedicated resource prefix. Use a new prefix rather than existing employer infrastructure."
  type        = string
  default     = "slpage"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project))
    error_message = "Use 3–20 lowercase letters, numbers and hyphens, starting with a letter."
  }
}

variable "aws_region" {
  description = "Region for this independent lab."
  type        = string
  default     = "eu-west-2"
}

variable "expected_account_id" {
  description = "The personal lab AWS account ID, verified using aws sts get-caller-identity."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Supply a 12-digit AWS account ID."
  }
}

variable "github_owner" {
  description = "GitHub repository owner."
  type        = string
  default     = "reranda"
}

variable "github_owner_id" {
  description = "Immutable owner ID used by GitHub's post-July-2026 OIDC subject."
  type        = string
  default     = "39367723"
}

variable "github_repository" {
  description = "Repository name."
  type        = string
  default     = "aws-serverless-page-cicd"
}

variable "github_repository_id" {
  description = "Immutable repository ID. Confirm the real claim before bootstrapping."
  type        = string
  default     = "1409182803"
}

variable "create_oidc_provider" {
  description = "Create the account-level GitHub OIDC provider only if it does not already exist."
  type        = bool
  default     = false
}

variable "enable_github_oidc" {
  description = "Enable role assumption only after branch and environment protections have been verified."
  type        = bool
  default     = false
}

variable "manage_api_gateway_account" {
  description = "Explicit opt-in to set the regional, account-wide API Gateway CloudWatch role."
  type        = bool
  default     = false
}

variable "existing_api_gateway_cloudwatch_role_arn" {
  description = "Existing account-wide API Gateway logging role, obtained using aws apigateway get-account."
  type        = string
  default     = ""
}
