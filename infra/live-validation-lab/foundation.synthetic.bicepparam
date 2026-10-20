using './foundation.bicep'

// Offline snapshot fixture only. These names and documentation IPs are not deployable inputs.
var fixture = loadJsonContent('./foundation.sample.json')
param labId = fixture.labId
param location = fixture.location
param names = fixture.names
param publisherEmail = fixture.publisherEmail
param publisherName = fixture.publisherName
param network = fixture.network
param observability = fixture.observability
