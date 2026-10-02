# Read back by scripts/deploy.sh: the edge hostname it prints as BASE_URL, and
# the delivery account it seeds the preview placeholder into.

output "delivery_account_name" {
  value = azurerm_storage_account.delivery.name
}

output "delivery_container_name" {
  value = azurerm_storage_container.public.name
}

output "delivery_blob_host" {
  value = azurerm_storage_account.delivery.primary_blob_host
}

output "frontdoor_profile_name" {
  value = azurerm_cdn_frontdoor_profile.edge.name
}

output "frontdoor_endpoint_hostname" {
  description = "Generated *.azurefd.net hostname. Front Door can take several minutes after apply before it answers on it."
  value       = azurerm_cdn_frontdoor_endpoint.media.host_name
}

output "base_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.media.host_name}"
}
