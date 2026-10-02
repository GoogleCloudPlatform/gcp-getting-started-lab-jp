// database.bicep — the shop's catalogue and order database.
//
// One PostgreSQL flexible server, carrying a single database. The compute SKU
// arrives as a parameter rather than a literal, because the flexible-server
// catalogue differs between subscriptions and regions; main.bicep holds the
// default. Public endpoint with the "allow Azure services" firewall
// entry, because the web app egresses from shared App Service addresses that
// nobody could pin down to a fixed range.
//
// Child resources on a flexible server are applied one at a time — the database
// waits on the firewall rule so the two never collide.

@description('Region for the flexible server.')
param location string

@description('Tags applied to the flexible server.')
param tags object

@description('Server name. Becomes a postgres.database.azure.com DNS label, so it carries a suffix.')
param serverName string

@description('Name of the storefront database.')
param databaseName string

@description('Administrator login.')
param adminLogin string

@description('Administrator password. Generated at deploy time.')
@secure()
param adminPassword string

@description('PostgreSQL major version.')
param postgresVersion string

@description('Compute SKU for the flexible server.')
param skuName string

@description('Compute tier matching skuName.')
param skuTier string

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    createMode: 'Default'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32
      autoGrow: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
  }
}

resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'AllowAllAzureServicesAndResources'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource storefrontDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgres
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
  dependsOn: [
    allowAzureServices
  ]
}

output serverSkuName string = postgres.sku.name
output serverName string = postgres.name
output serverId string = postgres.id
output fullyQualifiedDomainName string = postgres.properties.fullyQualifiedDomainName
output databaseName string = storefrontDatabase.name
