// search.bicep — the index the explainer retrieves fund documentation from.
// ---------------------------------------------------------------------------
// Basic tier, one replica, one partition. The free tier would be cheaper still,
// but a subscription gets exactly one free search service and the free tier
// cannot take a private endpoint at all, so Basic is the floor for a service
// that has to be reachable only from inside the network.
//
// Basic also draws the line on how the index gets filled. Private-endpoint
// support for indexers that run a skillset stops above this tier, so nothing
// here pulls from blob storage on a schedule. The explainer reads the documents
// itself and pushes them into the index, which is why POST /admin/reindex exists
// in the app rather than an indexer existing here.
//
// disableLocalAuth switches the admin and query keys off. Once it is true the
// authOptions block must not be set at all — the two are mutually exclusive, and
// setting both fails the deployment.
// ---------------------------------------------------------------------------

@description('Region for the search service.')
param location string

@description('Tags applied to the search service.')
param tags object

@description('Globally unique search service name: 2-60 lowercase alphanumerics and hyphens.')
param searchServiceName string

@description('Pricing tier. The free tier is one-per-subscription and cannot take a private endpoint.')
param searchSku string

resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: searchSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'Default'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    semanticSearch: 'disabled'
  }
}

output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'
