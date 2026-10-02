// cosmos.bicep — the conversation store behind /history.
// ---------------------------------------------------------------------------
// Serverless, SQL API, one database and one container partitioned on the
// session id. Serverless is the right shape for a few thousand explanations a
// month: nothing is provisioned, nothing bills when the app is idle, and there
// is no throughput figure to get wrong.
//
// Two consequences of serverless that the template has to respect:
//   * the account is single-region, so `locations` carries exactly one entry
//   * no throughput may be passed on the database or the container. Passing
//     any — including an empty options object with autoscale settings — is an
//     error, not a warning, so `options` is omitted from both child resources.
//
// Account keys stay on, because the account is only reachable over its public
// endpoint and the explainer authenticates with its identity through a data
// plane role assignment instead (modules/rbac.bicep). Those assignments are a
// Cosmos-specific mechanism, not Azure role assignments — different resource
// type, different role definition ids, different permission to create them.
// ---------------------------------------------------------------------------

@description('Region for the account.')
param location string

@description('Tags applied to the account.')
param tags object

@description('Globally unique account name: 3-44 lowercase alphanumerics and hyphens.')
param accountName string

@description('Name of the SQL database.')
param databaseName string

@description('Name of the container holding conversation turns.')
param containerName string

resource account 'Microsoft.DocumentDB/databaseAccounts@2026-03-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: 'Tls12'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2026-03-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2026-03-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/sessionId'
        ]
        kind: 'Hash'
      }
      // Explanations are only ever read back by session, and nobody queries the
      // body text, so everything but the partition key and the timestamp is
      // excluded from the index.
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/sessionId/?'
          }
          {
            path: '/createdAt/?'
          }
        ]
        excludedPaths: [
          {
            path: '/*'
          }
        ]
      }
    }
  }
}

output accountName string = account.name
output accountId string = account.id
output documentEndpoint string = account.properties.documentEndpoint
output databaseName string = database.name
output containerName string = container.name
