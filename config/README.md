# Local assessment configuration

`sample.psd1` contains synthetic identifiers and the specification's default
settings. It is not a real environment or a validated, runnable configuration.
`Get-Config` and its validation are still task T-003.

When that loader exists, copy the sample to a customer-specific `.psd1` and fill
it locally. Everything in this directory except the sample and this README is
ignored, including edge-range files. Never force-add real configurations.

The planned agent-assisted path also requires explicitly configured,
non-overlapping external restricted-collection and model-safe-analysis roots,
with the restricted root outside every Copilot trusted/allowed directory and no
symlink/junction/traversal path between the roots. The sample does not yet
advertise those keys because the configuration and model-data airlock tasks are
not implemented.
