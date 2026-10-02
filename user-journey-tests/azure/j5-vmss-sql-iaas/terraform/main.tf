# Resource group, shared tags, and the suffix that keeps globally-unique names
# unique.

data "azurerm_client_config" "current" {}

locals {
  # The Recovery Services vault name has to be unique across the subscription,
  # and public IP DNS labels have to be unique across the region. The suffix is
  # derived from the subscription and the group name, so it is stable for a
  # given estate and different between estates.
  unique = substr(sha1("${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}"), 0, 8)

  tags = {
    Owner        = "migration-test"
    CostCenter   = "test-journeys"
    AutoTeardown = var.autoteardown_date
    Journey      = "azure/j5-vmss-sql-iaas"
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
