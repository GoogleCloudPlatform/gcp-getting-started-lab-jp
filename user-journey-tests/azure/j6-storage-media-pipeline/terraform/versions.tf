# The media-licensing operator (fictional) — delivery edge. Provider and version pins.
#
# Scope note: this tree owns the DELIVERY SLICE only — the public origin
# account the licensing site's preview renders are served from, and the Front
# Door profile in front of it. The library itself (the media account, the
# premium share, the sync service, the factory and the blob events) is in
# ../arm/azuredeploy.json and is not managed from here.
#
# The edge was rebuilt in Terraform in 2025 when the contractor took the CDN
# work over; the rest of the estate stayed on the 2022 portal export.

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
