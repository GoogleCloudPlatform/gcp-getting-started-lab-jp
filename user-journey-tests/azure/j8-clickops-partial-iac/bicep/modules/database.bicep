// database.bicep — the notice board's database.
//
// One SQL logical server carrying a single database at the Basic service
// objective: 5 DTU, 2 GB. The notice board holds a few hundred rows and is read
// far more often than it is written, so the smallest objective has always been
// enough. The service objective arrives as a parameter rather than a literal
// because the catalogue differs between subscriptions; main.bicep holds the
// default.
//
// The server keeps a public endpoint with the "allow Azure services" firewall
// entry, because the portal egresses from shared App Service addresses that
// nobody could pin down to a fixed range. Operators reaching the server from a
// laptop add their own address and take it away again — scripts/seed.sh does
// exactly that.

@description('Region for the logical server and the database.')
param location string

@description('Tags applied to the logical server and the database.')
param tags object

@description('Server name. Becomes a database.windows.net DNS label, so it carries a suffix.')
param serverName string

@description('Name of the portal database.')
param databaseName string

@description('Administrator login.')
param adminLogin string

@description('Administrator password. Generated at deploy time.')
@secure()
param adminPassword string

@description('Service objective for the database.')
param skuName string

@description('Service tier matching skuName.')
param skuTier string

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// 0.0.0.0-0.0.0.0 is the documented sentinel for "any Azure service in any
// subscription", which is how the App Service workers reach the database.
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource portalDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Local'
  }
  dependsOn: [
    allowAzureServices
  ]
}

output serverName string = sqlServer.name
output serverId string = sqlServer.id
output fullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = portalDatabase.name
output databaseSkuName string = portalDatabase.sku.name
