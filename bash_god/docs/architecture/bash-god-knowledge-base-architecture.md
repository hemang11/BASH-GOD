# BASH_GOD Knowledge Base Architecture

**Status:** Implemented in BASH_GOD 0.0.1.1

## Context / Problem

BASH_GOD solves a memory problem: remembering the right native DevOps command when it is needed. Searching chat, notes, browser history, and shell history is slow, while wrapping every native CLI would create another interface to learn.

> BASH_GOD is a curated memory layer for frequently used DevOps operations. It displays native commands and never executes catalogued recipes.

The operator copies a command, replaces placeholders, reviews warnings, and runs it directly. Native CLIs remain the source of truth; their help commands can be catalogued like any other command.

## Goals

- Make `god` plus a platform name enough to rediscover operations.
- Present a compact, visually distinct index instead of a long manual page.
- Keep copy-ready examples one short route away.
- Use exact, case-insensitive service and group routes.
- Search every field while displaying concise command candidates.
- Keep one readable `.god` file per platform.
- Add platforms and commands without changing the dispatcher.
- Parse catalogs as inert text and remain silent when sourced.

## Non-goals

- Executing or wrapping Kafka, MongoDB, Kubernetes, AWS, SSH, or other tools.
- Accepting native operational arguments through `god`.
- Treating command titles as executable subcommands.
- Reproducing every native CLI option.
- Discovering hosts, opening SSH sessions, or changing state.
- Providing orchestration or dry-run behavior today.

## Decision / Implementation Summary

BASH_GOD is a service-directory-backed catalog with a generic validator, dispatcher, search engine,
and terminal renderer. Each platform owns one `catalog/<service>/service.god`; groups and command
records live inside that file. There is no file per command or group.

The UI uses progressive disclosure:

1. Bare `god` shows a terminal-only identity followed by platforms and discovery shortcuts.
2. `god kafka` shows a short group map with counts and one operation preview.
3. `god kafka consume` shows a numbered index of one-line commands.
4. `--details` expands every command below the current root, service, or group scope.
5. `god kafka consume 1` focuses the same detail view on one command.
6. `q` or `-q` searches globally or below the current service or group.

Help, tree, details, numbered entries, and search read the same records, preventing separate command registries from drifting.

## Architecture Overview

```text
shell startup                 executable use
     |                             |
     +-- BASH_GOD.sh          god -+
                    \          /
                     v        v
                    bash_god/core.sh
                    - initialize and dispatch
                              |
          +-------------------+-------------------+-------------------+
          |                   |                   |                   |
          v                   v                   v                   v
  bash_god/catalog.sh   bash_god/art.sh    bash_god/render.sh   specialized views
                                            /            \
                                           v              v
                               bash_god/search.sh  bash_god/tree.sh
                                           \              /
                                            v            v
          bash_god/catalog/<service>/service.god
```

No path continues from catalog command text to a native CLI.

## Key Components

```text
BASH_GOD.sh
god
README.md
LICENSE
bash_god/
  AGENTS.md
  art.sh
  core.sh
  catalog.sh
  render.sh
  search.sh
  tree.sh
  catalog/
    aws/
      service.god
    general/
      service.god
    elasticsearch/
      service.god
    k8s/
      service.god
    kafka/
      service.god
    mongo/
      service.god
    network/
      service.god
  docs/
    architecture/
      bash-god-knowledge-base-architecture.md
  tests/
    smoke.sh
```

- `bash_god/AGENTS.md` is the toolkit-scoped catalog-authoring guide for humans and coding agents.
- `LICENSE` applies the MIT license to the toolkit.
- `README.md` is the approachable installation, usage, and extension guide.
- `BASH_GOD.sh` is the single sourced entry point and loads the CLI silently.
- `god` is an executable wrapper for direct use and testing.
- `core.sh` owns initialization, shared styling primitives, module loading, and routing.
- `catalog.sh` owns catalog discovery, service-route resolution, and grammar validation.
- `art.sh` owns the pre-rendered six-line identity and its TTY gate; sourcing it is silent and only
  bare `god` may render it.
