# Versioned JSON contracts

Versioned manifest, model, and findings JSON schemas live here. The implemented
`manifest.schema.json` is validated before each manifest write with
`Test-Json -SchemaFile`; model and findings contracts remain planned. Follow
specification sections 6, 8, and 10, use camelCase fields and stable keys, and do
not turn unavailable collector data into an empty successful result.
