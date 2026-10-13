# Versioned JSON contracts

Versioned manifest, model, and findings JSON schemas live here.
`manifest.schema.json` is validated before each manifest write with
`Test-Json -SchemaFile`. Closed schemas are also implemented for the API,
operation, policy-matrix, subscription, and network models; remaining model and
findings contracts stay planned. Follow specification sections 6, 8, and 10,
use camelCase fields and stable keys, and do not turn unavailable collector data
into an empty successful result.
