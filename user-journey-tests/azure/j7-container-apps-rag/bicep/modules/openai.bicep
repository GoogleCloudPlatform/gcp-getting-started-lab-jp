// openai.bicep — the model account behind the portfolio explainer.
// ---------------------------------------------------------------------------
// One Azure OpenAI account, one content filtering policy, one model deployment
// that runs under that policy.
//
// The account sits in its own region parameter rather than following the
// resource group. Model availability is per region and per deployment type, and
// the region that carries the rest of the estate does not necessarily carry the
// model — see the note on openAiLocation in bicep/main.parameters.json.
//
// customSubDomainName is not decoration. Microsoft Entra authentication is only
// available on an account that has one, and a client reaching the account
// through a private endpoint has to address it by that subdomain: the
// *.privatelink.openai.azure.com name is an internal CNAME target and calling it
// directly does not work. The subdomain is global and immutable, which is why it
// carries the same uniqueness suffix as the account name.
//
// publicNetworkAccess is Disabled. Everything reaching this account arrives
// through the private endpoint in modules/privateendpoints.bicep. Turning it
// back on is a one-property change, and it is the difference between an estate
// where the endpoints are load-bearing and one where they are ornamental.
//
// disableLocalAuth switches off the account keys entirely, so the only way in is
// a token for the container app's identity.
// ---------------------------------------------------------------------------

@description('Region for the model account. Set independently of the rest of the estate.')
param location string

@description('Tags applied to every resource in this module.')
param tags object

@description('Globally unique account name. Also becomes the custom subdomain.')
param accountName string

@description('Name of the model deployment the explainer addresses.')
param deploymentName string

@description('Model to deploy.')
param modelName string

@description('Model version to deploy.')
param modelVersion string

@description('Deployment type. Pay-per-token types are GlobalStandard and Standard; the provisioned types bill by the hour whether or not a request is made.')
param deploymentSkuName string

@description('Deployment capacity, in thousands of tokens per minute. 1 is the smallest unit.')
param deploymentCapacity int

@description('Name of the content filtering policy the deployment runs under.')
param contentPolicyName string

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    restrictOutboundNetworkAccess: false
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}

// The stock filter kept refusing perfectly ordinary questions about market
// crashes and aggressive allocations, so the thresholds were re-cut per
// category rather than left on the default. Violence and hate are only blocked
// at High severity on the prompt side; self-harm is blocked from Low upward in
// both directions, which is the line the compliance lead would not move.
resource contentPolicy 'Microsoft.CognitiveServices/accounts/raiPolicies@2026-05-01' = {
  parent: account
  name: contentPolicyName
  properties: {
    basePolicyName: 'Microsoft.Default'
    mode: 'Blocking'
    contentFilters: [
      {
        name: 'Hate'
        blocking: true
        enabled: true
        severityThreshold: 'High'
        source: 'Prompt'
      }
      {
        name: 'Hate'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Completion'
      }
      {
        name: 'Violence'
        blocking: true
        enabled: true
        severityThreshold: 'High'
        source: 'Prompt'
      }
      {
        name: 'Violence'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Completion'
      }
      {
        name: 'Selfharm'
        blocking: true
        enabled: true
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      {
        name: 'Selfharm'
        blocking: true
        enabled: true
        severityThreshold: 'Low'
        source: 'Completion'
      }
      {
        name: 'Sexual'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Prompt'
      }
      {
        name: 'Sexual'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Completion'
      }
    ]
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: deploymentSkuName
    capacity: deploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: contentPolicy.name
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

output accountId string = account.id
output accountName string = account.name
output endpoint string = account.properties.endpoint
output deploymentName string = modelDeployment.name
output contentPolicyName string = contentPolicy.name
