targetScope = 'resourceGroup'

@description('Private lab ownership identifier matching the existing resource group.')
@minLength(3)
@maxLength(40)
param labId string

@description('Owner-approved region matching the existing foundation.')
param location string

@description('Existing lab VNet; the worker subnet retains its foundation NSG and NAT.')
param vnetName string

@description('Worker name matching the owner bootstrap Runtime configuration.')
param workerVmName string

@description('Validated, unreserved static IPv4 address in the existing worker subnet.')
param workerPrivateIp string

@description('Public provisioning key only; no SSH ingress is opened and guest SSH is masked.')
@secure()
param sshPublicKey string

@description('Owner-approved small VM SKU; availability/quota/cost remain private live gates.')
@allowed(['Standard_B2ls_v2', 'Standard_B2s'])
param vmSize string

@description('Owner-selected Ubuntu 24.04 image version, or latest within this fixed image family.')
param ubuntuImageVersion string

@description('Owner-verified zone supported by the selected image/SKU in this region.')
@minValue(1)
@maxValue(3)
param availabilityZone int

module worker 'br/public:avm/res/compute/virtual-machine:0.22.3' = {
  name: 'lab-private-worker'
  params: {
    name: workerVmName
    computerName: 'lab-worker'
    location: location
    vmSize: vmSize
    osType: 'Linux'
    adminUsername: 'labadmin'
    disablePasswordAuthentication: true
    publicKeys: [{ keyData: sshPublicKey, path: '/home/labadmin/.ssh/authorized_keys' }]
    managedIdentities: { systemAssigned: true }
    availabilityZone: availabilityZone
    securityType: 'TrustedLaunch'
    secureBootEnabled: true
    vTpmEnabled: true
    imageReference: {
      publisher: 'Canonical'
      offer: 'ubuntu-24_04-lts'
      sku: 'server'
      version: ubuntuImageVersion
    }
    osDisk: {
      name: '${workerVmName}-os'
      diskSizeGB: 32
      createOption: 'FromImage'
      deleteOption: 'Delete'
      caching: 'ReadWrite'
      managedDisk: { storageAccountType: 'StandardSSD_LRS' }
    }
    dataDisks: []
    nicConfigurations: [
      {
        name: '${workerVmName}-nic'
        deleteOption: 'Delete'
        enableIPForwarding: false
        enableAcceleratedNetworking: false
        dnsServers: ['AzureProvidedDNS']
        ipConfigurations: [
          {
            name: 'private'
            subnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'worker')
            privateIPAllocationMethod: 'Static'
            privateIPAddress: workerPrivateIp
            privateIPAddressVersion: 'IPv4'
          }
        ]
      }
    ]
    customData: loadTextContent('./worker/cloud-init.yaml')
    provisionVMAgent: true
    allowExtensionOperations: true
    bootDiagnostics: false
    patchMode: 'AutomaticByPlatform'
    patchAssessmentMode: 'AutomaticByPlatform'
    bypassPlatformSafetyChecksOnUserSchedule: false
    publicNetworkAccess: 'Disabled'
    networkAccessPolicy: 'DenyAll'
    tags: { apimAssessmentLab: labId }
    enableTelemetry: false
  }
}
