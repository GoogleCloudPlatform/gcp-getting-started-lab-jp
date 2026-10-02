// webapp.bicep — the storefront itself: plan, site, staging slot, and the
// application settings for both.
//
// The plan defaults to S1 Standard because the shop keeps a staging slot and
// slots start at the Standard tier; the SKU arrives as a parameter so the tier
// can be moved without editing this file. The site carries a system-assigned
// identity; the role assignments that give it something to do live in
// modules/rbac.bicep.
//
// Application settings are their own child resource rather than a siteConfig
// block, so the site (and therefore its identity) exists before any setting
// that has to be resolved against another resource.

@description('Region for the plan and the site.')
param location string

@description('Tags applied to the plan, the site and the slot.')
param tags object

@description('App Service plan name.')
param planName string

@description('App Service plan SKU. Slots need Standard or better.')
param planSkuName string

@description('App Service plan tier matching planSkuName.')
param planSkuTier string

@description('Site name. Becomes an azurewebsites.net DNS label, so it carries a suffix.')
param webAppName string

@description('Name of the staging deployment slot.')
param stagingSlotName string = 'staging'

@description('Django SECRET_KEY. Generated at deploy time.')
@secure()
param djangoSecretKey string

@description('PostgreSQL host the storefront connects to.')
param databaseHost string

@description('PostgreSQL database name.')
param databaseName string

@description('PostgreSQL login.')
param databaseLogin string

@description('PostgreSQL password. Generated at deploy time.')
@secure()
param databasePassword string

@description('Storage account holding product images.')
param mediaAccountName string

@description('Blob endpoint of the media storage account.')
param mediaBlobEndpoint string

@description('Blob container holding product images.')
param mediaContainerName string

@description('Data-plane URI of the key vault.')
param keyVaultUri string

@description('Data-plane URI of the checkout webhook signing key secret.')
param checkoutKeySecretUri string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Python runtime the storefront targets.')
param pythonVersion string = '3.12'

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
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      appCommandLine: 'gunicorn --bind=0.0.0.0:8000 --timeout 120 --access-logfile - --error-logfile - webshop.wsgi:application'
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
    DJANGO_DEBUG: '0'
    DJANGO_SECRET_KEY: djangoSecretKey
    DJANGO_ALLOWED_HOSTS: '*'
    PWA_DB_HOST: databaseHost
    PWA_DB_NAME: databaseName
    PWA_DB_USER: databaseLogin
    PWA_DB_PASSWORD: databasePassword
    PWA_DB_SSLMODE: 'require'
    PWA_MEDIA_ACCOUNT: mediaAccountName
    PWA_MEDIA_BLOB_ENDPOINT: mediaBlobEndpoint
    PWA_MEDIA_CONTAINER: mediaContainerName
    PWA_KEY_VAULT_URI: keyVaultUri
    PWA_CHECKOUT_SECRET_NAME: 'checkout-webhook-signing-key'
    PWA_CHECKOUT_SIGNING_KEY: '@Microsoft.KeyVault(SecretUri=${checkoutKeySecretUri})'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
    OTEL_SERVICE_NAME: 'webshop-storefront'
  }
}

// Staging slot, added during the 2024 Front Door work.
resource stagingSlot 'Microsoft.Web/sites/slots@2024-11-01' = {
  parent: webApp
  name: stagingSlotName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      appCommandLine: 'gunicorn --bind=0.0.0.0:8000 --timeout 120 --access-logfile - --error-logfile - webshop.wsgi:application'
      alwaysOn: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      numberOfWorkers: 1
    }
  }
}

resource stagingSlotSettings 'Microsoft.Web/sites/slots/config@2024-11-01' = {
  parent: stagingSlot
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    PYTHONUNBUFFERED: '1'
    DJANGO_DEBUG: '0'
    DJANGO_SECRET_KEY: djangoSecretKey
    DJANGO_ALLOWED_HOSTS: '*'
    PWA_DB_HOST: databaseHost
    PWA_DB_NAME: databaseName
    PWA_DB_USER: databaseLogin
    PWA_DB_PASSWORD: databasePassword
    PWA_DB_SSLMODE: 'require'
    PWA_MEDIA_ACCOUNT: mediaAccountName
    PWA_MEDIA_BLOB_ENDPOINT: mediaBlobEndpoint
    PWA_MEDIA_CONTAINER: 'media-old'
    ApplicationInsightsAgent_EXTENSION_VERSION: 'disabled'
  }
}

output webAppName string = webApp.name
output webAppId string = webApp.id
output defaultHostName string = webApp.properties.defaultHostName
output stagingSlotName string = stagingSlot.name
output stagingHostName string = stagingSlot.properties.defaultHostName
output principalId string = webApp.identity.principalId
