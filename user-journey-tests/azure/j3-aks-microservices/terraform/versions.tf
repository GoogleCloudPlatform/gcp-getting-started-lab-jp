# The parcel-tracking platform (fictional) — provider and version pins.
#
# Scope note: this Terraform tree owns the PLATFORM only — the cluster, the
# registry, the queue, the database and the identities. What actually runs on
# the cluster (deployments, the service account, the public Service) is
# maintained as Kubernetes manifests under ../k8s/ by the two developers who
# own the services, and is applied with kubectl by scripts/deploy.sh.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  # Subscription comes from ARM_SUBSCRIPTION_ID, exported by scripts/deploy.sh
  # after it has checked the current az context against the expected value.
  features {}
}
