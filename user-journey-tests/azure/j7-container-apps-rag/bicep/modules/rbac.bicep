// rbac.bicep — what the explainer's own identity is allowed to touch.
// ---------------------------------------------------------------------------
// Four grants, each scoped to the individual resource rather than the group:
//
//   Cognitive Services OpenAI User   call chat completions, nothing else. Not
//                                    OpenAI Contributor: that adds fine-tuning,
//                                    deployment writes and content-policy writes
//                                    the app has no use for.
//   Search Service Contributor       create and update the index definition.
//   Search Index Data Contributor    load documents into it and query it. The
//                                    split is real — Search Service Contributor
//                                    cannot load documents, and Search Index
//                                    Data Contributor cannot create the index.
//   Storage Blob Data Reader         read the documentation corpus.
//
// All four sit behind main.bicep's deployRoleAssignments switch, because writing
// a role assignment needs more on the scope than Contributor carries. Where that
// right sits with a subscription administrator instead of whoever runs the
// deployment, the switch is off and the same grants are made separately.
//
// The explainer needs a fifth grant, for the conversation store, and it is NOT
// here. Cosmos DB data-plane access is a Microsoft.DocumentDB write rather than
// a Microsoft.Authorization one, so Contributor can make it and it must not be
// lost when this switch goes off. It lives in modules/cosmosrbac.bicep.
// ---------------------------------------------------------------------------

@description('Name of the model account to grant against.')
param openAiAccountName string

@description('Name of the search service to grant against.')
param searchServiceName string

@description('Name of the storage account to grant against.')
param storageAccountName string

@description('Object id of the container app system-assigned identity.')
param principalId string

// Cognitive Services OpenAI User — inference on an existing deployment.
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// Search Service Contributor — manage index definitions, cannot read documents.
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'

// Search Index Data Contributor — read and write documents, cannot define indexes.
var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'

// Storage Blob Data Reader — read and list blobs, no writes.
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: openAiAccountName
}

resource searchService 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: searchServiceName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource openAiUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: openAiAccount
  name: guid(openAiAccount.id, principalId, openAiUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      openAiUserRoleId
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, principalId, searchServiceContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      searchServiceContributorRoleId
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchDataAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, principalId, searchIndexDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      searchIndexDataContributorRoleId
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


output openAiUserAssignmentId string = openAiUserAssignment.id
output searchServiceAssignmentId string = searchServiceAssignment.id
output searchDataAssignmentId string = searchDataAssignment.id
output blobReaderAssignmentId string = blobReaderAssignment.id
