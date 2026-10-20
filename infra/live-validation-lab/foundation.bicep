targetScope = 'resourceGroup'

import { networkType } from './network.bicep'

@sealed()
type namesType = {
  apim: string
  gatewayIdentity: string
  keyVault: string
  dnsZone: string
  appInsights: string
  logAnalytics: string
  vnet: string
  natGateway: string
  natPublicIp: string
}

@sealed()
type observabilityType = {
  retentionDays: (30 | 60 | 90 | 120 | 180 | 270 | 365)
  @minValue(1)
  @maxValue(10)
  dailyQuotaGb: int
  @minValue(1)
  @maxValue(100)
  samplingPercentage: int
}

@description('Private ownership identifier matching the existing owner-tagged lab resource group.')
@minLength(3)
@maxLength(40)
param labId string

@description('Owner-selected region matching the bootstrap configuration and lab resource group.')
param location string

@description('Exact resource names; runtime names must match the bootstrap Runtime configuration.')
param names namesType

@description('Private APIM administrative contact; never put real contact data in tracked files.')
@secure()
param publisherEmail string

@description('Private APIM publisher display name.')
param publisherName string

@description('Validated canonical IPv4 network inputs; use the offline parameter writer.')
param network networkType

@description('Explicit lab ingestion, retention and sampling bounds.')
param observability observabilityType

var tags = {
  apimAssessmentLab: labId
}

module labNetwork './network.bicep' = {
  name: 'foundation-network'
  params: {
    network: network
    location: location
    vnetName: names.vnet
    natGatewayName: names.natGateway
    natPublicIpName: names.natPublicIp
    tags: tags
  }
}

// AVM workspace 0.16.1 unconditionally retrieves shared keys in its outputs.
resource workspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: names.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: observability.retentionDays
    workspaceCapping: { dailyQuotaGb: observability.dailyQuotaGb }
    features: {
      disableLocalAuth: true
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

module appInsights 'br/public:avm/res/insights/component:0.8.0' = {
  name: 'foundation-insights'
  params: {
    name: names.appInsights
    location: location
    kind: 'web'
    applicationType: 'web'
    workspaceResourceId: workspace.id
    disableLocalAuth: true
    disableIpMasking: false
    retentionInDays: observability.retentionDays
    samplingPercentage: 100
    ingestionMode: 'LogAnalytics'
    tags: tags
    enableTelemetry: false
  }
}

module gatewayIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'foundation-gateway-identity'
  params: {
    name: names.gatewayIdentity
    location: location
    tags: tags
    enableTelemetry: false
  }
}

module challengeZone 'br/public:avm/res/network/dns-zone:0.6.2' = {
  name: 'foundation-challenge-zone'
  params: {
    name: names.dnsZone
    location: 'global'
    tags: tags
    enableTelemetry: false
  }
}

module vaultDns 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  name: 'foundation-vault-dns'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    tags: tags
    enableTelemetry: false
    virtualNetworkLinks: [
      {
        name: 'lab-vnet'
        virtualNetworkResourceId: labNetwork.outputs.vnetResourceId
        registrationEnabled: false
        tags: tags
      }
    ]
  }
}

module vault 'br/public:avm/res/key-vault/vault:0.14.2' = {
  name: 'foundation-vault'
  params: {
    name: names.keyVault
    location: location
    sku: 'standard'
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    enableVaultForDeployment: false
    enableVaultForTemplateDeployment: false
    enableVaultForDiskEncryption: false
    // APIM certificate control-plane access needs its documented trusted-service path.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: [
        { id: labNetwork.outputs.apimSubnetResourceId, ignoreMissingVnetServiceEndpoint: false }
      ]
    }
    privateEndpoints: [
      {
        name: '${names.keyVault}-pe'
        subnetResourceId: labNetwork.outputs.endpointSubnetResourceId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            { privateDnsZoneResourceId: vaultDns.outputs.resourceId }
          ]
        }
        tags: tags
      }
    ]
    diagnosticSettings: [
      {
        name: 'lab-vault'
        workspaceResourceId: workspace.id
        logAnalyticsDestinationType: 'Dedicated'
        logCategoriesAndGroups: [{ category: 'AuditEvent' }]
        metricCategories: []
      }
    ]
    tags: tags
    enableTelemetry: false
  }
}

var messageDiagnostics = {
  request: {
    headers: []
    body: { bytes: 0 }
  }
  response: {
    headers: []
    body: { bytes: 0 }
  }
}

var loggerId = resourceId('Microsoft.ApiManagement/service/loggers', names.apim, 'lab-insights')

module apim 'br/public:avm/res/api-management/service:0.15.0' = {
  name: 'foundation-apim'
  params: {
    name: names.apim
    location: location
    sku: 'Developer'
    skuCapacity: 1
    availabilityZones: []
    virtualNetworkType: 'Internal'
    subnetResourceId: labNetwork.outputs.apimSubnetResourceId
    publicNetworkAccess: 'Enabled'
    managedIdentities: { systemAssigned: true }
    minApiVersion: '2024-05-01'
    publisherEmail: publisherEmail
    publisherName: publisherName
    enableDeveloperPortal: false
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'False'
    }
    diagnosticSettings: [
      {
        name: 'lab-gateway-logs'
        workspaceResourceId: workspace.id
        logAnalyticsDestinationType: 'Dedicated'
        logCategoriesAndGroups: [{ category: 'GatewayLogs' }]
        metricCategories: []
      }
    ]
    loggers: [
      {
        name: 'lab-insights'
        type: 'applicationInsights'
        targetResourceId: appInsights.outputs.resourceId
        isBuffered: true
        credentials: {
          connectionString: appInsights.outputs.connectionString
          identityClientId: 'SystemAssigned'
        }
      }
    ]
    serviceDiagnostics: [
      {
        name: 'applicationinsights'
        loggerResourceId: loggerId
        alwaysLog: 'allErrors'
        frontend: messageDiagnostics
        backend: messageDiagnostics
        httpCorrelationProtocol: 'W3C'
        logClientIp: false
        operationNameFormat: 'Name'
        samplingPercentage: observability.samplingPercentage
        metrics: false
        verbosity: 'error'
      }
    ]
    tags: tags
    enableTelemetry: false
  }
}
