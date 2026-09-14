# BASH_GOD Knowledge Base Architecture

**Status:** Current implementation contract.

## Context / Problem

Operational teams repeatedly need native commands they know exist but cannot recall precisely. Shell
history is incomplete, manuals are broad, and wrapping every CLI would create a second operational
interface to learn and maintain.

BASH_GOD is a searchable, human-readable memory layer for reviewed native commands. It keeps the
native CLI visible, explains the command before it runs, and preserves a direct copy-and-paste path
for every catalog entry.

## Goals

- Make a service, group, or remembered phrase enough to find the right native command.
- Keep catalog content simple, inert, and owned by the service that it describes.
- Render the same command knowledge consistently in indexes, trees, details, and search.
- Offer a reviewed, in-place execution path only when a catalog declares that it is executable.
- Make platform, tool, version, connection, and safety constraints explicit rather than inferred.
- Preserve native CLI ownership: BASH_GOD never becomes a replacement API for Kafka, Kubernetes,
  AWS, MongoDB, Elasticsearch, or host tools.

## Non-goals

- Accept arbitrary native CLI arguments as new `god` subcommands.
- Translate arbitrary Linux commands into macOS commands, or compile shell syntax into another form.
- Discover remote hosts, credentials, or permissions by opening connections on the operator's behalf.
- Schedule, orchestrate, dry-run, or silently repair operational commands.
- Add a service-specific renderer, resolver, or execution branch.

## Architecture Overview

```text
catalog/<service>/service.god
          │ inert, validated data
          ▼
src/catalog.sh ──► src/search.sh ──► src/ui/render.sh / src/ui/tree.sh
          │                                  │
          │ executable catalog + plain TTY search only
          ▼                                  ▼
src/discover.sh ──► src/eligibility.sh ──► src/interaction.sh
                                                   │
                                     reviewed command model
                                      ┌────────────┴────────────┐
                                      ▼                         ▼
                               src/ui/tui.sh             src/resolve.sh
                                      │                         │
                              cmd/god-tui +              src/ui/input.sh
                               internal/tui                     │
                                      └────────────┬────────────┘
                                                   ▼
                                            src/execute.sh
                                                   │
                                           reviewed native child
```

The shell owns routing, catalog validation, command preparation, editing handoff, and execution. The
compiled helper owns only inline browsing and key handling. Catalog text never becomes shell code.

## Key Components

| Component | Responsibility |
|---|---|
| `BASH_GOD.sh`, `god`, `src/core.sh` | Silent source entry point, module loading, style setup, and route dispatch. |
| `catalog/<service>/service.god` | One authoritative, declarative knowledge catalog per service. |
| `src/catalog.sh` | Catalog discovery, parsing, validation, stable record identity, and metadata export. |
| `src/search.sh` | Smart query parsing, ranking, version/intent selection, and static search views. |
| `src/ui/render.sh`, `src/ui/tree.sh`, `src/ui/art.sh` | Human-readable dashboard, detail, tree, and identity presentation. |
| `src/discover.sh` | Explicit resync cache for client path, version, and eligible endpoint target candidates. |
| `src/eligibility.sh` | Bounded local fact collection and pure `eligible`, `ineligible`, or `unknown` decisions. |
| `src/interaction.sh` | Selectable-row policy, lazy command preparation, picker coordination, and final recheck. |
| `src/resolve.sh` | Safe placeholder, client-path, and Target substitution into a reviewed command model. |
| `src/ui/tui.sh`, `cmd/god-tui`, `internal/tui` | Protocol adapter and inline picker; no command editing or execution. |
| `src/ui/input.sh` | Normal native line-editor handoff after the picker exits. |
| `src/execute.sh` | Final reviewed-model validation and native-child terminal handoff. |
| `src/maintenance.sh`, `packaging/` | Direct-install update/removal ownership and release artifact construction. |

## Flow / Behavior

### Knowledge routes

Bare `god` presents the service index. `god <service>` presents groups, a group route presents a
compact command list, and numbered entries expand one command. `--details`, `--tree`, `--tree --full`,
`--keys`, and help routes are always static knowledge views.

`q` and `-q` are the only semantic-search routes. Search ranks catalog fields such as titles,
descriptions, group names, parameters, notes, and native commands. It can be scoped below a service
or group and supports `--any`, `--all`, `--exact`, and `--regex` when a broader or stricter match is
needed.

### Execution boundary

Only a plain TTY search may offer execution, and only for an executable catalog with an eligible
record and a compatible terminal helper. The operator sees the fully resolved command before choosing
it. Enter runs the reviewed record, `e` hands the same command to a normal command-line editor, and
Escape cancels. Editing and placeholder prompts occur after browse mode releases the terminal.

The reviewed command model contains stable record identity, context, risk, compatibility state,
display text, executable template, positional values, and unresolved slots. It is data, not a shell
fragment. `src/execute.sh` refuses incomplete or non-runnable models and launches the native command
with user values carried as positional arguments.

### Static fallback

Rendering remains copy-ready when discovery is unresolved, requirements are not eligible, output is
not a TTY, the terminal is too small, or the helper is absent or incompatible. The fallback is a
feature, not an error path: it preserves the knowledge index without pretending a command is safe to
run locally.

## Extensibility

To add knowledge, edit the closest `catalog/<service>/service.god` group. To add a service, create
one service directory and one `service.god`; the catalog engine discovers its route automatically.
See [CONTRIBUTING.md](../../CONTRIBUTING.md) and the [catalog contract](catalog-contract-architecture.md)
for the record grammar and fake-only verification workflow.

Change shared code only when the behavior is correct for every catalog that declares the relevant
metadata. A shared behavior change must update the owning module, its cross-service smoke coverage,
the contribution guide, and the matching architecture document. Do not solve a catalog-specific
problem with a service-name conditional in the engine.

## Verification

- Syntax checks source the shell modules in Bash and zsh without output.
- Catalog and smoke suites validate static rendering, search, routing, safety labels, requirements,
  discovery models, resolution, and fake-only execution flow.
- Go tests and vet validate the helper protocol and inline picker model.
- PTY suites use synthetic rows and child processes to cover split navigation keys, cancellation,
  editor handoff, placeholder prompts, terminal restoration, stderr streaming, and Ctrl-C handoff.
- Packaging suites validate staged artifacts, installation, updates, and managed-file removal without
  contacting a live service.

## Limitations / Risks

- The catalog is curated rather than exhaustive; native help and upstream documentation remain
  authoritative for less common operations.
- Smart search is ranked word matching, not a general-purpose language model.
- A compatibility range and local eligibility facts cannot prove remote permissions, service health,
  data safety, or network reachability.
- Endpoint targets are non-secret candidates collected only during explicit resync; they are not proof
  that a remote service is reachable.
- Static command spelling is intentionally preserved. BASH_GOD does not translate unreviewed commands
  between operating systems or shell dialects.
