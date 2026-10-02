# Read back by scripts/deploy.sh to print BASE_URL and by scripts/teardown.sh
# to find the vault and the protected item before deleting the group.

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "base_url" {
  description = "The MES web tier's public entry point."
  value       = "http://${azurerm_public_ip.web.ip_address}"
}

output "load_balancer_ip" {
  value = azurerm_public_ip.web.ip_address
}

output "scale_set_name" {
  value = azurerm_windows_virtual_machine_scale_set.mes.name
}

output "sql_vm_name" {
  value = azurerm_windows_virtual_machine.sql.name
}

output "sql_private_ip" {
  value = azurerm_network_interface.sql.private_ip_address
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "recovery_vault_name" {
  value = azurerm_recovery_services_vault.main.name
}

output "location" {
  value = azurerm_resource_group.main.location
}
