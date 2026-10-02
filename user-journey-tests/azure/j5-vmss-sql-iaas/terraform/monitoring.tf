# The workspace the plant's monitoring runs into.
#
# Retention is the number the quality manager asked for, not a default: the
# plant is audited against IATF 16949 and the auditors have twice asked to see
# process data from the previous production year, so the workspace was set to
# keep two years of it queryable. Nobody has revisited that setting since it
# was typed in, and the ingestion volume has roughly tripled in the meantime.

resource "azurerm_log_analytics_workspace" "main" {
  name                = "vsi-law"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}
