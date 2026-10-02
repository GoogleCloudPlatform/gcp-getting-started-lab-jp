# Read back by scripts/deploy.sh: kubeconfig, image push, manifest rendering.
# Read back by scripts/teardown.sh: the node resource group name.

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "node_resource_group" {
  description = "Resource group AKS created for the node pool VMs and the load balancer."
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "container_registry_name" {
  value = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "workload_identity_client_id" {
  description = "Rendered into the service-account annotation in ../k8s/ by deploy.sh."
  value       = azurerm_user_assigned_identity.workload.client_id
}

output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database" {
  value = azurerm_cosmosdb_sql_database.tracking.name
}

output "cosmos_container" {
  value = azurerm_cosmosdb_sql_container.parcels.name
}

output "servicebus_namespace_fqdn" {
  value = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
}

output "servicebus_queue" {
  value = azurerm_servicebus_queue.parcel_events.name
}

output "location" {
  value = azurerm_resource_group.main.location
}
