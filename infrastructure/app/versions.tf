terraform {
  required_version = "= 1.16.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.67.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
  default_tags {
    tags = { Project = var.project, Environment = var.environment, ManagedBy = "Terraform", Purpose = "Independent portfolio lab" }
  }
}
