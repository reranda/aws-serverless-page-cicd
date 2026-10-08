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
  description = "Enable after completing setup for the selected deployment mode."
}
variable "deployment_mode" {
  type    = string
  default = "reviewed"
  validation {
    condition     = contains(["reviewed", "private-lab"], var.deployment_mode)
    error_message = "Choose reviewed or private-lab."
  }
}
variable "oidc_repository" {
  type        = string
  default     = "reranda@39367723/aws-serverless-page-cicd@1409182803"
  description = "Exact repository portion of the observed GitHub OIDC subject. New repositories use immutable IDs."
}
variable "create_oidc_provider" {
  type        = bool
  default     = false
  description = "Keep false if token.actions.githubusercontent.com already exists from the first lab."
}

