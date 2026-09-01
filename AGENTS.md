# BASH_GOD agent entry point

Before changing this repository, read [`CONTRIBUTING.md`](CONTRIBUTING.md), then read
[`bash_god/AGENTS.md`](bash_god/AGENTS.md) in full.

For catalog work, start with the contribution guide's decision table and use its fake-only
verification workflow. Keep service knowledge in `bash_god/catalog/<service>/service.god`; do not
add a service-specific dispatcher, resolver, renderer, or execution branch.

For shared-engine work, make the behavior metadata-driven across every service, update the relevant
shared smoke coverage, and keep the architecture and catalog contract in sync. Do not commit, tag,
publish, or push unless explicitly asked.
