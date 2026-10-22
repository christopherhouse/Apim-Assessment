using './apis.bicep'

// Offline fixture only; owner parameters come from the validated private writer.
var fixture = loadJsonContent('./apis.sample.json')
param apimName = fixture.apimName
param tenantId = fixture.tenantId
param frontendResourceClientId = fixture.frontendResourceClientId
param backendAudienceClientId = fixture.backendAudienceClientId
param workerClientId = fixture.workerClientId
param backendOrigin = fixture.backendOrigin
param gatewayAddressStart = '10.240.0.0'
param gatewayAddressEnd = '10.240.0.255'
param workerPrivateIp = fixture.workerPrivateIp