- `render.sh` owns normal root, service, group, and command views.
- `search.sh` owns query parsing, matching, ranking, list/tree/detail search views, and search help.
- `tree.sh` owns root, service, and group hierarchy rendering.
- `catalog/general/service.god` holds host, operating-system, process, file, and resource knowledge.
- `catalog/network/service.god` holds vendor-neutral interfaces, ports, DNS resolvers, connectivity,
  HTTP, and SSH knowledge.
- `catalog/aws/service.god` holds AWS identity and read-only Route 53 inventory knowledge.
- Elasticsearch, Kubernetes, Kafka, and MongoDB each own the matching service catalog directory.
- `tests/smoke.sh` verifies that BASH_GOD only shows catalog knowledge in Bash and zsh.
- Existing aliases and functions remain in `BASH_GOD.sh`; the knowledge layer does not reinterpret them.

Current service routes are `aws`, `elasticsearch`, `general`, `k8s`, `kafka`, `mongo`, and `network`.
Compatibility modes remain searchable metadata; only older ZooKeeper-era Kafka syntax receives a
visible `[LEGACY]` badge.

## Catalog Format

A platform file contains metadata followed by ordered groups and command records:

```text
@title Kafka commands
@description
Curated Kafka commands. BASH_GOD never executes them.

@group offset
@command Show consumer-group offsets and lag
@mode MODERN
@description
Shows committed offsets, log-end offsets, and lag.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group connections --describe
@params
--bootstrap-server | localhost:9092 | Broker used to reach the cluster
--group | connections | Consumer group to inspect
--describe | flag | Display offsets and lag
@notes
Add client properties when the cluster requires them.
@end
```

Rules:

- One `@title` and top-level `@description` must precede all groups.
- Every `@group NAME` creates an exact navigable group route.
- Every `@command TITLE` requires `@mode`, non-empty `@description`, and exactly one physical `@run` line.
- `@mode` is `LOCAL`, `MODERN`, `LEGACY-ZK`, or `KRAFT`. It remains searchable metadata, but the
  terminal renderer keeps normal modes visually silent and displays only `LEGACY-ZK` as `[LEGACY]`.
- `@params` and `@optional` rows use `NAME | EXAMPLE | MEANING`.
- `@risk WRITE`, `@risk WARN`, and `@risk DELETE` distinguish normal writes, high-impact non-delete
  operations, and removals.
- `@notes` is optional.
- `@end` closes each command record.
- Group names and command titles are unique within their scopes, ignoring case.

Catalogs are never sourced, evaluated, passed to a shell, or sent to an operational executable. Only
regular, non-symlink files at `catalog/<valid-service-name>/service.god` are accepted. The parent
directory becomes the exact case-insensitive service route.

## Flow / Behavior

### Root and service index

Bare `god` on a TTY shows the pre-rendered six-line BASH GOD logo, then platforms, command counts,
and quick-start routes. `god help` and `god --help` show the same useful dashboard content without the
logo. Redirected or piped stdout also omits it, so logs and automation receive only functional text.
Navigation vocabulary remains available separately through `god --keys`.

`god kafka`, `god kafka help`, and `god kafka --help` are equivalent. They show each group route, its command count, the first operation title, and a `+N more` hint. This keeps the service map within one screen.

### Group commands and help

`god kafka consume` displays every operation as a numbered title and one copy-ready command. Commands remain one physical line; the renderer never inserts continuation backslashes.

`god kafka consume 1` focuses on one operation and adds a parameter table, optional parameters, and a short note when present. The number selects knowledge only and is never passed to Kafka.

`god kafka consume --details` expands every operation in the group with its description, command,
parameter meanings, optional flags, and notes. It is deliberately longer than the default group view.

The same key can deliberately widen the blast radius: `god kafka --details` expands every Kafka
group, while `god --details` expands every catalog command. These are display-only views; catalog
commands remain inert.

