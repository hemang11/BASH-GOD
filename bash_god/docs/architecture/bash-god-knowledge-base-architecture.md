# BASH_GOD Knowledge Base Architecture

**Status:** Implemented in BASH_GOD 0.0.2.4.1. Reviewed execution is now generic across the current
service catalogs.

## Context / Problem

BASH_GOD solves a memory problem: remembering the right native DevOps command when it is needed. Searching chat, notes, browser history, and shell history is slow, while wrapping every native CLI would create another interface to learn.

> BASH_GOD shows you the resolved command and runs it only after you confirm. It never runs anything
> you have not seen and approved. Discoverable catalogs resolve one tool family; PATH catalogs use the
> same reviewed picker through the caller's normal lookup. Every catalog command remains copy-ready.

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
- For a service that declares `@discover`, resolve the install path and version once; for one that
  declares `@execution PATH`, use normal PATH lookup without inventing a product version. In either
  case, fill in values safely and run only the reviewed command.

## Non-goals

- Accepting native operational arguments through `god`.
- Treating command titles as executable subcommands.
- Reproducing every native CLI option.
- Discovering hosts, opening SSH sessions, or changing state on a service's behalf beyond what a
  confirmed command itself does.
- Providing orchestration, scheduling, or dry-run behavior.
- Adding a service-specific execution fork. Catalog metadata selects the one shared engine; a catalog
  with neither execution marker remains copy-ready and display-only.

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

Self-maintenance is deliberately outside the catalog engine. A manifest-verified direct GitHub
installation may check for a newer BASH_GOD release on bare interactive startup, and
`god --uninstall` may remove BASH_GOD itself. Neither path reads or executes catalog command text.

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
          +-------------------+-------------------+-------------------+-------------------+
          |                   |                   |                   |                   |
          v                   v                   v                   v                   v
  bash_god/catalog.sh   bash_god/art.sh    bash_god/render.sh   specialized views
                                            /            \
                                           v              v
                               bash_god/search.sh  bash_god/tree.sh
                                           \              /
                                            v            v
          bash_god/catalog/<service>/service.god

bare interactive god / god --uninstall
                    |
                    v
          bash_god/maintenance.sh
                    |
                    v
       verified BASH_GOD release assets only
```

Catalog command text reaches a native CLI only through the generic reviewed-execution path: an
interactive search picker shows the complete resolved command, the operator explicitly chooses it,
and the engine launches it with user values carried as positional arguments. Every other renderer
remains inert and copy-ready.

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
  maintenance.sh
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
- `maintenance.sh` owns cached direct-GitHub update checks and complete BASH_GOD removal. It runs in
  a dedicated Bash process and never receives catalog command text.
- `catalog.sh` owns catalog discovery, service-route resolution, and grammar validation.
- `discover.sh` owns generic discoverable-tool resolution, version capture, endpoint-candidate
  resolution, and their cache.
- `art.sh` owns the pre-rendered six-line identity and its TTY gate; sourcing it is silent and only
  bare `god` may render it.
- `render.sh` owns normal root, service, group, and command views.
- `search.sh` owns query parsing, matching, ranking, list/tree/detail search views, and search help.
- `menu.sh` owns the in-place rich picker and normal command editor handoff.
- `resolve.sh` owns safe placeholder/config resolution and discovered-probe rewrites.
- `execute.sh` owns terminal handoff and reviewed command launch.
- `tree.sh` owns root, service, and group hierarchy rendering.
- `catalog/general/service.god` holds host, operating-system, process, file, and resource knowledge.
- `catalog/network/service.god` holds vendor-neutral interfaces, ports, DNS resolvers, connectivity,
  HTTP, and SSH knowledge.
- `catalog/aws/service.god` holds AWS identity and read-only Route 53 inventory knowledge.
- Elasticsearch, Kubernetes, Kafka, and MongoDB each own the matching service catalog directory.
- `tests/smoke.sh` is the stable entrypoint for static and fake-only execution regression suites.
- `packaging/tests/` verifies release construction, one-line installation, update decisions,
  cancellation, and full owned-path purge under isolated prefixes.
- Existing aliases and functions remain in `BASH_GOD.sh`; the knowledge layer does not reinterpret them.

Current service routes are `aws`, `elasticsearch`, `general`, `k8s`, `kafka`, `mongo`, and `network`.
Compatibility modes remain searchable metadata; only older ZooKeeper-era Kafka syntax receives a
visible `[LEGACY]` badge.

## Catalog Format

A platform file contains metadata followed by ordered groups and command records:

```text
@title Kafka commands
@description
Curated Kafka commands. Shown for review and, once you confirm, run against the resolved install.

