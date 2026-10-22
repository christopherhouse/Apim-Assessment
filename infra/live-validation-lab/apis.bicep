targetScope = 'resourceGroup'

@minLength(1)
param apimName string

@minLength(36)
@maxLength(36)
param tenantId string

@minLength(36)
@maxLength(36)
param frontendResourceClientId string

@minLength(36)
@maxLength(36)
param backendAudienceClientId string

@minLength(36)
@maxLength(36)
param workerClientId string

@description('Canonical HTTPS origin matching the worker certificate and exact private DNS record; no path or port.')
param backendOrigin string

@description('Validated private gateway subnet bounds from the offline parameter writer.')
param gatewayAddressStart string
param gatewayAddressEnd string

@description('Exact private worker address, also the only permitted PLM source.')
param workerPrivateIp string

var inventory = loadJsonContent('./scenarios/inventory.json')
var documents = {
  'e-commerce': loadJsonContent('./scenarios/e-commerce.openapi.json')
  manufacturing: loadJsonContent('./scenarios/manufacturing.openapi.json')
  plm: loadJsonContent('./scenarios/plm.openapi.json')
  'service-management': loadJsonContent('./scenarios/service-management.openapi.json')
  'supply-chain': loadJsonContent('./scenarios/supply-chain.openapi.json')
}
var productIds = [
  'business'
  'partner'
]
var operationTargets = flatten(map(inventory.apis, api => flatten(map(items(documents[api.apiId].paths), path => map(
  filter(items(path.value), operation => contains(['get', 'post', 'patch', 'put', 'delete', 'head', 'options'], operation.key)),
  operation => {
    apiId: api.apiId
    operationId: toLower(operation.value.operationId)
  }
)))))

resource service 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// No separately published AVM policy-fragment module is available.
resource callerFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: service
  name: 'lab-caller-auth'
  properties: {
    description: 'Exact lab tenant, v2 audience, application role and worker caller.'
    format: 'rawxml'
    value: replace(replace(replace(loadTextContent('./policies/caller-auth.xml'),
      '__TENANT_ID__', tenantId), '__FRONTEND_ID__', frontendResourceClientId), '__WORKER_ID__', workerClientId)
  }
}

resource backendFragment 'Microsoft.ApiManagement/service/policyFragments@2024-05-01' = {
  parent: service
  name: 'lab-backend-auth'
  properties: {
    description: 'Remove caller credentials and authenticate only as the APIM system identity.'
    format: 'rawxml'
    value: replace(loadTextContent('./policies/backend-auth.xml'), '__BACKEND_ID__', backendAudienceClientId)
  }
}

module globalPolicy 'br/public:avm/res/api-management/service/policy:0.1.2' = {
  name: 'apis-global-policy'
  params: {
    apiManagementServiceName: apimName
    format: 'rawxml'
    value: replace(replace(replace(loadTextContent('./policies/global.xml'),
      '__GATEWAY_START__', gatewayAddressStart), '__GATEWAY_END__', gatewayAddressEnd), '__WORKER_IP__', workerPrivateIp)
    enableTelemetry: false
  }
  dependsOn: [
    callerFragment
  ]
}

module backends 'br/public:avm/res/api-management/service/backend:0.2.2' = [for api in inventory.apis: {
  name: 'backend-${api.apiId}'
  params: {
    apiManagementServiceName: apimName
    name: 'lab-${api.apiId}'
    protocol: 'http'
    url: '${backendOrigin}/${api.path}'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    enableTelemetry: false
  }
}]

module apis 'br/public:avm/res/api-management/service/api:0.2.2' = [for api in inventory.apis: {
  name: 'api-${api.apiId}'
  params: {
    apiManagementServiceName: apimName
    name: api.apiId
    displayName: documents[api.apiId].info.title
    path: api.path
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    format: 'openapi+json'
    value: string(union(documents[api.apiId], {
      servers: [{ url: '${backendOrigin}/${api.path}' }]
    }))
    serviceUrl: '${backendOrigin}/${api.path}'
    policies: [
      {
        format: 'rawxml'
        value: replace(replace(replace(loadTextContent('./policies/api.xml'), '__API_ID__', api.apiId),
          '__PRODUCT_PREDICATE__', join(map(api.productIds, product => 'context.Product.Id == "${product}"'), ' || ')),
          '__PRIVATE_GUARD__', api.publication == 'privateOnly'
            ? replace(loadTextContent('./policies/plm-guard.xml'), '__WORKER_IP__', workerPrivateIp)
            : '')
      }
    ]
    enableTelemetry: false
  }
  dependsOn: [
    globalPolicy
    backendFragment
    backends
  ]
}]

module products 'br/public:avm/res/api-management/service/product:0.2.3' = [for product in productIds: {
  name: 'product-${product}'
  params: {
    apiManagementServiceName: apimName
    name: product
    displayName: 'Lab ${product}'
    subscriptionRequired: true
    approvalRequired: true
    subscriptionsLimit: 1
    state: 'published'
    apis: map(filter(inventory.apis, api => contains(api.productIds, product)), api => api.apiId)
    policies: [
      {
        format: 'rawxml'
        value: replace(loadTextContent('./policies/product.xml'), '__PRODUCT_ID__', product)
      }
    ]
    enableTelemetry: false
  }
  dependsOn: [
    apis
  ]
}]

module subscriptions 'br/public:avm/res/api-management/service/subscription:0.1.3' = [for (product, index) in productIds: {
  name: 'subscription-${product}'
  params: {
    apiManagementServiceName: apimName
    name: 'lab-${product}'
    displayName: 'Lab ${product} private caller'
    scope: '/products/${product}'
    state: 'active'
    allowTracing: false
    enableTelemetry: false
  }
  dependsOn: [
    products[index]
  ]
}]

module operationPolicies 'br/public:avm/res/api-management/service/api/operation/policy:0.1.0' = [for target in operationTargets: {
  name: 'operation-${target.apiId}-${target.operationId}'
  params: {
    apiManagementServiceName: apimName
    apiName: target.apiId
    operationName: target.operationId
    format: 'rawxml'
    value: replace(loadTextContent('./policies/operation.xml'), '__OPERATION_ID__', target.operationId)
    enableTelemetry: false
  }
  dependsOn: [
    apis
  ]
}]
