# The MES database server.
#
# This is a server, not a managed database service: SQL Server runs inside a
# Windows VM built from the gallery image, and everything around it — the
# Agent jobs, the nightly maintenance plan, the folder the vendor's importer
# drops files into — lives on the box. The 2022 lift moved the machine as it
# was and changed nothing about how it is run.

resource "azurerm_network_interface" "sql" {
  name                           = "vsi-sql01-nic"
  resource_group_name            = azurerm_resource_group.main.name
  location                       = azurerm_resource_group.main.location
  accelerated_networking_enabled = true
  tags                           = local.tags

  ip_configuration {
    name                          = "vsi-sql01-ipcfg"
    subnet_id                     = azurerm_subnet.data.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.40.2.4"
  }
}

resource "azurerm_windows_virtual_machine" "sql" {
  name                = "vsi-sql01"
  computer_name       = "vsi-sql01"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.sql_vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = local.tags

  network_interface_ids = [azurerm_network_interface.sql.id]

  source_image_reference {
    publisher = "MicrosoftSQLServer"
    offer     = var.sql_image_offer
    sku       = var.sql_image_sku
    version   = "latest"
  }

  os_disk {
    name                 = "vsi-sql01-osdisk"
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
  }

  boot_diagnostics {}
}

# Database files, transaction logs and the folder the maintenance plan writes
# its own .bak files into before the vault picks the machine up.
resource "azurerm_managed_disk" "sql_data" {
  name                 = "vsi-sql01-data01"
  resource_group_name  = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.sql_data_disk_gb
  tags                 = local.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "sql_data" {
  managed_disk_id    = azurerm_managed_disk.sql_data.id
  virtual_machine_id = azurerm_windows_virtual_machine.sql.id
  lun                = 0
  caching            = "ReadOnly"
}