@discover
probe | kafka-topics.sh | Core topic-management tool; presence marks a resolved install
root | /opt/kafka/bin | Common install layout
scan | /opt | Bounded scan root when the common layout is absent
version | kafka-topics.sh --version | Prints the installed version

@connection ENDPOINT 9092

@synced 3.9

@group offset
@command Show consumer-group offsets and lag
@mode MODERN
@since 0.10.1
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
- An optional top-level `@discover` block (probe/root/scan/version rows) marks one discovered tool
  family executable. `@execution PATH` marks a multi-tool PATH catalog executable. They are mutually
  exclusive, must appear before all groups, and a catalog with neither stays display-only.
- Every executable catalog declares `@connection NONE`, `@connection ENDPOINT <port>`, or
  `@connection CONTEXT`. `NONE` has no shared target, `ENDPOINT` permits one cached non-secret
  `host:port` candidate, and `CONTEXT` represents client-managed state such as kubeconfig or AWS
  profile/region.
- An optional top-level `@synced VERSION` records which version the catalog was last verified
  against. `god --paths` renders it once per service; it never filters or annotates a command row.
- Every `@group NAME` creates an exact navigable group route.
- Every `@command TITLE` requires `@mode`, non-empty `@description`, and exactly one physical `@run` line.
  In a catalog with `@discover`, every command also requires `@since VERSION`; service-neutral local
  rows use `@since 0.0`.
- `@mode` is `LOCAL`, `MODERN`, `LEGACY-ZK`, or `KRAFT`. It remains searchable metadata, but the
  terminal renderer keeps normal modes visually silent and displays only `LEGACY-ZK` as `[LEGACY]`.
  `LOCAL` also exempts a record from path resolution and version filtering.
- Per-command `@since VERSION` and optional `@until VERSION` state the version range a record is
  known to support. In discovery catalogs `@since` is mandatory. Search keeps an out-of-range row
  visible with its reason but disables execution and editing. Optional `@intent SLUG` links
  same-purpose records across versions so the preferred in-range form is identified.
- `@params` and `@optional` rows use `NAME | EXAMPLE | MEANING`.
- `@risk WRITE`, `@risk WARN`, and `@risk DELETE` distinguish normal writes, high-impact non-delete
  operations, and removals.
- `@notes` is optional and records a material compatibility, safety, or interpretation detail.
- `@end` closes each command record.
- Group names and command titles are unique within their scopes, ignoring case.

The catalog file itself is never sourced, evaluated as code, or treated as anything but text: parsing
it can never run a line it contains. In BASH_GOD 0.0.2.4.1, the *value* of one reviewed `@run` line is
handed to a child shell as an argument-safe template for catalogs declaring
`@discover` or `@execution PATH`; all other views stop at the screen. Only regular, non-symlink files
at `catalog/<valid-service-name>/service.god` are accepted. The parent directory becomes the exact
case-insensitive service route.

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

Once a version is detected for a service, each result is checked against its own `@since`/`@until`
range after scoring. Out-of-range matches stay in their relevance position, show the exact required
or last-supported version, and cannot be run or edited. `@intent` twins identify the preferred
in-range form without a service-level compatibility summary. A service with no detected version, or
no `@discover` block, applies no version policy. `--all-versions` exposes every variant but does not
make an incompatible row executable; `@synced` remains service-level review metadata in `god --paths`.

### Execution (generic, 0.0.2.4.1)

A view key (`--tree`, `--details`, `--keys`, `--help`, `--full`) never offers execution, on any
service, at any scope — those routes only ever render text. Only the plain `q`/`-q` route, with no
view key, on a TTY, offers to run a result:

1. **Determine capability.** `@discover` resolves the declared probe against its declared root,
   then PATH, then a bounded scan, caching the directory and version. During explicit
   `god SERVICE --resync` only, an `ENDPOINT` catalog also prefers a non-secret
   `target=host:port` override and otherwise may cache a concrete local listener at its declared
   port. A search makes only a cheap client-path freshness check; it never probes for a target.
   `god --paths` lists the resolved client, detected version, catalog review version, and—only for
   resolved endpoint catalogs—`Target: host:port` or `Target: unresolved`. `@execution PATH`
   intentionally has no discovery or product version: its commands retain their catalog spelling and
   use the caller's PATH. An unresolved discovery catalog, a catalog with neither marker, or an
   unusable terminal retains the static `MATCHING OPERATIONS` table.
