# Container registry for the two service images.
#
# Premium, and holding a second region: the 2025 plan was to run parcel
# tracking out of a second depot as well as the original one, and the registry
# was set up for it first because it was the easy half of the work. The second
# depot never happened, and the replica stayed where the plan put it — see
# var.acr_replication_region.

resource "azurerm_container_registry" "main" {
  name                = "akmacr${local.unique}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Premium"

  # Pulls authenticate with the cluster's kubelet identity via AcrPull, so the
  # shared admin account stays off.
  admin_enabled = false

  georeplications {
    location                        = var.acr_replication_region
    global_endpoint_routing_enabled = true
    zone_redundancy_enabled         = false
    tags                            = local.tags
  }

  tags = local.tags

  lifecycle {
    # Azure rejects a replica in the registry's own region. Catching it here
    # fails the plan in a second instead of ten minutes into the apply.
    precondition {
      condition     = var.acr_replication_region != var.location
      error_message = "acr_replication_region must differ from location: a registry cannot hold a replica in its own region."
    }
  }
}