`god kafka consume help` and `god kafka consume --help` show only operation names and descriptions.

Command titles are knowledge entries, not more route tokens. “Show consumer-group offsets and lag” is found through `god kafka offset`; BASH_GOD never invokes it.

### Tree and numbered entries

```text
god --tree
god --tree --full
god tree kafka
god kafka --tree
god kafka --tree --full
god tree kafka offset
god kafka offset --tree
god kafka offset --tree --full
```

Tree views use real terminal branches and progressive depth so their default form fits on one screen:

- `god --tree` shows services and their groups.
- `god kafka --tree` shows Kafka groups with command counts.
- `god kafka offset --tree` reveals the numbered operation names inside one group.
- Adding `--full` at root, service, or group scope explicitly adds each native command line beneath
  its numbered operation title.

The default trees deliberately omit command bodies. Full trees are the explicit, high-volume view:
`god kafka native --tree --full` shows the complete native-help branch through every `@run` line.

`--details` works at root, service, and group scope. `<number>` is the sole contextual selector: use
`god kafka GROUP <number>` for one focused explanation after a group has printed its numbered rows.
The value, such as `03`, is a universal UI selector rather than a platform-specific command name.

### Search

```text
god -q "Get all consumers from a group"
god q consumer lag
god -q unavailable leader
god q --any consumer group
god q --all consumer group
god q --exact 'active members'
god q --regex -- 'offset|lag'
god q "Get all consumers from a group" --tree
god q "Get all consumers from a group" --tree --full
god q unavailable leader --details
god kafka q "describe topic" --tree
god kafka topics q "describe topic" --tree --full
god q --help
```

All semantic lookup begins with `q` or `-q`; there are no separate `search`, `find`, or `query`
routes. Default smart search removes conversational filler words, normalizes common plurals, allows
prefix-related word variants, keeps records with the greatest query-word coverage, and ranks those
records by matches in the title, route, and command body. This lets remembered wording find a command
without letting weak one-word hits overwhelm stronger results.

Explicit modes are available when the operator wants different semantics:

- `--any` returns every record matching at least one meaningful word.
- `--all` requires every meaningful word to match one record.
- `--exact` requires one case-insensitive literal phrase.
- `--regex` accepts one case-insensitive POSIX extended regular expression.

Search covers service and group names plus each record's title, mode, risk, description, native
command, parameters, optional parameters, and notes. `god q --help` keeps these choices discoverable.
Placing `q` after a service or group restricts the same search engine to that scope; it does not
change matching semantics. Thus `god kafka q WORDS` searches Kafka only, and
`god kafka topics q WORDS` searches only Kafka's `topics` group.

Results remain compact: each match shows its exact `god SERVICE GROUP <number>` route, operation
title, and `WRITE`, `WARN`, or `DELETE` marker when applicable. The actual search result contains the
numeric value, such as `god kafka health 3`; run that route to open the focused parameter explanation.

Trailing view keys are parsed separately from query text. `--tree` groups only the matches by
service and group, `--tree --full` adds each matching `@run` line, `--details` expands every match,
and `--help` or `--keys` opens search-specific usage. A literal query token that looks like a view
flag can follow `--` to end option parsing.

### Routing and exit codes

Service and group names require exact matches but ignore case, so `god KAFKA OFFSET` resolves normally. Partial names are search terms, not routes. Unknown routes return contextual help and never guess.

`god --keys`, `god kafka --keys`, and `god kafka offset --keys` show the same navigation vocabulary
with examples for the current scope. The routing invariant is that `--help`, `--tree`, `--details`,
`--keys`, and `q`/`-q` resolve at root, service, group, and search scopes wherever meaningful.
`--quiet` is an exact global option accepted anywhere and suppresses decorative home artwork without
changing the selected view; `-q` remains the query route. `--full` always modifies `--tree`;
`<number>` always requires numbered group rows. `god --version`
and root-level `god -v` print only
`BASH_GOD 0.0.1.1` and `License: MIT`; they do not report the host shell version.

