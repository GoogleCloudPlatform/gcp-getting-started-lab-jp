// network.bicep — the virtual network the explainer runs inside, and the four
// private DNS zones that make the model and search endpoints resolvable from it.
// ---------------------------------------------------------------------------
// Two subnets:
//
//   apps       delegated to Microsoft.App/environments, which the container
//              apps environment requires. Sized /23 rather than the /27 minimum
//              so a revision swap has room to double its replica count without
//              running the subnet dry.
//   endpoints  holds the network interfaces the private endpoints create. Not
//              delegated to anything — a delegated subnet cannot host them.
//
// The DNS zones are what actually make the private endpoints useful. Without
// them, car-openai-<uniq>.openai.azure.com still resolves to the service's
// public address, the request leaves the network, and the account rejects it
// because public access is switched off. Each zone is linked to the network, so
// Azure's own resolver answers with the private address instead.
//
// The model account carries three zones rather than one. Azure publishes
// openai.azure.com, cognitiveservices.azure.com and services.ai.azure.com as a
// set for one account private endpoint, and the automatic A-record creation
// only covers zones that are present. The explainer only calls the first of the
// three, but leaving the other two out means anything that later reaches for
// the general endpoint silently goes out over the internet and fails.
//
// Every Microsoft.Network resource here is pinned to an api-version no later
// than 2024-05-01. Versions released after 2026-03-31 create subnets with
// defaultOutboundAccess set to false, which would leave the container apps
// environment with no route out to pull its image.
// ---------------------------------------------------------------------------

@description('Region for the virtual network.')
param location string

@description('Tags applied to every resource in this module.')
param tags object

@description('Name of the virtual network.')
param vnetName string

@description('Address space for the virtual network.')
param vnetAddressPrefix string

@description('Address prefix for the container apps subnet. Must be /27 or larger.')
param appsSubnetPrefix string

@description('Address prefix for the subnet holding private endpoint network interfaces.')
param endpointsSubnetPrefix string

var appsSubnetName = 'apps'
var endpointsSubnetName = 'endpoints'

// One zone per public suffix the private endpoints answer for.
var privateDnsZoneNames = [
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.search.windows.net'
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: appsSubnetName
        properties: {
          addressPrefix: appsSubnetPrefix
          delegations: [
            {
              name: 'container-apps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: endpointsSubnetName
        properties: {
          addressPrefix: endpointsSubnetPrefix
        }
      }
    ]
  }
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for zoneName in privateDnsZoneNames: {
    name: zoneName
    // Private DNS zones are not regional resources; 'global' is the only value
    // this property accepts.
    location: 'global'
    tags: tags
  }
]

resource privateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zoneName, index) in privateDnsZoneNames: {
    parent: privateDnsZones[index]
    name: '${vnetName}-link'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

output vnetId string = vnet.id
output vnetName string = vnet.name
output appsSubnetId string = '${vnet.id}/subnets/${appsSubnetName}'
output endpointsSubnetId string = '${vnet.id}/subnets/${endpointsSubnetName}'
output openAiDnsZoneIds array = [
  privateDnsZones[0].id
  privateDnsZones[1].id
  privateDnsZones[2].id
]
output searchDnsZoneId string = privateDnsZones[3].id
