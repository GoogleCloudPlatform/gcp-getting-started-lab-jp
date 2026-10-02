# Shared tags and the resource group this tree writes into.
#
# The group is looked up rather than created: it belongs to the estate as a
# whole, and scripts/deploy.sh creates it with the tag block below before
# either tree runs.

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

locals {
  tags = {
    Owner        = "migration-test"
    CostCenter   = "test-journeys"
    AutoTeardown = var.autoteardown_date
    Journey      = "azure/j6-storage-media-pipeline"
  }

  delivery_account_name = "smpdelivery${var.name_suffix}"
}
