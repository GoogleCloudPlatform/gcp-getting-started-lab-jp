// Event Grid — how a scanned claim PDF becomes work.
//
// One system topic on the claims storage account, and two subscriptions hanging
// off it. The first is the live path: blob-created notifications for the intake
// container land in the claim-intake queue, which the intake processor drains.
//
// The second is older. When the v1 claims desk ran alongside this pipeline it
// took a copy of every write on the account into its own queue, and that
// subscription was never removed when v1 was switched off in March 2025.

@description('Event Grid system topic name.')
param systemTopicName string

@description('Azure region. Must match the region of the source storage account.')
param location string

@description('Tags applied to the system topic.')
param tags object

@description('Resource id of the claims storage account the topic is sourced from.')
param claimsStorageId string

@description('Blob container that receives scanned claim documents.')
param intakeContainerName string

@description('Queue the live intake subscription delivers to.')
param intakeQueueName string

@description('Queue the v1 archive subscription delivers to.')
param archiveFeedQueueName string

resource systemTopic 'Microsoft.EventGrid/systemTopics@2025-02-15' = {
  name: systemTopicName
  location: location
  tags: tags
  properties: {
    source: claimsStorageId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource intakeSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2025-02-15' = {
  parent: systemTopic
  name: 'dfp-egs-intake'
  properties: {
    eventDeliverySchema: 'EventGridSchema'
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/${intakeContainerName}/'
      isSubjectCaseSensitive: false
    }
    destination: {
      endpointType: 'StorageQueue'
      properties: {
        resourceId: claimsStorageId
        queueName: intakeQueueName
      }
    }
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Unfiltered by design of the v1 archiver, which wanted every write on the
// account rather than just the intake container.
resource archiveFeedSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2025-02-15' = {
  parent: systemTopic
  name: 'dfp-egs-v1-archive'
  properties: {
    eventDeliverySchema: 'EventGridSchema'
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      isSubjectCaseSensitive: false
    }
    destination: {
      endpointType: 'StorageQueue'
      properties: {
        resourceId: claimsStorageId
        queueName: archiveFeedQueueName
      }
    }
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}

output systemTopicName string = systemTopic.name
output intakeSubscriptionName string = intakeSubscription.name
output archiveFeedSubscriptionName string = archiveFeedSubscription.name
