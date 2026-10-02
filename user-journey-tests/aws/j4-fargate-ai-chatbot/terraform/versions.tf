# j4-fargate-ai-chatbot — provider + version pins.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x series; latest 6.53.0 as of 2026-07 (verified).
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Applied to every taggable resource in this configuration.
  default_tags {
    tags = {
      Owner        = "migration-test"
      CostCenter   = "test-journeys"
      AutoTeardown = var.autoteardown_date
      Journey      = "j4-fargate-ai-chatbot"
    }
  }
}
