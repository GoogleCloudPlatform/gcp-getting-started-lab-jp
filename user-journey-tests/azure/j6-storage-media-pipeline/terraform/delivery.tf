# The public delivery origin.
#
# Everything Front Door serves comes out of the "public" container below:
# watermarked preview renders, copied up from the proxies container by the
# contractor's publish script whenever a shoot is released to the catalogue.

resource "azurerm_storage_account" "delivery" {
  name                = local.delivery_account_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Previews are cold most of the time. The catalogue's long tail is the whole
  # business: a photograph shot in 2017 gets looked at twice a year, and cool
  # storage is a third of the price to keep.
  access_tier = "Cool"

  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  # Front Door reads the preview blobs anonymously; there is no origin
  # authentication on this account and nothing private is ever published to it.
  allow_nested_items_to_be_public = true
  shared_access_key_enabled       = true
  public_network_access_enabled   = true

  tags = local.tags
}

resource "azurerm_storage_container" "public" {
  name                  = "public"
  storage_account_id    = azurerm_storage_account.delivery.id
  container_access_type = "blob"
}
