// cosmosrbac.bicep — the explainer's data-plane access to the conversation store.
// ---------------------------------------------------------------------------
// This is one grant, and it is in its own module because it is a different
// mechanism from the four in modules/rbac.bicep and carries a different
// permission requirement.
//
// Data-plane access to a Cosmos DB SQL API account is not an Azure role
// assignment. It is a sqlRoleAssignments resource under the account, pointing at
// a role definition that is also a child of the account and has its own fixed
// ids. Creating one is a Microsoft.DocumentDB write, not a
// Microsoft.Authorization write, so Contributor on the resource group is
// sufficient — which is exactly why it does not belong behind the same switch
// as the four that need more than Contributor. Folding it in there would mean a
// deployment that turns that switch off loses conversation history for no
// reason.
//
// It has a switch of its own all the same, for the case where the grant is
// managed outside this template.
// ---------------------------------------------------------------------------

@description('Name of the Cosmos DB account to grant against.')
param cosmosAccountName string

@description('Object id of the container app system-assigned identity.')
param principalId string

// Cosmos DB Built-in Data Contributor. A fixed id scoped to the account, and
// not interchangeable with anything under Microsoft.Authorization.
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2026-03-15' existing = {
  name: cosmosAccountName
}

resource cosmosDataAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2026-03-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, principalId, cosmosDataContributorRoleId)
  properties: {
    principalId: principalId
    roleDefinitionId: resourceId(
      'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions',
      cosmosAccountName,
      cosmosDataContributorRoleId
    )
    scope: cosmosAccount.id
  }
}

output cosmosDataAssignmentId string = cosmosDataAssignment.id
