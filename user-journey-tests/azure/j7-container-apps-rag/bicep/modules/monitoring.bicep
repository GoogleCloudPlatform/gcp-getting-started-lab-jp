// monitoring.bicep — the workspace and the Application Insights component.
//
// Both keep 30 days. The workspace is also what the container apps environment
// streams container stdout to, so it exists whether or not anyone looks at the
// Application Insights side.

@description('Region for both resources.')
param location string

@description('Tags applied to both resources.')
param tags object

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Name of the Application Insights component.')
param appInsightsName string

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    // Workspace-based components take their retention from the workspace above;
    // this property is recorded rather than enforced. Both say 30 either way.
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workspaceCustomerId string = workspace.properties.customerId
output appInsightsName string = appInsights.name
output connectionString string = appInsights.properties.ConnectionString
