# BASH_GOD architecture

This directory documents the current design contracts of BASH_GOD. It is organized by component so a
maintainer can understand and change the product without reconstructing implementation history.

- [Knowledge-base architecture](bash-god-knowledge-base-architecture.md) explains the overall
  catalog, routing, search, and execution boundaries.
- [Catalog contract architecture](catalog-contract-architecture.md) defines the inert `.god` format,
  discovery, compatibility, connection, and eligibility metadata.
- [Terminal runtime architecture](terminal-runtime-architecture.md) defines the inline picker,
  editor, child-process, fallback, and packaging boundaries.
- [Installation and support architecture](installation-and-support-architecture.md) defines
  ownership, relocatable runtime layouts, package-manager boundaries, and the current support
  evidence.
- [Service synchronization](../service-sync.md) is the maintainer runbook for updating a reviewed
  discovery catalog after an upstream native release.

Task plans and implementation history intentionally do not live here. The documents above describe
what BASH_GOD is and how its parts fit together today.
