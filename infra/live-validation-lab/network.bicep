targetScope = 'resourceGroup'

import { securityRuleType } from 'br/public:avm/res/network/network-security-group:0.5.4'

@export()
@sealed()
type networkType = {
  vnetCidr: string
  gatewayCidr: string
  apimCidr: string
  workerCidr: string
  privateEndpointCidr: string
  @minLength(1)
  @maxLength(16)
  approvedCallerCidrs: string[]
  @minLength(1)
  @maxLength(16)
  workerHttpsEgressCidrs: string[]
}

@description('Validated private network inputs; use the offline parameter writer.')
param network networkType

@description('Owner-selected Azure region.')
param location string

@description('Lab-owned VNet name.')
param vnetName string

@description('Lab-owned worker NAT gateway name.')
param natGatewayName string

@description('Lab-owned worker NAT public IP name.')
param natPublicIpName string

@description('Fixed ownership tags.')
param tags object

func rule(name string, priority int, direction ('Inbound' | 'Outbound'), protocol ('Tcp' | 'Udp' | '*'), source string, destination string, port string, access ('Allow' | 'Deny')) securityRuleType => {
  name: name
  properties: {
    priority: priority
    direction: direction
    protocol: protocol
    sourceAddressPrefix: source
    sourcePortRange: '*'
    destinationAddressPrefix: destination
    destinationPortRange: port
    access: access
  }
}

module natIp 'br/public:avm/res/network/public-ip-address:0.13.0' = {
  name: 'foundation-nat-ip'
  params: {
    name: natPublicIpName
    location: location
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    availabilityZones: []
    tags: tags
    enableTelemetry: false
  }
}

module nat 'br/public:avm/res/network/nat-gateway:2.1.1' = {
  name: 'foundation-nat'
  params: {
    name: natGatewayName
    location: location
    availabilityZone: -1
    natGatewaySku: 'Standard'
    idleTimeoutInMinutes: 4
    publicIpResourceIds: [natIp.outputs.resourceId]
    tags: tags
    enableTelemetry: false
  }
}

var callerRules = [for (cidr, i) in network.approvedCallerCidrs: rule('CallerHttps-${i}', 100 + i, 'Inbound', 'Tcp', cidr, network.gatewayCidr, '443', 'Allow')]
var workerHttpsRules = [for (cidr, i) in network.workerHttpsEgressCidrs: rule('ApprovedHttps-${i}', 300 + i, 'Outbound', 'Tcp', network.workerCidr, cidr, '443', 'Allow')]

module gatewayNsg 'br/public:avm/res/network/network-security-group:0.5.4' = {
  name: 'foundation-gateway-nsg'
  params: {
    name: '${vnetName}-gateway-nsg'
    location: location
    tags: tags
    enableTelemetry: false
    securityRules: concat(
      callerRules,
      [
        rule('WorkerNatHttps', 150, 'Inbound', 'Tcp', '${natIp.outputs.ipAddress}/32', network.gatewayCidr, '443', 'Allow')
        rule('GatewayManager', 200, 'Inbound', 'Tcp', 'GatewayManager', '*', '65200-65535', 'Allow')
        rule('AzureLoadBalancer', 210, 'Inbound', '*', 'AzureLoadBalancer', '*', '*', 'Allow')
        rule('GatewayHealth65502', 220, 'Inbound', 'Tcp', 'VirtualNetwork', network.gatewayCidr, '65502', 'Allow')
        rule('GatewayHealth54321', 230, 'Inbound', 'Tcp', 'VirtualNetwork', network.gatewayCidr, '54321', 'Allow')
        rule('GatewayHealth12345', 240, 'Inbound', 'Udp', 'VirtualNetwork', network.gatewayCidr, '12345', 'Allow')
        rule('DenyOtherInbound', 4096, 'Inbound', '*', '*', '*', '*', 'Deny')
      ]
    )
  }
}

