# Parcel scan events.
#
# Every handheld scan in a depot becomes one message. Messages are grouped by
# parcel so that the scans for a single parcel are processed in the order they
# were taken — a "picked up" that arrives after its "delivered" produces a
# wrong tracking page and a phone call from the customer.

resource "azurerm_servicebus_namespace" "main" {
  name                = "akm-sb-${local.unique}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  tags = local.tags
}

resource "azurerm_servicebus_queue" "parcel_events" {
  name         = "parcel-events"
  namespace_id = azurerm_servicebus_namespace.main.id

  # One session per parcel id. A receiver locks a whole session, so scans for
  # the same parcel are never handled by two notifier pods at once.
  requires_session = true

  # Five attempts, then the message is moved aside rather than retried
  # forever. The queue that holds those is read by hand, about once a month.
  max_delivery_count                      = 5
  dead_lettering_on_message_expiration    = true
  default_message_ttl                     = "P1D"
  lock_duration                           = "PT1M"
  requires_duplicate_detection            = false
  duplicate_detection_history_time_window = "PT10M"
  max_size_in_megabytes                   = 1024
}
