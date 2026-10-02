# Parcel documents.
#
# One document per parcel, partitioned on the parcel id, holding the current
# status and the scan history. Read volume is a few hundred lookups a minute
# from the public tracking page; write volume is whatever the depots scan.
#
# Serverless rather than provisioned throughput: overnight traffic is close to
# zero and nobody wanted to size RU/s for a load that swings by two orders of
# magnitude between 03:00 and 11:00.

resource "azurerm_cosmosdb_account" "main" {
  name                = "akm-cosmos-${local.unique}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "tracking" {
  name                = "tracking"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "parcels" {
  name                  = "parcels"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.tracking.name
  partition_key_paths   = ["/parcelId"]
  partition_key_version = 2

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/scans/*"
    }
  }
}
