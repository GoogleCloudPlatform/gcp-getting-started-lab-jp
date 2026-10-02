// The claims-intake operator (fictional) — claims intake and review platform.
//
// One resource group (dfp-rg) holds the whole estate. Deploy order is Bicep's
// problem: the storage module lands first because the function app and the
// Event Grid system topic both take its name as a parameter, and the messaging
// module lands before the function app for the same reason.
//
// Everything here is Standard tier or serverless. Log and Application Insights
// retention sits at the 30-day floor because the claims team only ever looks at
// the last fortnight.

@description('Azure region for every resource. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('YYYY-MM-DD date carried on the AutoTeardown tag of every resource.')
param autoTeardownDate string

@description('Log Analytics and Application Insights retention, in days.')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Blob soft-delete and container soft-delete retention on the claims account, in days.')
@minValue(1)
@maxValue(365)
param blobSoftDeleteRetentionDays int = 30

@description('Claim value in JPY at or above which the approval chain is started instead of auto-routing.')
param claimEscalationThresholdJpy int = 500000

@description('How far back the reconciliation pass reads claim state rows, in days.')
param reconcileLookbackDays int = 45

var namePrefix = 'dfp'
var uniq = uniqueString(resourceGroup().id)

var tags = {
  Owner: 'migration-test'
  CostCenter: 'test-journeys'
  AutoTeardown: autoTeardownDate
  Journey: 'azure/j4-durable-functions-pipeline'
}

// Names the pipeline agrees on end to end: the Bicep creates them, the app
// settings carry them, and the function code reads them from the environment.
var intakeContainerName = 'intake'
var intakeQueueName = 'claim-intake'
var archiveFeedQueueName = 'v1-archive-feed'
var claimStateTableName = 'claimstate'
var reviewQueueName = 'claims-review'

// Both of these are globally unique DNS labels, so they carry the suffix.
var claimsStorageName = '${namePrefix}claims${uniq}'
var functionStorageName = '${namePrefix}fn${uniq}'

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      immediatePurgeDataOn30Days: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Workspace-based Application Insights. The classic mode was retired, and the
// claims team never built a dashboard on top of it either way — this exists
// because the function app template asked for a key.
resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${namePrefix}-appi'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
    RetentionInDays: logRetentionDays
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

module claimsStorage 'modules/claims-storage.bicep' = {
  name: 'dfp-claims-storage'
  params: {
    storageAccountName: claimsStorageName
    location: location
    tags: tags
    intakeContainerName: intakeContainerName
    intakeQueueName: intakeQueueName
    archiveFeedQueueName: archiveFeedQueueName
    claimStateTableName: claimStateTableName
    softDeleteRetentionDays: blobSoftDeleteRetentionDays
  }
}

module messaging 'modules/messaging.bicep' = {
  name: 'dfp-messaging'
  params: {
    namespaceName: '${namePrefix}-sb-${uniq}'
    location: location
    tags: tags
    reviewQueueName: reviewQueueName
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'dfp-function-app'
  params: {
    functionAppName: '${namePrefix}-fn-${uniq}'
    planName: '${namePrefix}-plan'
    functionStorageName: functionStorageName
    location: location
    tags: tags
    claimsStorageName: claimsStorage.outputs.storageAccountName
    serviceBusNamespaceName: messaging.outputs.namespaceName
    appInsightsConnectionString: insights.properties.ConnectionString
    intakeQueueName: intakeQueueName
    reviewQueueName: messaging.outputs.reviewQueueName
    claimStateTableName: claimsStorage.outputs.claimStateTableName
    claimEscalationThresholdJpy: claimEscalationThresholdJpy
    reconcileLookbackDays: reconcileLookbackDays
  }
}

module events 'modules/events.bicep' = {
  name: 'dfp-events'
  params: {
    systemTopicName: '${namePrefix}-egt-claims'
    location: location
    tags: tags
    claimsStorageId: claimsStorage.outputs.storageAccountId
    intakeContainerName: intakeContainerName
    intakeQueueName: intakeQueueName
    archiveFeedQueueName: archiveFeedQueueName
  }
}

output resourceGroupName string = resourceGroup().name
output claimsStorageAccount string = claimsStorage.outputs.storageAccountName
output intakeContainer string = intakeContainerName
output claimStateTable string = claimStateTableName
output serviceBusNamespace string = messaging.outputs.namespaceName
output reviewQueue string = messaging.outputs.reviewQueueName
output functionAppName string = functionApp.outputs.functionAppName
output functionAppHostName string = functionApp.outputs.defaultHostName
