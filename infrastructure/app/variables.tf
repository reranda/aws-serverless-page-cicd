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
variable "api_id" { type = string }
variable "api_endpoint" { type = string }
variable "api_execution_arn" { type = string }
variable "runtime_role_arn" { type = string }
variable "alarm_topic_arn" { type = string }
variable "release_sha" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.release_sha))
    error_message = "Use a full Git commit SHA."
  }
}

