# Resource group, shared tags, and the suffix that keeps globally-unique names
# unique.

data "azurerm_client_config" "current" {}

locals {
  # Container registry, Service Bus namespace and Cosmos DB account names are
  # public DNS labels, so they have to be unique across the whole of Azure.
  # The suffix is derived from the subscription and the group name, so it is
  # stable for a given lab and different between labs.
  unique = substr(sha1("${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}"), 0, 8)

  tags = {
    Owner        = "migration-test"
    CostCenter   = "test-journeys"
    AutoTeardown = var.autoteardown_date
    Journey      = "azure/j3-aks-microservices"
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