module apimNsg 'br/public:avm/res/network/network-security-group:0.5.4' = {
  name: 'foundation-apim-nsg'
  params: {
    name: '${vnetName}-apim-nsg'
    location: location
    tags: tags
    enableTelemetry: false
    securityRules: [
      rule('GatewayHttps', 100, 'Inbound', 'Tcp', network.gatewayCidr, network.apimCidr, '443', 'Allow')
      rule('WorkerHttps', 110, 'Inbound', 'Tcp', network.workerCidr, network.apimCidr, '443', 'Allow')
      rule('ApiManagementControlPlane', 200, 'Inbound', 'Tcp', 'ApiManagement', network.apimCidr, '3443', 'Allow')
      rule('LoadBalancerHealth', 210, 'Inbound', 'Tcp', 'AzureLoadBalancer', network.apimCidr, '6390-6391', 'Allow')
      rule('InternalCache', 220, 'Inbound', 'Tcp', network.apimCidr, network.apimCidr, '6381-6383', 'Allow')
      rule('InternalCounters', 230, 'Inbound', 'Udp', network.apimCidr, network.apimCidr, '4290', 'Allow')
      rule('DenyOtherInbound', 4096, 'Inbound', '*', '*', '*', '*', 'Deny')
      rule('PrivateBackendHttps', 100, 'Outbound', 'Tcp', network.apimCidr, network.workerCidr, '443', 'Allow')
      rule('PrivateVaultHttps', 110, 'Outbound', 'Tcp', network.apimCidr, network.privateEndpointCidr, '443', 'Allow')
      rule('InternalCacheOutbound', 120, 'Outbound', 'Tcp', network.apimCidr, network.apimCidr, '6381-6383', 'Allow')
      rule('InternalCountersOutbound', 130, 'Outbound', 'Udp', network.apimCidr, network.apimCidr, '4290', 'Allow')
      rule('Storage', 200, 'Outbound', 'Tcp', network.apimCidr, 'Storage', '443', 'Allow')
      rule('Sql', 210, 'Outbound', 'Tcp', network.apimCidr, 'Sql', '1433', 'Allow')
      rule('KeyVault', 220, 'Outbound', 'Tcp', network.apimCidr, 'AzureKeyVault', '443', 'Allow')
      rule('Entra', 230, 'Outbound', 'Tcp', network.apimCidr, 'AzureActiveDirectory', '443', 'Allow')
      rule('MonitorHttps', 240, 'Outbound', 'Tcp', network.apimCidr, 'AzureMonitor', '443', 'Allow')
      rule('MonitorHealth', 250, 'Outbound', 'Tcp', network.apimCidr, 'AzureMonitor', '1886', 'Allow')
      // Classic APIM also needs public CRL/PKI, update and internal diagnostic endpoints.
      rule('PlatformHttp', 300, 'Outbound', 'Tcp', network.apimCidr, 'Internet', '80', 'Allow')
      rule('PlatformHttps', 310, 'Outbound', 'Tcp', network.apimCidr, 'Internet', '443', 'Allow')
      rule('PlatformNtp', 320, 'Outbound', 'Udp', network.apimCidr, 'Internet', '123', 'Allow')
      rule('DnsUdp', 330, 'Outbound', 'Udp', network.apimCidr, 'AzurePlatformDNS', '53', 'Allow')
      rule('DnsTcp', 340, 'Outbound', 'Tcp', network.apimCidr, 'AzurePlatformDNS', '53', 'Allow')
      rule('DenyOtherOutbound', 4096, 'Outbound', '*', '*', '*', '*', 'Deny')
    ]
  }
}

