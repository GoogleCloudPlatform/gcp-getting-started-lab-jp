// Service Bus — the handover between intake and the review desk.
//
// Standard tier, because the 2023 build needed nothing Premium offers and the
// broker never signed off the cost. One queue, dead-lettering left on the
// defaults: nobody has looked in the dead-letter sub-queue since it was built,
// which is why the acceptance check asserts it is empty.

@description('Globally unique Service Bus namespace name — becomes a servicebus.windows.net DNS label.')
@minLength(6)
@maxLength(50)
param namespaceName string

@description('Azure region.')
param location string

@description('Tags applied to the namespace.')
param tags object

@description('Queue carrying parsed claims from intake to the review router.')
param reviewQueueName string

resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    zoneRedundant: false
  }
}

resource reviewQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: namespace
  name: reviewQueueName
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    enablePartitioning: false
    requiresDuplicateDetection: false
    requiresSession: false
    maxSizeInMegabytes: 1024
  }
}

output namespaceName string = namespace.name
output namespaceId string = namespace.id
output reviewQueueName string = reviewQueue.name
