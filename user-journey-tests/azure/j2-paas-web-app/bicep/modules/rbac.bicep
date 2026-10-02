// rbac.bicep — what the storefront's own identity is allowed to touch.
//
// Two data-plane grants, scoped to the individual resource rather than the
// resource group: read secrets from the vault, read blobs from the media
// account. The vault and the storage account are looked up rather than created
// here; modules/keyvault.bicep and modules/storage.bicep own them.
//
// Writing a role assignment needs more on the scope than Contributor carries.
// Where that sits with a subscription administrator instead of whoever runs the
// deployment, main.bicep's deployRoleAssignments switch leaves this module out
// and the same two grants are made separately; the design is unchanged either
// way.

@description('Name of the key vault to grant against.')
param keyVaultName string

@description('Name of the storage account to grant against.')
param storageAccountName string

@description('Object id of the storefront web app system-assigned identity.')
param principalId string

// Key Vault Secrets User — read secret contents, nothing else.
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// Storage Blob Data Reader — read and list blobs, no writes.
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource secretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, principalId, keyVaultSecretsUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      keyVaultSecretsUserRoleId
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource blobReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, storageBlobDataReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      storageBlobDataReaderRoleId
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output secretsUserAssignmentId string = secretsUserAssignment.id
output blobReaderAssignmentId string = blobReaderAssignment.id
