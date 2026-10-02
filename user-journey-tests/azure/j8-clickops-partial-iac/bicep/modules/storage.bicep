// storage.bicep — the portal's document library.
//
// One general-purpose v2 account holding a single private blob container. The
// registrar's office exports notices and forms into it, and the portal lists
// and serves them back. The portal authenticates with the account key rather
// than an identity, so shared-key access stays on; the container itself is
// private and everything is served through the site.

@description('Region for the storage account.')
param location string

@description('Tags applied to the storage account.')
param tags object

@description('Globally unique storage account name: 3-24 lowercase alphanumerics, no hyphens.')
param storageAccountName string

@description('Name of the blob container holding student documents.')
param documentsContainerName string

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
    // The portal reads the library with the account key, so the key path has to
    // stay open. Switching this off takes the site down until it is rewritten
    // to use an identity.
    allowSharedKeyAccess: true
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

resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: documentsContainerName
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output documentsContainerName string = documentsContainer.name
