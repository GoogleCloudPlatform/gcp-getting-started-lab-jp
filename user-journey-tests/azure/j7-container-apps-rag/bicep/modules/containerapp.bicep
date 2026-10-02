// containerapp.bicep — the environment and the one app that runs in it.
// ---------------------------------------------------------------------------
// The environment is a workload profiles environment integrated into the
// estate's own network. That is not the default shape and it is not free: it
// creates a managed resource group of its own, a standard load balancer and a
// public address for egress. It is here because the model account and the search
// service only answer on private endpoints, and only a network-integrated
// environment can reach them.
//
// Consequences of that choice which are encoded below:
//   * the subnet must be delegated to Microsoft.App/environments, and the
//     delegation lives in modules/network.bicep
//   * workloadProfiles must be present. It is the only signal in the template
//     that selects a workload profiles environment over the legacy
//     consumption-only one, and the legacy one cannot use a delegated subnet
//   * platformReservedCidr, platformReservedDnsIP and dockerBridgeCidr are left
//     out entirely: they apply only to the legacy environment
//
// The environment keeps an external address so the explainer stays reachable for
// acceptance checks; only the two back-end services are private.
//
// The app runs one container on the built-in Consumption profile, 0.5 vCPU and
// 1 GiB — the smallest pair above the 0.25/0.5Gi floor that leaves room for the
// Azure SDK client set. Bicep types the cpu property as an integer even though
// fractional cores are what the service expects, so the value goes through
// json() rather than being written as a decimal literal.
// ---------------------------------------------------------------------------

@description('Region for the environment and the app.')
param location string

@description('Tags applied to both resources.')
param tags object

@description('Name of the container apps environment.')
param environmentName string

@description('Name of the container app.')
param containerAppName string

@description('Resource id of the subnet delegated to Microsoft.App/environments.')
param infrastructureSubnetId string

@description('Name of the Log Analytics workspace container output is streamed to.')
param workspaceName string

@description('Name of the container registry the image is pulled from.')
param registryName string

@description('Fully qualified image reference, including the registry login server and the tag.')
param containerImage string

@description('Port the application listens on.')
param containerPort int

@description('Environment variables handed to the container.')
param appEnvironmentVariables array

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: workspaceName
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = {
  name: registryName
}

resource environment 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: false
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    publicNetworkAccess: 'Enabled'
    zoneRedundant: false
  }
}

resource containerApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      // One revision at a time. Publishing a new one deactivates its
      // predecessor rather than leaving both addressable, so there is no
      // revision to weight traffic across and no way to hold an old one warm.
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: containerPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'registry-password'
          value: registry.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: registry.properties.loginServer
          username: registry.listCredentials().username
          passwordSecretRef: 'registry-password'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'advisor'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: appEnvironmentVariables
          // Both probes call /health/live, which touches nothing outside the
          // process. /health reaches the model account and the search service
          // over their private endpoints, and a probe that waits on those
          // restarts the container every time one of them is slow.
          //
          // timeoutSeconds is stated rather than left out: the property
          // defaults to one second, which is not a realistic budget for an
          // HTTP round trip to a replica that is still warming up.
          probes: [
            {
              // Nothing is scheduled until a request arrives, so a replica has
              // to pull the image and import the Azure SDK set before it can
              // answer. The liveness probe does not start until this passes.
              type: 'Startup'
              httpGet: {
                path: '/health/live'
                port: containerPort
              }
              periodSeconds: 5
              failureThreshold: 30
              timeoutSeconds: 5
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: containerPort
              }
              periodSeconds: 30
              failureThreshold: 3
              timeoutSeconds: 5
            }
          ]
        }
      ]
      scale: {
        // Nobody asks the explainer anything overnight, and a cold start costs
        // a few seconds against a request that already waits on the model.
        minReplicas: 0
        maxReplicas: 3
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: '20'
              }
            }
          }
        ]
      }
    }
  }
}

output environmentId string = environment.id
output environmentName string = environment.name
output containerAppName string = containerApp.name
output principalId string = containerApp.identity.principalId
output fqdn string = containerApp.properties.configuration.ingress.fqdn
