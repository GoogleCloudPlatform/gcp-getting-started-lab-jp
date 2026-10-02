# j5-eks-microservices — provider + version pins.
#
# NOTE (dual-layer): this Terraform tree is authoritative for INFRASTRUCTURE
# only (cluster, nodes, IAM, table, registries). The workloads that run ON the
# cluster — deployments, services, the pod service account — are declared in
# ../k8s/ and applied by scripts/deploy.sh with kubectl. See README.md,
# "Dual-layer convention".

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x series (verified 2026-07).
      version = "~> 6.0"
    }
    tls = {
      # Only used to read the cluster OIDC issuer certificate thumbprint.
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
      Journey      = "j5-eks-microservices"
    }
  }
}
