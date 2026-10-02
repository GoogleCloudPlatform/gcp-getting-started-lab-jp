// main.bicep — the robo-advisory portfolio explainer.
// ---------------------------------------------------------------------------
// Everything lands in one resource group (car-rg) so the whole estate can be
// removed with a single `az group delete`.
//
// bicep/registry.bicep runs FIRST and separately. It creates the container
// registry, and the explainer image has to be pushed into it before this
// template runs: a container app whose image cannot be pulled provisions as
// Failed and takes the deployment down with it. This template looks the registry
// up rather than creating one.
//
// Composition order is expressed through module inputs rather than dependsOn:
//   network + monitoring + storage + cosmos
//     -> model account + search service
//     -> private endpoints for both
//     -> container apps environment and app
//     -> role assignments for the app's identity
//
// Two regions, not one. Everything follows the resource group except the model
// account, which takes openAiLocation. Azure publishes model availability per
// region AND per deployment type, and the region carrying the rest of the estate
// does not necessarily carry the model at the deployment type in use. Splitting
// it out means moving the account is a parameter change rather than a rewrite.
// Note the account is still reached through a private endpoint in the estate's
// own region — a private endpoint and its target do not have to share one.
//
// The two SKUs a subscription is most likely to argue with — the search tier and
// the model deployment type/capacity — are parameters for the same reason.
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

@description('Azure region for the estate. Everything except the model account follows this.')
param location string = resourceGroup().location

@description('Azure region for the model account. Defaults to the estate region; model availability may require another.')
param openAiLocation string = location

@description('Date this estate should be removed, stamped onto every resource as a tag.')
param autoTeardownDate string

@description('Name of the container registry created by bicep/registry.bicep.')
param registryName string

@description('Fully qualified image reference for the explainer, including registry login server and tag.')
param containerImage string

@description('Pricing tier for the search service. The free tier is one-per-subscription and cannot take a private endpoint.')
@allowed([
  'basic'
  'standard'
  'standard2'
])
param searchSku string = 'basic'

@description('Model deployed behind the explainer.')
param openAiModelName string = 'gpt-4o-mini'

@description('Version of that model.')
param openAiModelVersion string = '2024-07-18'

@description('Deployment type. GlobalStandard and Standard bill per token; the provisioned types bill hourly whether or not a request is made.')
@allowed([
  'GlobalStandard'
  'Standard'
  'DataZoneStandard'
])
param openAiDeploymentSku string = 'GlobalStandard'

@description('Deployment capacity in thousands of tokens per minute.')
@minValue(1)
param openAiDeploymentCapacity int = 1

@description('Mode the explainer generates in. "live" calls the model; "stub" returns a deterministic analysis over the same retrieval path.')
@allowed([
  'live'
  'stub'
])
param llmMode string = 'stub'

@description('Whether this deployment creates the container app identity\'s Azure role assignments for the model account, the search service and the documentation storage. Writing a role assignment needs more than Contributor on the scope; where that is held elsewhere, the grants are applied by the subscription administrator and this switch is off.')
param deployRoleAssignments bool = true

@description('Whether this deployment creates the container app identity\'s Cosmos DB data-plane assignment. Kept separate from deployRoleAssignments because this one is a Microsoft.DocumentDB write that Contributor can make, so turning the other switch off must not take conversation history with it.')
param deployCosmosDataPlaneRole bool = true

// Storage accounts, Cosmos DB accounts, model accounts, search services and
// container registries are all global DNS labels, so each name carries a suffix
// derived from the resource group id.
var uniqueSuffix = uniqueString(resourceGroup().id)

var commonTags = {
  Owner: 'migration-test'
  CostCenter: 'test-journeys'
  AutoTeardown: autoTeardownDate
  Journey: 'azure/j7-container-apps-rag'
}

var vnetName = 'car-vnet'
var vnetAddressPrefix = '10.40.0.0/16'
var appsSubnetPrefix = '10.40.0.0/23'
var endpointsSubnetPrefix = '10.40.2.0/28'

var storageAccountName = 'cardocs${uniqueSuffix}'
var docsContainerName = 'docs'
var cosmosAccountName = 'car-cosmos-${uniqueSuffix}'
var cosmosDatabaseName = 'explainer'
var cosmosContainerName = 'chat-history'
var openAiAccountName = 'car-openai-${uniqueSuffix}'
var openAiDeploymentName = 'explainer'
var contentPolicyName = 'car-explainer-filters'
var searchServiceName = 'car-search-${uniqueSuffix}'
var searchIndexName = 'fund-docs'
var environmentName = 'car-cae'
var containerAppName = 'car-advisor'
var containerPort = 8000