2. A capable result opens one **in-place interactive picker**: the caller's terminal keeps the
   BASH_GOD-framed search title and subtitle, the list contains compact titles, and the highlighted
   title owns a word-wrapped `$ <resolved command>` panel. It never enters an alternate terminal
   screen. Arrow keys repaint only the changed rows and panel; `e` opens a normal line editor seeded
   with the complete command, Enter runs the reviewed command, and Escape cancels promptly. Its key
   reader may use a bare `perl` executable, but never an optional Perl module.
3. **Resolve and execute** (`bash_god/resolve.sh`, `bash_god/execute.sh`) safely prepare each selected
   command. A discovered catalog may rewrite a declared leading client spelling to its cached,
   catalog-declared probe-family member at the resolved absolute path. An endpoint target may replace
   only the exact catalog default `localhost:<port>` in that reviewed model; static catalog text remains
   copyable. `@params` become positional argument slots, including
   values embedded inside quoted URLs or JSON, so query/config/prompt values never become shell syntax.
   Any remaining placeholder is prompted only after selection in the same terminal flow. Native stdout
   and stderr stream directly to the terminal, and child exit status and Ctrl-C are preserved. An
   executable catalog contains only child-process-safe commands; a shell-state operation
   (`cd`, `export`, `unset`, `source`) is rejected as a defense in depth.

No terminal, no execution: all non-search views remain inert, copy-ready renderers.

### Routing and exit codes

Service and group names require exact matches but ignore case, so `god KAFKA OFFSET` resolves normally. Partial names are search terms, not routes. Unknown routes return contextual help and never guess.

`god --keys`, `god kafka --keys`, and `god kafka offset --keys` show the same navigation vocabulary
with examples for the current scope. The routing invariant is that `--help`, `--tree`, `--details`,
`--keys`, and `q`/`-q` resolve at root, service, group, and search scopes wherever meaningful.
`--quiet` is an exact global option accepted anywhere and suppresses decorative home artwork without
changing the selected view; `-q` remains the query route. `--full` always modifies `--tree`;
`<number>` always requires numbered group rows. `god --version`
and root-level `god -v` print only
`BASH_GOD 0.0.2.4.1` and `License: MIT`; they do not report the host shell version.

- `0`: successful display or search with matches.
- `1`: valid search with no matches.
- `2`: invalid syntax, route, regex, style setting, or catalog data.

## Visual Design

- The six-line BASH GOD logo is pre-rendered in `art.sh`; BASH_GOD never shells out to `figlet`,
  `toilet`, or another banner generator.
- A compact identity strip beneath the logo shows `BASH_GOD`, the current version, the MIT license,
  the searchable command-memory purpose, and the native-CLI source-of-truth philosophy.
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

Adding `@discover` or `@execution PATH` to a new service's catalog opts it into the same execution
engine — nothing service-specific to write. See `bash_god/AGENTS.md`'s Execution Metadata section for
the directive grammar and `bash_god/docs/service-sync.md` for keeping a discovery catalog's version
metadata current as its native tool changes.

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
- Copy-ready display verified without invoking Kafka or another native tool; the execution path
  (discovery, resolution, injection-safety, resolved-picker review, no-TTY-refuses) is verified
  separately against synthetic fixtures, never against a live service.
- Pre-rendered artwork only for bare TTY `god`, exact slogan rendering, global `--quiet`, and
  logo-free help, scoped, redirected, piped, and error views.
- Manifest-gated update/removal, silent offline checks, explicit update choice, default-cancel
  uninstall, and removal of every BASH_GOD-owned runtime, backup, config, cache, state, and data path.

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
- A catalog with neither `@discover` nor `@execution PATH` remains display-only. Across executable
  catalogs, resolve.sh binds a value only when the query names that slot's keyword unambiguously;
  anything less certain stays a placeholder to fill in by hand.
- Warnings cannot prevent an operator from running a risky command; the risk label remains visible
  on the picker row, and Enter runs the command the operator just reviewed.
- Automatic update and `god --uninstall` apply only to direct GitHub installations carrying the
  matching ownership manifest. Package managers and source checkouts retain ownership of their files.
