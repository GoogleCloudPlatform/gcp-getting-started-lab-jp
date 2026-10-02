// webapp.bicep — the portal itself: the plan, the site, and the configuration
// that tells the site where its two dependencies are.
//
// The plan is B1 Basic. The portal is busy for a fortnight either side of
// registration and quiet the rest of the year, and B1 is the smallest plan that
// supports keeping the site warm, which matters because the first request after
// an idle period was taking long enough for students to complain.
//
// The site has NO managed identity. Both dependencies are reached with
// credentials that this module reads out of the resources themselves and writes
// into configuration: the storage account key through listKeys(), and the SQL
// login and password composed into an ADO.NET string on the site's connection
// strings collection, where the portal blade puts it. That is what the web team
// configured by hand in 2025 and what this template reproduces, and it is why
// the deployment needs nothing beyond Contributor on the resource group.
//
// Application settings and connection strings are separate child resources of
// the site, and they are ordered one after the other: two writes to the same
// site configuration in the same deployment can otherwise race.

@description('Region for the plan and the site.')
param location string

@description('Tags applied to the plan and the site.')
param tags object

@description('App Service plan name.')
param planName string

@description('App Service plan SKU.')
param planSkuName string

@description('App Service plan tier matching planSkuName.')
param planSkuTier string

@description('Site name. Becomes an azurewebsites.net DNS label, so it carries a suffix.')
param webAppName string

@description('Python runtime the portal targets.')
param pythonVersion string

@description('Storage account holding the document library.')
param documentsAccountName string

@description('Blob container holding the document library.')
param documentsContainerName string

@description('Fully qualified name of the SQL logical server.')
param sqlServerFqdn string

@description('Name of the portal database.')
param sqlDatabaseName string

@description('SQL administrator login the portal signs in with.')
param sqlAdminLogin string

@description('SQL administrator password the portal signs in with. Generated at deploy time.')
@secure()
param sqlAdminPassword string

// Read back rather than passed in: the key never leaves this module, so it
// never appears in a module output or in deployment history as a plain value.
resource documentsAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: documentsAccountName
}

resource plan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: planName
  location: location
  tags: tags
  sku: {
    name: planSkuName
    tier: planSkuTier
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      appCommandLine: 'gunicorn --bind=0.0.0.0:8000 --timeout 120 --access-logfile - --error-logfile - portal:app'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      healthCheckPath: '/health'
      numberOfWorkers: 1
    }
  }
}

resource webAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    PYTHONUNBUFFERED: '1'
    AZURE_STORAGE_CONNECTION_STRING: 'DefaultEndpointsProtocol=https;AccountName=${documentsAccount.name};AccountKey=${documentsAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    CPI_STORAGE_ACCOUNT: documentsAccount.name
    CPI_DOCUMENTS_CONTAINER: documentsContainerName
    CPI_SQL_DATABASE: sqlDatabaseName
  }
}

// The portal blade writes the database credentials here rather than into the
// application settings above, so this is where they are. App Service exposes
// the entry to the worker as SQLAZURECONNSTR_PortalDb.
resource webAppConnectionStrings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'connectionstrings'
  properties: {
    PortalDb: {
      type: 'SQLAzure'
      value: 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User ID=${sqlAdminLogin};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    }
  }
  dependsOn: [
    webAppSettings
  ]
}

output webAppName string = webApp.name
output webAppId string = webApp.id
output defaultHostName string = webApp.properties.defaultHostName
output planName string = plan.name
output planSkuName string = plan.sku.name
