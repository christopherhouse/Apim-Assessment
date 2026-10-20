using './worker.bicep'

// Offline fixture only, never an owner deployment configuration.
var fixture = loadJsonContent('./worker.sample.json')
param labId = fixture.labId
param location = fixture.location
param vnetName = fixture.vnetName
param workerVmName = fixture.workerVmName
param workerPrivateIp = fixture.workerPrivateIp
param sshPublicKey = fixture.sshPublicKey
param vmSize = fixture.vmSize
param ubuntuImageVersion = fixture.ubuntuImageVersion
param availabilityZone = fixture.availabilityZone
