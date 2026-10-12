# Local assessment configuration

`sample.psd1` contains synthetic identifiers and the specification's default
settings. Replace both `Output` placeholders with absolute paths before loading
it. It is not a real environment or a directly runnable customer configuration.

The private `Get-Config` helper now validates required keys and nested types,
GUIDs, enum values, positive windows/weights/thresholds, strictly ascending
usage buckets, and absolute non-overlapping output roots. Existing symbolic
links/junctions in either output path are rejected. The helper normalizes valid
output paths but does not create them.

When that loader exists, copy the sample to a customer-specific `.psd1` and fill
it locally. Everything in this directory except the sample and this README is
ignored, including edge-range files. Never force-add real configurations.

The planned agent-assisted path also requires explicitly configured,
non-overlapping external restricted-collection and model-safe-analysis roots,
with the restricted root outside every Copilot trusted/allowed directory and no
symlink/junction/traversal path between the roots. The sample does not yet
enable agent mode automatically. Future broker code must call `Get-Config` with
agent-assisted validation and provide every Copilot-visible path; validation
fails closed when that list is empty or overlaps the restricted root.
