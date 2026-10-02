// main.bicep — the university student portal.
// ---------------------------------------------------------------------------
// This template covers the student portal and nothing else. It was written in
// 2025 by the web team when the portal was rebuilt, and it is the only part of
// the university's Azure estate that anybody ever put into source control. The
// rest of what the IT office runs was clicked together in the portal over the
// years by whoever needed it; see architecture.md for what that includes. Do
// not assume this file describes the whole subscription — it describes the
// student portal.
//
// Everything the template does create lands in one resource group (cpi-rg), so
// the portal can be removed with a single `az group delete`.
//
// Composition order is expressed through module inputs rather than dependsOn:
//   storage + database  ->  web app (settings reference both)
//
// The web app has no managed identity. It reaches storage with the account key
// and SQL with a username and password, both delivered as application settings
// that this template composes. That is how the web team set it up and it is
// what the running site expects; nothing here creates a role assignment, so the
// deployment needs no more than Contributor on the resource group.
//
// Region and both SKUs are parameters, never literals: the region follows the
// resource group, and the SKUs can be moved onto another size without editing a
// template when a subscription's catalogue does not carry the default.
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

@description('Azure region for every resource the portal deployment creates.')
param location string = resourceGroup().location

@description('Date this estate should be torn down, stamped onto every resource as a tag.')
param autoTeardownDate string

@description('Administrator login for the SQL logical server.')
param sqlAdminLogin string = 'cpiadmin'

@description('Administrator password for the SQL logical server. Generated at deploy time.')
@secure()
param sqlAdminPassword string

@description('App Service plan SKU. B1 is the smallest plan that keeps the site warm between lectures.')
param appServicePlanSkuName string = 'B1'

@description('App Service plan tier matching appServicePlanSkuName.')
param appServicePlanSkuTier string = 'Basic'

@description('SQL database SKU. Basic is 5 DTU with a 2 GB ceiling — the notice board never grew past a few hundred rows.')
param sqlDatabaseSkuName string = 'Basic'

@description('SQL database tier matching sqlDatabaseSkuName.')
param sqlDatabaseSkuTier string = 'Basic'

@description('Python runtime the portal targets.')
param pythonVersion string = '3.12'

// Storage accounts, SQL logical servers and App Service sites are all global
// DNS labels, so each name carries a suffix derived from the resource group id.
var uniqueSuffix = uniqueString(resourceGroup().id)

var commonTags = {
  Owner: 'migration-test'
  CostCenter: 'test-journeys'
  AutoTeardown: autoTeardownDate
  Journey: 'azure/j8-clickops-partial-iac'
}

var storageAccountName = 'cpiportal${uniqueSuffix}'
var sqlServerName = 'cpi-sql-${uniqueSuffix}'
var webAppName = 'cpi-portal-${uniqueSuffix}'
var documentsContainerName = 'documents'
var sqlDatabaseName = 'cpiportal'

module storage 'modules/storage.bicep' = {
  name: 'cpi-storage'
  params: {
    location: location
    tags: commonTags
    storageAccountName: storageAccountName
    documentsContainerName: documentsContainerName
  }
}

module database 'modules/database.bicep' = {
  name: 'cpi-database'
  params: {
    location: location
    tags: commonTags
    serverName: sqlServerName
    databaseName: sqlDatabaseName
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
    skuName: sqlDatabaseSkuName
    skuTier: sqlDatabaseSkuTier
  }
}

module webapp 'modules/webapp.bicep' = {
  name: 'cpi-webapp'
  params: {
    location: location
    tags: commonTags
    planName: 'cpi-plan'
    planSkuName: appServicePlanSkuName
    planSkuTier: appServicePlanSkuTier
    webAppName: webAppName
    pythonVersion: pythonVersion
    documentsAccountName: storage.outputs.storageAccountName
    documentsContainerName: documentsContainerName
    sqlServerFqdn: database.outputs.fullyQualifiedDomainName
    sqlDatabaseName: database.outputs.databaseName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
  }
}

output baseUrl string = 'https://${webapp.outputs.defaultHostName}'
output webAppName string = webapp.outputs.webAppName
output appServicePlanSku string = webapp.outputs.planSkuName
output sqlServerName string = database.outputs.serverName
output sqlServerFqdn string = database.outputs.fullyQualifiedDomainName
output sqlDatabaseName string = database.outputs.databaseName
output sqlDatabaseSku string = database.outputs.databaseSkuName
output storageAccountName string = storage.outputs.storageAccountName
output documentsContainerName string = storage.outputs.documentsContainerName
