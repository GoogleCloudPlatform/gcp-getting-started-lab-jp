// The claims pipeline function app, plus the storage account the Functions
// host needs for itself.
//
// The plan is the one the 2023 build created: a Y1 Dynamic App Service plan on
// Windows. The runtime is Node 22 because that is what the broker's own
// integration samples were written in and nobody has revisited the choice.
//
// Two connections the code needs are supplied as app settings rather than
// bindings config, because the triggers resolve them by setting name:
//   CLAIMS_STORAGE  the queue trigger on claim-intake, and the Tables client
//   SERVICE_BUS     the queue trigger on claims-review

@description('Globally unique function app name — becomes an azurewebsites.net DNS label.')
param functionAppName string

@description('App Service plan name.')
param planName string

@description('Globally unique storage account name for the Functions host itself.')
@minLength(3)
@maxLength(24)
param functionStorageName string

@description('Azure region.')
param location string

@description('Tags applied to every resource in this module.')
param tags object

@description('Name of the claims storage account, created by the storage module.')
param claimsStorageName string

@description('Name of the Service Bus namespace, created by the messaging module.')
param serviceBusNamespaceName string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Storage queue the intake processor triggers on.')
param intakeQueueName string

@description('Service Bus queue the review router triggers on.')
param reviewQueueName string

@description('Table the review router writes claim state rows into.')
param claimStateTableName string

@description('Claim value in JPY at or above which the approval chain is started.')
param claimEscalationThresholdJpy int

@description('How far back the reconciliation pass reads claim state rows, in days.')
param reconcileLookbackDays int

// Created by the storage and messaging modules; looked up here only to build
// the connection strings the Functions host resolves triggers through.
resource claimsStorage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: claimsStorageName
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: serviceBusNamespaceName
}

resource serviceBusRootRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2024-01-01' existing = {
  parent: serviceBusNamespace
  name: 'RootManageSharedAccessKey'
}

resource functionStorage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: functionStorageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
        }
        queue: {
          enabled: true
        }
        table: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
    }
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {}
}

var storageSuffix = environment().suffixes.storage
var functionStorageConnection = 'DefaultEndpointsProtocol=https;AccountName=${functionStorage.name};AccountKey=${functionStorage.listKeys().keys[0].value};EndpointSuffix=${storageSuffix}'
var claimsStorageConnection = 'DefaultEndpointsProtocol=https;AccountName=${claimsStorage.name};AccountKey=${claimsStorage.listKeys().keys[0].value};EndpointSuffix=${storageSuffix}'

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~22'
        }
        {
          name: 'AzureWebJobsStorage'
          value: functionStorageConnection
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: functionStorageConnection
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower('${functionAppName}-content')
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'CLAIMS_STORAGE'
          value: claimsStorageConnection
        }
        {
          name: 'SERVICE_BUS'
          value: serviceBusRootRule.listKeys().primaryConnectionString
        }
        {
          name: 'CLAIMS_INTAKE_QUEUE'
          value: intakeQueueName
        }
        {
          name: 'CLAIMS_REVIEW_QUEUE'
          value: reviewQueueName
        }
        {
          name: 'CLAIM_STATE_TABLE'
          value: claimStateTableName
        }
        {
          name: 'CLAIM_ESCALATION_THRESHOLD_JPY'
          value: string(claimEscalationThresholdJpy)
        }
        {
          name: 'RECONCILE_LOOKBACK_DAYS'
          value: string(reconcileLookbackDays)
        }
      ]
    }
  }
}

output functionAppName string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output planName string = plan.name
output functionStorageName string = functionStorage.name
