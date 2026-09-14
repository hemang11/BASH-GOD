# Catalog Contract Architecture

**Status:** Current implementation contract for executable and display-only catalogs.

## Context / Problem

A command catalog is only useful when its text is readable, its compatibility claims are reviewable,
and the shared runtime can make the same decision for every service. Embedding shell code, renderer
logic, or service-specific execution behavior in catalog data would make those properties impossible
to maintain.

The catalog contract therefore treats every `.god` file as inert, structured text. Catalog authors
state facts; shared modules validate, render, discover, resolve, and execute them generically.

## Goals

- Keep exactly one authoritative `service.god` file per service route.
- Keep commands human-copyable and on one physical line.
- Declare execution, compatibility, local requirements, and connection facts explicitly.
- Keep static knowledge broad while allowing a conservative executable subset.
- Let a new service or command work through shared code without a dispatcher branch.

## Non-goals

- Treat catalog data as executable shell code.
- Infer dependencies by parsing arbitrary shell syntax in `@run`.
- Guess remote facts, credentials, endpoint reachability, or operating-system equivalence.
- Translate one platform's native command into another platform's command.
- Use a successful discovery probe as proof that every sibling executable exists.

## Architecture Overview

```text
service.god
    │
    ├── identity and human-facing records
    ├── execution + connection declaration
    ├── discovery or PATH policy
    ├── compatibility and requirements metadata
    └── native command text
             │
             ▼
        catalog.sh validates and exports data
             │
      ┌──────┴─────────┐
      ▼                ▼
static render      eligible reviewed execution
```

The static branch never executes a command. The executable branch is available only to catalogs that
declare an execution model and only after the shared runtime establishes the required bounded facts.

## Key Components

| Metadata | Meaning |
|---|---|
| `@title`, top-level `@description` | Human-facing service identity and scope. |
| `@group` | A stable navigational group within one service catalog. |
| `@command` through `@end` | One complete, ordered command record. |
| `@mode`, `@risk`, `@description`, `@run` | Command behavior, impact, explanation, and copy-ready native syntax. |
| `@discover` | Declarative lookup for one installed client family and optional service-version probe. |
| `@execution PATH` | Declarative opt-in for a mixed host-tool catalog that uses the caller's PATH. |
| `@connection` | Whether a catalog has no shared target, an endpoint, or client-managed context. |
| `@synced`, `@since`, `@until`, `@intent` | Service review baseline and per-command compatibility/variant facts. |
| `@environment 1`, `@requires` | Requirements Schema 1 service defaults and exact command prerequisites. |

## Flow / Behavior

### Core record shape

Every record has a human-facing command title, mode, description, one physical `@run` line, and
`@end`. Parameters and optional flags use three columns: `NAME | EXAMPLE | MEANING`. Risks use the
specific `WRITE`, `WARN`, or `DELETE` vocabulary.

An executable production catalog declares `@environment 1` once and exactly one non-empty
`@requires` block for every record. Requirements appear after mode/compatibility metadata and before
the human-facing record body. The validator rejects a partial opt-in.

```text
@command Show consumer-group offsets and lag
@mode MODERN
@since 0.10.1
@requires
tool | service:kafka-consumer-groups.sh | present
@description
Shows committed offsets, log-end offsets, and lag for one consumer group.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group <consumer_group> --describe
@end
```

### Execution declarations

Choose one of three models for a catalog:

- `@discover` is for one CLI family, such as Kafka scripts, `kubectl`, `aws`, or a Mongo shell. Its
  ordered `probe`, `root`, `scan`, and `version` rows are declarative lookup facts. The shared
  resolver finds the client only during explicit discovery/resync and rewrites only the declared
  leading client in the reviewed runtime model.
- `@execution PATH` is for intentionally mixed local toolsets such as general host and network
  commands. It has no product version or discovery directory and preserves the catalog spelling.
- A catalog with neither declaration is display-only. It remains searchable and copy-ready but never
  enters the executable picker.

