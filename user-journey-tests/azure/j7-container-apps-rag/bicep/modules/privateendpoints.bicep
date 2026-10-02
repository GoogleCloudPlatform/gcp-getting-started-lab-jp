// privateendpoints.bicep — the two private endpoints the estate depends on.
// ---------------------------------------------------------------------------
// The model account and the search service both refuse traffic arriving over
// their public addresses. These two endpoints are the only way in, and the
// privateDnsZoneGroup on each is what writes the A record that points the
// service's ordinary hostname at the endpoint's address inside the network.
//
// Drop the zone group and the endpoint still exists, but nothing resolves to it:
// the container app looks up the public name, gets the public address, connects,
// and is refused. The zone group is the load-bearing half.
//
// The model account's endpoint carries three zones. Azure documents
// openai.azure.com, cognitiveservices.azure.com and services.ai.azure.com as one
// set for the single `account` subresource, and only zones present in the group
// get records written.
//
// Both are pinned to api-version 2024-05-01, matching the network module.
// ---------------------------------------------------------------------------

@description('Region for the private endpoints. Follows the virtual network, not the target service.')
param location string

@description('Tags applied to both endpoints.')
param tags object

@description('Resource id of the subnet the endpoint network interfaces land in.')
param endpointsSubnetId string

@description('Resource id of the model account.')
param openAiAccountId string

@description('Private DNS zone ids for the model account, in the order Azure documents them.')
param openAiDnsZoneIds array

@description('Resource id of the search service.')
param searchServiceId string

@description('Private DNS zone id for the search service.')
param searchDnsZoneId string

@description('Name of the model account private endpoint.')
param openAiEndpointName string

@description('Name of the search service private endpoint.')
param searchEndpointName string

resource openAiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: openAiEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: endpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${openAiEndpointName}-connection'
        properties: {
          privateLinkServiceId: openAiAccountId
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource openAiZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: openAiPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'openai'
        properties: {
          privateDnsZoneId: openAiDnsZoneIds[0]
        }
      }
      {
        name: 'cognitiveservices'
        properties: {
          privateDnsZoneId: openAiDnsZoneIds[1]
        }
      }
      {
        name: 'aiservices'
        properties: {
          privateDnsZoneId: openAiDnsZoneIds[2]
        }
      }
    ]
  }
}

resource searchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: searchEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: endpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${searchEndpointName}-connection'
        properties: {
          privateLinkServiceId: searchServiceId
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
}

resource searchZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: searchPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'search'
        properties: {
          privateDnsZoneId: searchDnsZoneId
        }
      }
    ]
  }
}

output openAiEndpointId string = openAiPrivateEndpoint.id
output searchEndpointId string = searchPrivateEndpoint.id
