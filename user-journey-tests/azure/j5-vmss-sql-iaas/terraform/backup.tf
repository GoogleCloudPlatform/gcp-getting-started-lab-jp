# Azure Backup, covering exactly one machine: the database server.
#
# The web tier is not protected. The contractor's position has always been that
# the instances are disposable and the vendor's installer can rebuild one in an
# afternoon, so the vault was pointed at the box that holds the data and left
# there.
#
# The vault name has to be unique across the subscription, hence the suffix.
#
# Soft delete cannot be turned off here — the argument that used to do it was
# removed from the provider in 5.0, and Azure no longer permits disabling it in
# the regions where secure-by-default is generally available. That is a
# teardown consideration rather than a deployment one: see scripts/teardown.sh,
# which disables protection and drops the backup data before the group delete.

resource "azurerm_recovery_services_vault" "main" {
  name                = "vsi-rsv-${local.unique}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  storage_mode_type   = "LocallyRedundant"
  tags                = local.tags
}

# Runs after the late shift has closed its last work order. Azure enforces a
# floor of seven daily recovery points whatever the provider schema accepts, so
# this is the shortest legal retention rather than a considered choice.
resource "azurerm_backup_policy_vm" "sql_daily" {
  name                = "vsi-sql-daily"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  timezone            = "Tokyo Standard Time"

  backup {
    frequency = "Daily"
    time      = "22:00"
  }

  retention_daily {
    count = var.backup_retention_days
  }
}

resource "azurerm_backup_protected_vm" "sql" {
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  source_vm_id        = azurerm_windows_virtual_machine.sql.id
  backup_policy_id    = azurerm_backup_policy_vm.sql_daily.id

  # Protecting the machine installs an agent on it, which needs the data
  # subnet's route out to be in place first.
  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.sql_data,
    azurerm_subnet_nat_gateway_association.data,
  ]
}
