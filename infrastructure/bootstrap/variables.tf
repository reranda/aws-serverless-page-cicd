variable "region" {
  type    = string
  default = "eu-west-2"
}
variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Use the 12-digit AWS account ID."
  }
}
variable "state_bucket" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "Use a globally unique S3 bucket name."
  }
}
variable "repository" {
  type    = string
  default = "reranda/aws-serverless-page-cicd"
}
variable "enable_ci_trust" {
  type        = bool
  default     = false
  description = "Enable only after CLI configuration verifies GitHub review and deployment controls."
}
variable "create_oidc_provider" {
  type        = bool
  default     = false
  description = "Keep false if token.actions.githubusercontent.com already exists from the first lab."
}

