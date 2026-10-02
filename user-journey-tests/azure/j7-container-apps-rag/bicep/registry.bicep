// registry.bicep — the container registry the portfolio explainer image is pushed to.
// ---------------------------------------------------------------------------
// This is a separate template from main.bicep for reasons of ordering rather
// than taste. A container app whose image cannot be pulled provisions as Failed,
// so the image has to exist in a registry before main.bicep runs. The deploy
// sequence is therefore: this template -> build and push the image -> main.bicep.
//
// main.bicep looks the registry up with an `existing` reference; it never
// creates one. Both templates land in the same resource group (car-rg), so the
// single `az group delete` still removes everything.
//
// The admin account is switched on. The container app pulls with a registry
// username and password read at deploy time by main.bicep, rather than with its
// own identity, because granting AcrPull to the app's identity needs a role
// assignment and the platform team does not always hold that right on this
// subscription. Neither credential is stored in this repository.
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

@description('Region for the registry. Follows the resource group.')
param location string = resourceGroup().location

@description('Date this estate should be removed, stamped onto every resource as a tag.')
param autoTeardownDate string

// Registry names are 5-50 alphanumerics with no hyphens and are globally unique
// across all of Azure, so the name carries the same resource-group-derived
// suffix every other global name in this estate carries. main.bicep is handed
// the resolved name rather than recomputing it.
var registryName = 'caracr${uniqueString(resourceGroup().id)}'

var commonTags = {
  Owner: 'migration-test'
  CostCenter: 'test-journeys'
  AutoTeardown: autoTeardownDate
  Journey: 'azure/j7-container-apps-rag'
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: registryName
  location: location
  tags: commonTags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    anonymousPullEnabled: false
  }
}

output registryName string = registry.name
output loginServer string = registry.properties.loginServer
