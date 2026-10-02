// main.bicep — the stationery shop's online storefront.
// ---------------------------------------------------------------------------
// Everything lands in one resource group (pwa-rg) so the whole shop can be
// removed with a single `az group delete`.
//
// Composition order is expressed through module inputs rather than dependsOn:
//   storage + key vault + monitoring  ->  database  ->  web app (+ staging slot)
//   ->  role assignments for the web app's identity  ->  front door
//
// The App Service plan is S1 rather than a burstable B-series because the shop
// keeps a staging slot, and staging slots are only available from the Standard
// tier upwards. S1 is the smallest tier that carries one.
//
// Region and both compute SKUs are parameters, never literals in a module: the
// region follows the resource group, and the two SKUs can be moved onto another
// size without editing a template when a subscription's catalogue does not
// carry the default.
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

@description('Azure region for every resource in the shop. Front Door itself is global.')
param location string = resourceGroup().location

@description('Date this estate should be torn down, stamped onto every resource as a tag.')
param autoTeardownDate string

@description('Administrator login for the PostgreSQL flexible server.')
param dbAdminLogin string = 'pwaadmin'

@description('Administrator password for the PostgreSQL flexible server. Generated at deploy time.')
@secure()
param dbAdminPassword string

@description('Django SECRET_KEY for the storefront. Generated at deploy time.')
@secure()
param djangoSecretKey string

@description('PostgreSQL major version the storefront runs against.')
param postgresVersion string = '16'

@description('App Service plan SKU. Must be a slot-capable tier — the shop keeps a staging slot, and slots start at Standard.')
param appServicePlanSkuName string = 'S1'

@description('App Service plan tier matching appServicePlanSkuName.')
param appServicePlanSkuTier string = 'Standard'

@description('Compute SKU for the PostgreSQL flexible server.')
param postgresSkuName string = 'Standard_B1ms'

@description('Compute tier matching postgresSkuName.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param postgresSkuTier string = 'Burstable'

@description('Whether this deployment creates the web app identity\'s data-plane role assignments. Writing a role assignment needs more than Contributor on the scope; where that is held elsewhere, the grants are applied by the subscription administrator and this switch is off.')
param deployRoleAssignments bool = true

// Storage accounts, key vaults, App Service sites, PostgreSQL servers and Front
// Door endpoints are all global DNS labels, so each name carries a suffix
// derived from the resource group id.
var uniqueSuffix = uniqueString(resourceGroup().id)

var commonTags = {
  Owner: 'migration-test'
  CostCenter: 'test-journeys'
  AutoTeardown: autoTeardownDate
  Journey: 'azure/j2-paas-web-app'
}

var storageAccountName = 'pwamedia${uniqueSuffix}'
var keyVaultName = 'pwa-kv-${uniqueSuffix}'
var webAppName = 'pwa-web-${uniqueSuffix}'
var postgresServerName = 'pwa-pg-${uniqueSuffix}'
var frontDoorEndpointName = 'pwa-shop-${uniqueSuffix}'
var mediaContainerName = 'media'
var databaseName = 'pwashop'

module storage 'modules/storage.bicep' = {
  name: 'pwa-storage'
  params: {
    location: location
    tags: commonTags
    storageAccountName: storageAccountName
    mediaContainerName: mediaContainerName
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'pwa-keyvault'
  params: {
    location: location
    tags: commonTags
    keyVaultName: keyVaultName
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'pwa-monitoring'
  params: {
    location: location
    tags: commonTags
    workspaceName: 'pwa-logs'
    appInsightsName: 'pwa-appi'
  }
}

module database 'modules/database.bicep' = {
  name: 'pwa-database'
  params: {
    location: location
    tags: commonTags
    serverName: postgresServerName
    databaseName: databaseName
    adminLogin: dbAdminLogin
    adminPassword: dbAdminPassword
    postgresVersion: postgresVersion
    skuName: postgresSkuName
    skuTier: postgresSkuTier
  }
}

module webapp 'modules/webapp.bicep' = {
  name: 'pwa-webapp'
  params: {
    location: location
    tags: commonTags
    planName: 'pwa-plan'
    planSkuName: appServicePlanSkuName
    planSkuTier: appServicePlanSkuTier
    webAppName: webAppName
    djangoSecretKey: djangoSecretKey
    databaseHost: database.outputs.fullyQualifiedDomainName
    databaseName: databaseName
    databaseLogin: dbAdminLogin
    databasePassword: dbAdminPassword
    mediaAccountName: storage.outputs.storageAccountName
    mediaBlobEndpoint: storage.outputs.blobEndpoint
    mediaContainerName: mediaContainerName
    keyVaultUri: keyvault.outputs.vaultUri
    checkoutKeySecretUri: keyvault.outputs.checkoutKeySecretUri
    appInsightsConnectionString: monitoring.outputs.connectionString
  }
}

module rbac 'modules/rbac.bicep' = if (deployRoleAssignments) {
  name: 'pwa-rbac'
  params: {
    keyVaultName: keyVaultName
    storageAccountName: storageAccountName
    principalId: webapp.outputs.principalId
  }
}

module frontdoor 'modules/frontdoor.bicep' = {
  name: 'pwa-frontdoor'
  params: {
    tags: commonTags
    profileName: 'pwa-fd'
    endpointName: frontDoorEndpointName
    originHostName: webapp.outputs.defaultHostName
  }
}

output baseUrl string = 'https://${frontdoor.outputs.endpointHostName}'
output originUrl string = 'https://${webapp.outputs.defaultHostName}'
output stagingUrl string = 'https://${webapp.outputs.stagingHostName}'
output webAppName string = webAppName
output postgresFqdn string = database.outputs.fullyQualifiedDomainName
output postgresSku string = database.outputs.serverSkuName
output storageAccountName string = storageAccountName
output keyVaultName string = keyVaultName
output mediaContainerName string = mediaContainerName