module network 'modules/network.bicep' = {
  name: 'car-network'
  params: {
    location: location
    tags: commonTags
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    appsSubnetPrefix: appsSubnetPrefix
    endpointsSubnetPrefix: endpointsSubnetPrefix
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'car-monitoring'
  params: {
    location: location
    tags: commonTags
    workspaceName: 'car-logs'
    appInsightsName: 'car-appi'
  }
}

module storage 'modules/storage.bicep' = {
  name: 'car-storage'
  params: {
    location: location
    tags: commonTags
    storageAccountName: storageAccountName
    docsContainerName: docsContainerName
  }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'car-cosmos'
  params: {
    location: location
    tags: commonTags
    accountName: cosmosAccountName
    databaseName: cosmosDatabaseName
    containerName: cosmosContainerName
  }
}

module openai 'modules/openai.bicep' = {
  name: 'car-openai'
  params: {
    location: openAiLocation
    tags: commonTags
    accountName: openAiAccountName
    deploymentName: openAiDeploymentName
    modelName: openAiModelName
    modelVersion: openAiModelVersion
    deploymentSkuName: openAiDeploymentSku
    deploymentCapacity: openAiDeploymentCapacity
    contentPolicyName: contentPolicyName
  }
}

module search 'modules/search.bicep' = {
  name: 'car-search'
  params: {
    location: location
    tags: commonTags
    searchServiceName: searchServiceName
    searchSku: searchSku
  }
}

module privateEndpoints 'modules/privateendpoints.bicep' = {
  name: 'car-private-endpoints'
  params: {
    location: location
    tags: commonTags
    endpointsSubnetId: network.outputs.endpointsSubnetId
    openAiAccountId: openai.outputs.accountId
    openAiDnsZoneIds: network.outputs.openAiDnsZoneIds
    searchServiceId: search.outputs.searchServiceId
    searchDnsZoneId: network.outputs.searchDnsZoneId
    openAiEndpointName: 'car-pe-openai'
    searchEndpointName: 'car-pe-search'
  }
}

module containerapp 'modules/containerapp.bicep' = {
  name: 'car-containerapp'
  params: {
    location: location
    tags: commonTags
    environmentName: environmentName
    containerAppName: containerAppName
    infrastructureSubnetId: network.outputs.appsSubnetId
    workspaceName: monitoring.outputs.workspaceName
    registryName: registryName
    containerImage: containerImage
    containerPort: containerPort
    appEnvironmentVariables: [
      {
        name: 'PORT'
        value: string(containerPort)
      }
      {
        name: 'LLM_MODE'
        value: llmMode
      }
      {
        name: 'CAR_OPENAI_ENDPOINT'
        value: openai.outputs.endpoint
      }
      {
        name: 'CAR_OPENAI_DEPLOYMENT'
        value: openai.outputs.deploymentName
      }
      {
        name: 'CAR_OPENAI_API_VERSION'
        value: '2024-10-21'
      }
      {
        name: 'CAR_SEARCH_ENDPOINT'
        value: search.outputs.searchEndpoint
      }
      {
        name: 'CAR_SEARCH_INDEX'
        value: searchIndexName
      }
      {
        name: 'CAR_COSMOS_ENDPOINT'
        value: cosmos.outputs.documentEndpoint
      }
      {
        name: 'CAR_COSMOS_DATABASE'
        value: cosmos.outputs.databaseName
      }
      {
        name: 'CAR_COSMOS_CONTAINER'
        value: cosmos.outputs.containerName
      }
      {
        name: 'CAR_DOCS_ACCOUNT'
        value: storage.outputs.storageAccountName
      }
      {
        name: 'CAR_DOCS_BLOB_ENDPOINT'
        value: storage.outputs.blobEndpoint
      }
      {
        name: 'CAR_DOCS_CONTAINER'
        value: storage.outputs.docsContainerName
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: monitoring.outputs.connectionString
      }
    ]
  }
  dependsOn: [
    privateEndpoints
  ]
}

module rbac 'modules/rbac.bicep' = if (deployRoleAssignments) {
  name: 'car-rbac'
  params: {
    openAiAccountName: openai.outputs.accountName
    searchServiceName: search.outputs.searchServiceName
    storageAccountName: storage.outputs.storageAccountName
    principalId: containerapp.outputs.principalId
  }
}

module cosmosrbac 'modules/cosmosrbac.bicep' = if (deployCosmosDataPlaneRole) {
  name: 'car-cosmos-rbac'
  params: {
    cosmosAccountName: cosmos.outputs.accountName
    principalId: containerapp.outputs.principalId
  }
}

output baseUrl string = 'https://${containerapp.outputs.fqdn}'
output containerAppName string = containerapp.outputs.containerAppName
output environmentName string = containerapp.outputs.environmentName
output openAiAccountName string = openai.outputs.accountName
output openAiLocation string = openAiLocation
output openAiEndpoint string = openai.outputs.endpoint
output openAiDeploymentName string = openai.outputs.deploymentName
output contentPolicyName string = openai.outputs.contentPolicyName
output searchServiceName string = search.outputs.searchServiceName
output searchEndpoint string = search.outputs.searchEndpoint
output searchIndexName string = searchIndexName
output searchSku string = searchSku
output storageAccountName string = storage.outputs.storageAccountName
output docsContainerName string = storage.outputs.docsContainerName
output cosmosAccountName string = cosmos.outputs.accountName
output vnetName string = network.outputs.vnetName
output llmMode string = llmMode
