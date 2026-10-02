// frontdoor.bicep — the edge the shop put in front of the storefront in 2024,
// after a Golden Week weekend when product images made the site crawl.
//
// Standard tier: one endpoint, one origin group pointing at the App Service
// site, one route, and a rules engine carrying a single rule for the product
// image path.

@description('Tags applied to the profile and the endpoint.')
param tags object

@description('Front Door profile name.')
param profileName string

@description('Endpoint name. Becomes an azurefd.net DNS label, so it carries a suffix.')
param endpointName string

@description('Host name of the App Service site behind the endpoint.')
param originHostName string

@description('Prefix on which product images are served.')
param mediaPathPrefix string = '/media/'

resource profile 'Microsoft.Cdn/profiles@2025-06-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2025-06-01' = {
  parent: profile
  name: endpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2025-06-01' = {
  parent: profile
  name: 'pwa-web-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
    sessionAffinityState: 'Disabled'
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2025-06-01' = {
  parent: originGroup
  name: 'pwa-web-origin'
  properties: {
    hostName: originHostName
    originHostHeader: originHostName
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enforceCertificateNameCheck: true
    enabledState: 'Enabled'
  }
}

resource ruleSet 'Microsoft.Cdn/profiles/ruleSets@2025-06-01' = {
  parent: profile
  name: 'pwaMediaRules'
}

// Product images are immutable once uploaded, so the edge is told to hold them
// for a day and to stamp the browser-facing cache header on the way out.
resource mediaCacheRule 'Microsoft.Cdn/profiles/ruleSets/rules@2025-06-01' = {
  parent: ruleSet
  name: 'productImageCaching'
  properties: {
    order: 1
    matchProcessingBehavior: 'Stop'
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
          operator: 'BeginsWith'
          matchValues: [
            mediaPathPrefix
          ]
          negateCondition: false
          transforms: [
            'Lowercase'
          ]
        }
      }
    ]
    actions: [
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'Cache-Control'
          value: 'public, max-age=86400, immutable'
        }
      }
      {
        name: 'RouteConfigurationOverride'
        parameters: {
          typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
          cacheConfiguration: {
            queryStringCachingBehavior: 'IgnoreQueryString'
            cacheBehavior: 'OverrideAlways'
            cacheDuration: '1.00:00:00'
            isCompressionEnabled: 'Disabled'
          }
        }
      }
    ]
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2025-06-01' = {
  parent: endpoint
  name: 'pwa-default-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    ruleSets: [
      {
        id: ruleSet.id
      }
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [
    origin
  ]
}

output profileName string = profile.name
output endpointHostName string = endpoint.properties.hostName
output ruleSetName string = ruleSet.name