module workerNsg 'br/public:avm/res/network/network-security-group:0.5.4' = {
  name: 'foundation-worker-nsg'
  params: {
    name: '${vnetName}-worker-nsg'
    location: location
    tags: tags
    enableTelemetry: false
    securityRules: concat(
      [
        rule('ApimBackendHttps', 100, 'Inbound', 'Tcp', network.apimCidr, network.workerCidr, '443', 'Allow')
        rule('GatewayDenyBackendHttps', 110, 'Inbound', 'Tcp', network.gatewayCidr, network.workerCidr, '443', 'Allow')
        rule('DenyOtherInbound', 4096, 'Inbound', '*', '*', '*', '*', 'Deny')
        rule('ApimPrivateHttps', 100, 'Outbound', 'Tcp', network.workerCidr, network.apimCidr, '443', 'Allow')
        rule('VaultPrivateHttps', 110, 'Outbound', 'Tcp', network.workerCidr, network.privateEndpointCidr, '443', 'Allow')
        rule('ArmHttps', 200, 'Outbound', 'Tcp', network.workerCidr, 'AzureResourceManager', '443', 'Allow')
        rule('EntraHttps', 210, 'Outbound', 'Tcp', network.workerCidr, 'AzureActiveDirectory', '443', 'Allow')
        rule('MonitorHttps', 220, 'Outbound', 'Tcp', network.workerCidr, 'AzureMonitor', '443', 'Allow')
        rule('StorageHttps', 230, 'Outbound', 'Tcp', network.workerCidr, 'Storage', '443', 'Allow')
        rule('DnsUdp', 240, 'Outbound', 'Udp', network.workerCidr, 'AzurePlatformDNS', '53', 'Allow')
        rule('DnsTcp', 250, 'Outbound', 'Tcp', network.workerCidr, 'AzurePlatformDNS', '53', 'Allow')
        rule('VmAgentHttp', 260, 'Outbound', 'Tcp', network.workerCidr, '168.63.129.16', '80', 'Allow')
        rule('VmAgentFabric', 270, 'Outbound', 'Tcp', network.workerCidr, '168.63.129.16', '32526', 'Allow')
        rule('ManagedIdentityMetadata', 280, 'Outbound', 'Tcp', network.workerCidr, '169.254.169.254', '80', 'Allow')
        rule('DenyOtherOutbound', 4096, 'Outbound', '*', '*', '*', '*', 'Deny')
      ],
      workerHttpsRules
    )
  }
}

module endpointNsg 'br/public:avm/res/network/network-security-group:0.5.4' = {
  name: 'foundation-endpoint-nsg'
  params: {
    name: '${vnetName}-endpoint-nsg'
    location: location
    tags: tags
    enableTelemetry: false
    securityRules: [
      rule('GatewayVaultHttps', 100, 'Inbound', 'Tcp', network.gatewayCidr, network.privateEndpointCidr, '443', 'Allow')
      rule('WorkerVaultHttps', 110, 'Inbound', 'Tcp', network.workerCidr, network.privateEndpointCidr, '443', 'Allow')
      rule('ApimVaultHttps', 120, 'Inbound', 'Tcp', network.apimCidr, network.privateEndpointCidr, '443', 'Allow')
      rule('DenyOtherInbound', 4096, 'Inbound', '*', '*', '*', '*', 'Deny')
      rule('DenyOtherOutbound', 4096, 'Outbound', '*', '*', '*', '*', 'Deny')
    ]
  }
}

module vnet 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'foundation-vnet'
  params: {
    name: vnetName
    location: location
    addressPrefixes: [network.vnetCidr]
    tags: tags
    enableTelemetry: false
    subnets: [
      {
        name: 'gateway'
        addressPrefix: network.gatewayCidr
        networkSecurityGroupResourceId: gatewayNsg.outputs.resourceId
      }
      {
        name: 'apim'
        addressPrefix: network.apimCidr
        networkSecurityGroupResourceId: apimNsg.outputs.resourceId
        serviceEndpoints: ['Microsoft.KeyVault', 'Microsoft.Storage', 'Microsoft.Sql']
      }
      {
        name: 'worker'
        addressPrefix: network.workerCidr
        networkSecurityGroupResourceId: workerNsg.outputs.resourceId
        natGatewayResourceId: nat.outputs.resourceId
        defaultOutboundAccess: false
      }
      {
        name: 'private-endpoints'
        addressPrefix: network.privateEndpointCidr
        networkSecurityGroupResourceId: endpointNsg.outputs.resourceId
        privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
        defaultOutboundAccess: false
      }
    ]
  }
}

@description('Private handoff only; never publish deployment output.')
output vnetResourceId string = vnet.outputs.resourceId

@description('Private handoff only; never publish deployment output.')
output apimSubnetResourceId string = '${vnet.outputs.resourceId}/subnets/apim'

@description('Private handoff only; never publish deployment output.')
output endpointSubnetResourceId string = '${vnet.outputs.resourceId}/subnets/private-endpoints'
