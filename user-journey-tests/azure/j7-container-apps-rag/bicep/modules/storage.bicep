// storage.bicep — where the fund documentation the explainer cites is kept.
//
// One general-purpose v2 account holding a single private container, `docs`.
// The explainer reads it with the container app's identity, so shared-key access
// is switched off. Unlike the model account and the search service this one
// stays reachable over its public endpoint: the seed step uploads the corpus
// from an operator's machine, which has no route into the network.

@description('Region for the storage account.')
param location string

@description('Tags applied to the storage account.')
param tags object

@description('Globally unique storage account name: 3-24 lowercase alphanumerics, no hyphens.')
param storageAccountName string

@description('Name of the blob container holding fund documentation.')
param docsContainerName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    // Left unset, a storage account still accepts TLS 1.0. Pin the floor.
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource docsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: docsContainerName
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output docsContainerName string = docsContainer.name
