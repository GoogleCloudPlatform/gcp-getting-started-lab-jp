// Claims storage account — the one place a claim lives before it is a row.
//
// The branch scanners upload scanned claim PDFs into the `intake` container,
// and the adjuster desktops clear each one out again once the case is attached.
// Everything downstream keys off that single write.
//
// Recovery settings were turned on across the board during the 2024 audit
// response: blob versioning, blob soft delete and container soft delete, all on
// the same 30-day clock the compliance checklist asked for.

@description('Globally unique storage account name — lowercase alphanumerics only, 3-24 characters.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region.')
param location string

@description('Tags applied to the account.')
param tags object

@description('Blob container that receives scanned claim documents.')
param intakeContainerName string

@description('Queue that Event Grid writes blob-created notifications into.')
param intakeQueueName string

@description('Queue the retired v1 claims reader used to drain.')
param archiveFeedQueueName string

@description('Table holding one row per claim per state change.')
param claimStateTableName string

@description('Retention for blob soft delete and container soft delete, in days.')
param softDeleteRetentionDays int

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

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: softDeleteRetentionDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: softDeleteRetentionDays
    }
  }
}

resource intakeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobServices
  name: intakeContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource queueServices 'Microsoft.Storage/storageAccounts/queueServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource intakeQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2024-01-01' = {
  parent: queueServices
  name: intakeQueueName
}

// Fed by its own Event Grid subscription. The reader that used to drain it was
// part of the v1 claims desk, switched off in March 2025.
resource archiveFeedQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2024-01-01' = {
  parent: queueServices
  name: archiveFeedQueueName
}

resource tableServices 'Microsoft.Storage/storageAccounts/tableServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
}

// PartitionKey is the ISO date the claim was received, RowKey is the claim
// reference — with approval steps as `<claim-ref>#<step>`. Chosen in 2023 so a
// day's claims read back as one partition scan.
resource claimStateTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2024-01-01' = {
  parent: tableServices
  name: claimStateTableName
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output intakeContainerName string = intakeContainer.name
output intakeQueueName string = intakeQueue.name
output archiveFeedQueueName string = archiveFeedQueue.name
output claimStateTableName string = claimStateTable.name
