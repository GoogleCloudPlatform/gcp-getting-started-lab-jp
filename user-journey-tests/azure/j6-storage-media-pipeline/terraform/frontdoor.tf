# Front Door Standard in front of the delivery origin.
#
# Tier choice: Azure CDN Standard from Microsoft (classic) stopped accepting new
# profiles on 2025-08-15 and retires on 2027-09-30, so a profile created today
# is a Front Door one whether or not the workload wants Front Door's dynamic
# features. Standard is the routing-and-caching tier; the studio buys no WAF.
#
# There is no custom domain. Catalogue previews are served from the generated
# *.azurefd.net endpoint and always have been — the licensing site rewrites
# image URLs to it at render time.

resource "azurerm_cdn_frontdoor_profile" "edge" {
  name                = "smp-fd"
  resource_group_name = data.azurerm_resource_group.main.name
  sku_name            = var.frontdoor_sku

  # Seconds Front Door waits for the origin to send a response before giving up.
  response_timeout_seconds = 60

  tags = local.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "media" {
  name                     = "smp-media-edge"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.edge.id
  enabled                  = true

  tags = local.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "delivery" {
  name                     = "smp-fd-delivery-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.edge.id

  # One origin, so there is nothing to balance across; these are the values the
  # portal writes when a profile is created with a single origin.
  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }

  health_probe {
    interval_in_seconds = 100
    path                = "/public/health.txt"
    protocol            = "Https"
    request_type        = "HEAD"
  }
}

resource "azurerm_cdn_frontdoor_origin" "delivery" {
  name                          = "smp-fd-delivery-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.delivery.id
  enabled                       = true

  # The origin is the blob endpoint's own certificate, so the name check stays
  # on and the host header has to be the blob host rather than the Front Door
  # hostname — a storage account rejects a request whose Host is anything else.
  certificate_name_check_enabled = true
  host_name                      = azurerm_storage_account.delivery.primary_blob_host
  origin_host_header             = azurerm_storage_account.delivery.primary_blob_host

  http_port  = 80
  https_port = 443
  priority   = 1
  weight     = 1000
}

resource "azurerm_cdn_frontdoor_route" "previews" {
  name                          = "smp-fd-previews"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.media.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.delivery.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.delivery.id]
  enabled                       = true

  # Requests arrive as /<blob>, and the container name is prepended here so the
  # container is not part of the public URL. The origin path REPLACES the part
  # of the request that the route pattern matched and the remainder is appended
  # verbatim, so the trailing slash is load-bearing: without it /index.html
  # forwards to /publicindex.html.
  cdn_frontdoor_origin_path = "/public/"

  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  link_to_default_domain = true

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = false
  }
}
