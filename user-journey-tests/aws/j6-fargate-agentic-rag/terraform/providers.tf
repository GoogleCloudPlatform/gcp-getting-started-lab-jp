# j6-fargate-agentic-rag — provider pins and account-wide tagging.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # 6.x series (verified 2026-08)
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Owner        = "migration-test"
      CostCenter   = "test-journeys"
      AutoTeardown = var.autoteardown_date
      Journey      = "j6-fargate-agentic-rag"
    }
  }
}

# The account's default VPC carries everything — this journey never creates
# or destroys VPC-level networking, matching the lab account's guardrails.
data "aws_vpc" "this" {
  default = true
}

data "aws_subnets" "this" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_caller_identity" "this" {}
