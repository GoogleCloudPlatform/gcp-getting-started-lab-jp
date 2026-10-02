# Fictional test workload — serverless task/reminder API (see ../architecture.md).
# Everything is tagged for the migration-test cost sweep; the AutoTeardown
# tag is a review marker set from ~/.aws/journeys.env at deploy time.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Owner        = "migration-test"
      CostCenter   = "test-journeys"
      AutoTeardown = var.autoteardown_date
      Journey      = "j1-serverless-task-api"
    }
  }
}

locals {
  prefix = "sta-"
}