`@discover` and `@execution PATH` are mutually exclusive. Neither permits custom code in a catalog.

### Connection declarations and Target

Every executable catalog declares one connection model:

- `@connection NONE` has no shared endpoint. Individual commands can still expose an explicit host
  placeholder.
- `@connection ENDPOINT <port>` allows explicit resync to cache a non-secret `host:port` candidate.
  A user may supply a `target=host:port` override in the service configuration. The reviewed model
  may replace only the catalog's declared default endpoint or explicit host/port slots; static catalog
  text does not change.
- `@connection CONTEXT` delegates destination selection to a client context, such as Kubernetes
  kubeconfig or AWS profile/region. It has no invented host or port.

`god --paths` reports a resolved client, discovered version when relevant, the service review
baseline, and endpoint Target state. A local listener is a candidate, not proof of a reachable or
authorized service.

### Compatibility and variants

Discovery catalogs record `@synced <version>` once at service level. It says when the catalog was
last reviewed and is displayed once in paths output; it does not mark, hide, or authorize individual
commands.

Each discovery record has `@since <version>` and may have `@until <version>`. These are facts about
the exact shown syntax. When a detected version is outside a record's range, static search preserves
the result with its explanation, while editing and execution are unavailable. `@intent <slug>` joins
overlapping forms of the same operation so the preferred applicable form is selected without losing
the older knowledge.

Use [service synchronization](../service-sync.md) when reviewing a native release. Update a command's
range only from verified native behavior; do not use a service review baseline as a substitute for
per-command compatibility.

### Requirements Schema 1

`@environment 1` supplies scalar defaults for local OS, execution context, and shell dialect.
`@requires` refines those defaults for a record. Supported requirement rows are:

```text
os | local | any|linux|darwin|freebsd
shell | local | none|posix|bash
context | execution | local|remote
tool | local:<name>|service:<name>|remote:<name> | present|gnu|bsd
tool-version | local:<name>|service:<name>|remote:<name> | <comparator><version>
```

`service:<name>` is valid only for a discovery catalog and checks that exact executable in the
resolved directory. A `tool-version` row requires the matching `tool` declaration. Each executable
in a reviewed pipeline or command substitution must be declared; the runtime never tries to infer
dependencies from the command string.

The evaluator returns `eligible`, `ineligible`, or `unknown` from declared requirements and fresh,
bounded facts. Unknown is deliberately conservative: remote facts stay unknown until an approved
source supplies them, and BASH_GOD never opens SSH merely to discover them. Static views preserve all
knowledge; only eligible rows enter the executable picker and are rechecked before edit, prompts, or
launch.

## Extensibility / How to change it

1. Start with the decision table and fake-only workflow in [CONTRIBUTING.md](../../CONTRIBUTING.md).
2. Put service knowledge in `catalog/<service>/service.god`; do not add a service-specific dispatcher,
   resolver, renderer, or execution branch.
3. Use a reviewed native spelling and explicit `@since`, requirements, and risk facts.
4. Add generic parser/evaluator support and cross-service tests before expanding metadata vocabulary.
5. Verify with synthetic clients and isolated cache/config paths; never run the catalog command
   against a live service as a test.

## Verification

- Catalog validation checks record order, required fields, compatibility facts, and Schema 1
  completeness before normal rendering.
- Fake discovery tests prove only declared probes and exact sibling requirements are resolved.
- Resolution tests prove that static commands remain human-copyable while reviewed runtime models
  receive only permitted path, Target, and placeholder substitutions.
- Cross-service smoke tests cover all executable catalogs and prevent a regression from becoming a
  one-service exception.

## Limitations / Risks

- Requirements are local, declarative facts, not a shell compiler or remote capability scanner.
- A present client cannot prove an authenticated account, cluster feature, file existence, or remote
  executable exists.
- Native tooling and vendor behavior change over time; the catalog must be reviewed and synchronized
  deliberately.
- Commands without an executable declaration remain useful knowledge but cannot be launched through
  BASH_GOD.