- `0`: successful display or search with matches.
- `1`: valid search with no matches.
- `2`: invalid syntax, route, regex, style setting, or catalog data.

## Visual Design

- The six-line BASH GOD logo is pre-rendered in `art.sh`; BASH_GOD never shells out to `figlet`,
  `toilet`, or another banner generator.
- Only bare `god` on a TTY renders the logo and slogan. `god help`, scoped routes, redirected or piped
  output, and errors never do. The global exact `--quiet` option suppresses it explicitly.
- Every top-level TTY invocation prints one leading blank line to separate the command output from the
  shell prompt. Non-TTY output stays unpadded, and an invocation-depth guard prevents recursive tree
  routing from producing duplicate blank lines.
- Magenta framed banners identify normal views; tree mode uses a compact branch heading to save rows.
- Cyan routes and bullets show navigation.
- Green `$` lines identify commands to copy.
- Yellow `WRITE`, `WARN`, and `DELETE` markers identify state-changing or high-impact entries.
- Dim text carries descriptions and secondary guidance.

Color is automatic only on a terminal. `GOD_COLOR=always|never|auto` controls the normal policy, but
`NO_COLOR` is authoritative and disables ANSI even when `GOD_COLOR=always`. It does not suppress the
plain logo on a TTY; `--quiet` controls decoration. UTF-8 locales use box drawing and bullets; other
locales fall back to ASCII for normal views.

## Extensibility

Use `bash_god/AGENTS.md` as the authoritative contribution workflow and field reference.

To add a Kafka operation, append one `@command ... @end` record beneath the appropriate `@group` in
`catalog/kafka/service.god`. No dispatcher or help-table change is required.

To add a platform, create its service directory and primary catalog, such as
`bash_god/catalog/mongo/service.god`:

```text
@title MongoDB commands
@description
Curated MongoDB commands.
@group service
@command Check MongoDB service status
@mode LOCAL
@description
Shows whether the local mongod service is running.
@run
systemctl status mongod
@end
```

After validation, root help, `god mongo`, tree, and search discover it automatically. Use placeholders such as `<database_name>` for local values; never put secrets in a catalog.

## Verification

- Root, service, group, numbered entry, help, details, compact tree, full command tree, and contextual
  keys, including the cross-scope routing matrix.
- Smart conversational, any-word, all-word, exact-phrase, and regex search, including trailing tree,
  full-tree, details, help, and keys views at global, service, and group scope.
- Service-directory discovery and separate catalog, normal-rendering, search, and tree modules.
- BASH_GOD version output and the toolkit-local MIT license.
- Exact case-insensitive routing and contextual unknown-route errors.
- Success, no-match, and invalid-input exit codes.
- Silent sourcing in Bash and zsh.
- Catalog validation and inert handling of command text.
- Automatic color, authoritative `NO_COLOR`, forced color modes, and ASCII fallback for normal views.
- Copy-ready wrapping without invoking Kafka or another native tool.
- Pre-rendered artwork only for bare TTY `god`, exact slogan rendering, global `--quiet`, and
  logo-free help, scoped, redirected, piped, and error views.

## Limitations / Risks

- Catalog coverage is intentionally curated rather than exhaustive; less common native operations still require
  native help or upstream documentation.
- Each service currently has exactly one authoritative `service.god`; the directory layout reserves
  room for a future multi-file service format but does not enable one yet.
- Native versions may change flags; native help remains authoritative.
- Smart search is a local ranked word matcher, not an embedding model or full natural-language engine;
  prefixes and simple plural normalization can still produce false positives or miss distant synonyms.
- Renderers use fixed widths rather than detecting terminal width.
- The pre-rendered logo uses Unicode block characters; `--quiet` provides a decoration-free view for
  terminals where those glyphs are undesirable.
- BASH_GOD neither substitutes placeholders nor validates copied commands.
- Warnings cannot prevent an operator from running a risky command.
