// keyvault.bicep — the shop's one vault.
//
// Created during the 2025 security tidy-up. RBAC permission model, so access is
// granted with role assignments rather than vault access policies.
//
// The vault is seeded with the checkout webhook signing key. The value written
// here is the stand-in the studio put in when the vault was built, pending the
// real key from the payment provider.

@description('Region for the key vault.')
param location string

@description('Tags applied to the key vault.')
param tags object

@description('Globally unique vault name: 3-24 alphanumerics and hyphens, leading letter.')
param keyVaultName string

@description('Name of the checkout webhook signing key secret.')
param checkoutKeySecretName string = 'checkout-webhook-signing-key'

@description('Value written into the checkout signing key secret when the vault is first created.')
param checkoutKeySeedValue string = 'rotate-me-before-launch'

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    // Soft delete cannot be turned off. Purge protection is left off so a
    // torn-down shop can be rebuilt under the same vault name.
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource checkoutKey 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: checkoutKeySecretName
  properties: {
    value: checkoutKeySeedValue
    contentType: 'text/plain'
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output vaultUri string = keyVault.properties.vaultUri
output checkoutKeySecretName string = checkoutKey.name
// Version-less data-plane URI, so the app setting always resolves the current version.
output checkoutKeySecretUri string = '${keyVault.properties.vaultUri}secrets/${checkoutKey.name}'
