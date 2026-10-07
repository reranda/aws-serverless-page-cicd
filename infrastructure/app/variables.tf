variable "project" {
  description = "Prefix matching the bootstrap layer."
  type        = string
  default     = "slpage"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project))
    error_message = "Use the validated bootstrap project prefix."
  }
}

variable "environment" {
  description = "Isolated state, role and API stage for dev or prod."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "aws_region" {
  description = "Region matching bootstrap."
  type        = string
  default     = "eu-west-2"
}

variable "expected_account_id" {
  description = "Fail closed when credentials belong to another account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Supply the 12-digit personal lab account ID."
  }
}

variable "rest_api_id" {
  description = "Bootstrap-owned REST API ID, limiting deployment-role permissions."
  type        = string
}

variable "root_resource_id" {
  description = "Root resource ID from the bootstrap API."
  type        = string
}

variable "execution_role_arn" {
  description = "Bootstrap-owned Lambda runtime role; application Terraform does not manage IAM."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Environment-specific KMS key configured for these CloudWatch log groups."
  type        = string
}

variable "lambda_zip_path" {
  description = "Deterministic ZIP supplied by the release workflow."
  type        = string
  default     = "../../build/lambda.zip"
}

variable "alias_version_override" {
  description = "Existing published version for a reviewed rollback. Null follows the new release."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.alias_version_override == null ? true : can(regex("^[1-9][0-9]*$", var.alias_version_override))
    error_message = "Rollback must select an existing numbered Lambda version, never $LATEST."
  }
}

variable "alarm_actions" {
  description = "Optional pre-approved SNS topic ARNs. Empty means alarms have no notification destination."
  type        = list(string)
  default     = []
}
