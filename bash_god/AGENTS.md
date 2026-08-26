# BASH_GOD Contribution Guide

These instructions apply only to the BASH_GOD toolkit in this directory. They are written for both
humans and coding agents. Follow them when adding or changing BASH_GOD knowledge.

## Context / Problem

BASH_GOD is a searchable memory layer for native DevOps commands. Its job is to answer questions
such as “how do I inspect consumer lag?” by showing a curated native command with enough context to
understand and adapt it.

BASH_GOD is not a replacement CLI. Catalog entries are inert text: BASH_GOD displays them and never
executes them.

## Scope

This guide covers:

- adding a command to an existing group;
- adding a group to an existing service;
- adding a new top-level service catalog;
- documenting parameters, optional flags, compatibility, and safety;
- previewing and verifying catalog changes.

It does not authorize running a displayed command against Kafka, MongoDB, Kubernetes, AWS, a remote
host, or any other operational system.

## Non-negotiable Rules

1. Keep exactly one `catalog/<service>/service.god` catalog per top-level service or subject.
2. Do not create one file per group or one file per command.
3. Treat every `.god` file as data, never as shell code. Do not source it or evaluate it.
4. Keep every `@run` value on one physical line. Do not add formatting-only continuation backslashes.
5. Never store credentials, tokens, private keys, passwords, authenticated URIs, or decrypted values.
6. Use placeholders such as `<topic_name>` and `<consumer_group>` for values users must replace.
7. Mark state-changing operations accurately with `@risk WRITE`, `@risk WARN`, or `@risk DELETE`.
8. Preserve BASH_GOD's knowledge-only model. Do not add code that executes catalog commands.
9. Do not modify `.bashrc`, `.zshrc`, or another startup file while adding catalog knowledge.
10. Preserve unrelated aliases, functions, files, and user changes.

## Architecture / Flow

Catalogs live under service-specific directories:

```text
bash_god/catalog/
  general/
    service.god
  kafka/
    service.god
  <future-service>/
    service.god
```

The service route comes from the directory name, while `service.god` remains the single authoritative
catalog inside it. The folder gives each service room for future supporting files without bloating
the global catalog directory. The generic engine discovers every valid service catalog automatically.
A normal catalog-only addition should not require a dispatcher, renderer, or completion change.

The navigation model is positional and consistent across services:

```text
god <service>                         service group map
god <service> <group>                 numbered, copy-ready command list
god <service> <group> <number>        explanation for one displayed row
god --details                         explanations for every catalog command
god <service> --details               explanations for every command in one service
god <service> <group> --details       explanations for every row in the group
god <service> <group> --tree          compact branch with numbered row titles
god <service> <group> --tree --full   titles plus every native command line
god --keys                            root navigation vocabulary
god <service> --keys                  service-context navigation vocabulary
god <service> <group> --keys          group-context navigation vocabulary
god --quiet                           root dashboard without decorative artwork
god <service> --quiet                 global option accepted at any route position
god q <terms>                         forgiving, relevance-ranked lookup
god -q <terms>                        same smart lookup
god <service> q <terms>               search only one service
god <service> <group> q <terms>       search only one group
god q --any <terms>                   every record matching any useful word
god q --all <terms>                   require every useful word
god q --exact '<phrase>'              require one literal phrase
god q --regex '<pattern>'             explicit POSIX extended regex lookup
god q <terms> --tree                  matching commands grouped as a hierarchy
god q <terms> --tree --full           matching hierarchy plus native commands
god q <terms> --details               full explanation of every match
god --version                         BASH_GOD version and license
god --uninstall                       purge a managed direct-GitHub installation
```

The view keys work from root, service, group, and scoped-search routes. `--full` modifies `--tree`,
so it always follows that key. `<number>` is the only contextual selector: it requires a group whose
numbered rows are visible. It is generated from record order, is not a permanent command identifier,
and never belongs in a `.god` record. Search results resolve to the current row number.

`god --uninstall` and the cached update prompt are self-maintenance operations, not catalog routes.
They execute only `bash_god/maintenance.sh`, never an `@run` value. Automatic update checks are
limited to bare interactive `god` from a manifest-verified direct GitHub installation; package
manager installs and source checkouts remain owned by their original installation method.

`--quiet` is an exact global option: the dispatcher removes it wherever it appears and suppresses
decorative home artwork without changing the requested data view. Do not reuse `-q` for quiet mode;
`q` and `-q` remain the semantic-search routes.

Smart search is case-insensitive. It removes conversational filler, normalizes common plurals,
tolerates prefix-related variants, retains records with the best query-word coverage, and then ranks
title, route, and body matches. Search candidates are always command records even when the matching
text came from a description, parameter, optional flag, or note.

## Terminal Identity Contract

- Store the six-line BASH GOD logo as pre-rendered text in `art.sh`; do not invoke `figlet`, `toilet`,
  or another generator at runtime.
- Follow the logo with the compact identity strip: product version, license, command-memory purpose,
  and the reminder that native CLIs remain the source of truth.
- Render the logo only for a bare `god` invocation when stdout is a TTY.
- Keep `god help`, scoped commands, redirects, pipes, and error output free of the logo.
- Honor the exact global `--quiet` option at every route position.
- Start each top-level interactive invocation with exactly one blank line so output is visually
  separated from the prompt. Do not add that padding to redirected or piped stdout, and do not let
  recursive routes such as `god tree kafka` print it twice.
- Treat `NO_COLOR` as authoritative: when it is present, emit no ANSI sequences even if
  `GOD_COLOR=always`. On a TTY, this leaves the uncolored logo unless `--quiet` is also present.
- Keep sourcing silent. Loading `BASH_GOD.sh` or `art.sh` must never print the logo or other output.

## Choose the Correct Catalog and Group

Before adding anything, decide where the knowledge belongs:

- Put platform-specific knowledge in that platform's catalog: AWS in `catalog/aws/service.god`, Kafka
  in `catalog/kafka/service.god`, MongoDB in `catalog/mongo/service.god`, Kubernetes in
  `catalog/k8s/service.god`, and Elasticsearch in `catalog/elasticsearch/service.god`.
- Put service-independent host, process, filesystem, and hardware-resource knowledge in
  `catalog/general/service.god`.
- Put generic interfaces, ports, DNS resolvers, connectivity, HTTP, and SSH knowledge in
  `catalog/network/service.god`; do not dilute `general` with networking commands.
- Put AWS identity, Route 53, and future AWS-service knowledge in `catalog/aws/service.god`. Route 53
  is an AWS service even though its records participate in DNS; do not place it under `network`.
- Reuse an existing group when the new command answers the same kind of question.
- Add a new group only when it creates a useful distinction on `god <service>`.
- Keep group names short, lowercase, and memorable, for example `offset`, `topics`, `health`, or
  `native`.

Do not duplicate a general command inside multiple service catalogs merely because it is often used
while operating those services.

## Fast Path: Add a Command to an Existing Group

1. Open `bash_god/catalog/<service>/service.god`.
2. Find the single matching `@group <name>` block.
3. Add one complete command record alongside related commands.
4. Preview the group and the new detail view.
5. Run the smoke tests. Never run the displayed native command as part of verification.

Use this template:

```text
@command Human-readable operation title
@mode MODERN
@description
One concise explanation of what the native command reveals or changes.
@run
native-command --required-option <required_value>
@params
--required-option | <required_value> | Why this option or value is needed
@optional
--optional-flag | <optional_value> | When someone should add this option
@notes
One short operational caveat that materially helps the user.
@end
```

Remove `@optional` or `@notes` when there is nothing useful to say. Do not add empty sections.

### Minimal read-only example

```text
@command Describe one consumer group
@mode MODERN
@description
Shows committed offsets, log-end offsets, and lag for one consumer group.
@run
./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group <consumer_group> --describe
@params
--bootstrap-server | localhost:9092 | Broker used to discover the cluster
--group | <consumer_group> | Consumer group to inspect
--describe | flag | Display partition offsets and lag
@end
```

Read-only records omit `@risk`.

### State-changing example shape

```text
@command Human-readable mutation title
@mode MODERN
@risk WRITE
@description
States exactly what will change.
@run
native-command --change <target>
@params
--change | <target> | Resource that will be modified
@notes
Review the target and native help before running this command.
@end
```

Use `WRITE` for an ordinary intentional state change, `DELETE` when the command removes data,
metadata, or access, and `WARN` for a high-impact non-delete operation such as resetting offsets or
moving replicas. Never hide a mutation inside an unmarked record.

## Add a New Group

Add one new group block inside the existing service file:

```text
@group new-group

@command First operation in the group
@mode MODERN
@description
Explains the operation.
@run
native-command --inspect <resource>
@params
--inspect | <resource> | Resource to inspect
@end
```

Rules:

- A group name may contain only letters, numbers, `_`, and `-`.
- Group names must be unique within the catalog, ignoring case.
- Place the group near related groups so the service map remains navigable.
- Prefer a focused group with several related operations over vague groups such as `misc`.
- Do not create a directory or another `.god` file for the group.

## Add a New Service

Create one service directory with exactly one primary catalog:

```text
bash_god/catalog/mongo/service.god
```

The `service.god` content begins like this:

```text
@title MongoDB commands

@description
Curated MongoDB inspection knowledge. Commands are shown as inert text and are never executed by BASH_GOD.

@group service

@command Check the MongoDB service status
@mode LOCAL
@description
Shows whether the local MongoDB systemd unit is running and displays recent status information.
@run
systemctl status mongod
@end
```

The parent directory becomes the exact, case-insensitive route:

```text
god mongo
god mongo service
```

Do not register the new service manually in `core.sh`. The parent directory name becomes the route,
so `catalog/mongo/service.god` becomes `god mongo`. Automatic discovery should make it appear in
`god`, `god --tree`, and search. If it does not appear, validate the catalog instead of adding a
special-case dispatcher branch.

## Catalog Field Reference

| Field | Required | Meaning |
|---|---:|---|
| `@title` | Once per file | Human-readable service title. Must precede every group. |
| top-level `@description` | Once per file | Concise scope of the entire catalog. Must precede every group. |
| `@group <name>` | Yes | Exact navigable group route. |
| `@command <title>` | Per record | Unique, human-readable operation title within the group. |
| `@mode <mode>` | Per record | Compatibility/context metadata; see accepted values below. |
| `@risk WRITE` | Optional | Command intentionally changes state. |
| `@risk WARN` | Optional | High-impact non-delete command that deserves extra review. |
| `@risk DELETE` | Optional | Command removes data, metadata, or access. |
| `@description` | Per record | What the command does, in plain language. |
| `@run` | Per record | Exactly one physical line containing the copy-ready native command. |
| `@params` | Optional | Required or already-present arguments as `NAME | EXAMPLE | MEANING`. |
| `@optional` | Optional | Useful additions as `NAME | EXAMPLE | MEANING`. |
| `@notes` | Optional | A concise compatibility, safety, or interpretation note. |
| `@end` | Per record | Closes the command record. |

Accepted modes are:

- `MODERN`: normal current/native CLI usage;
- `LOCAL`: host, shell, filesystem, or service-manager command;
- `LEGACY-ZK`: older ZooKeeper-era Kafka syntax;
- `KRAFT`: Kafka KRaft-specific operation.

Modes remain searchable metadata. The terminal keeps normal modes quiet and visibly renders only
`LEGACY-ZK` as `[LEGACY]`. Do not invent another mode without updating validation, rendering, tests,
and this guide together.

## Writing Good Records

### Title

Use an action-oriented title that answers “what will I learn or change?”

Good:

```text
Show consumer-group offsets and lag
Find partitions without an available leader
Check the MongoDB service status
```

Avoid titles that merely repeat a binary name, such as `Run kafka-topics`.

### Description

Explain the operational result, not every native option. Keep it concise enough for `--help` and
search results. Search examines descriptions, so include the words a person is likely to remember.

### Command

- Keep it copy-ready and on one physical line.
- Prefer a safe, bounded inspection form.
- Use meaningful placeholders rather than shell variables requiring hidden setup.
- Use the executable name a user will actually see, such as `./kafka-topics.sh`.
- If several installed names are possible, add a setup/discovery record or explain it in `@notes`.
- Do not put a credential or a credential-bearing URI in an example.

### Parameters

Explain non-obvious arguments individually. A parameter row always has exactly three pipe-separated
columns:

```text
NAME | EXAMPLE | MEANING
```

Put flags already present in `@run` under `@params`. Put useful flags not present in the shown
command under `@optional`.

### Notes

Use notes only for information that changes safe or correct use, such as version differences, file
sensitivity, prerequisites, or interpretation of output. Do not restate the description.

## Native Help Knowledge

Native help remains catalog knowledge, not executable BASH_GOD behavior. Put native-help records in
the service's `native` group:

```text
@command Show kafka-topics native help
@mode MODERN
@description
Displays every option supported by the installed kafka-topics version.
@run
./kafka-topics.sh --help
@end
```

Do not create `god` code that detects or invokes the tool. The user chooses whether to copy and run
the displayed help command.

## Safety and Secrets

- Catalog verification may render records but must never execute `@run` lines.
- Prefer read-only inspection commands.
- For mutations, use `@risk WRITE`, `@risk WARN`, or `@risk DELETE` and state the effect plainly.
- Do not add real Vault tokens, AWS credentials, SSH private keys, passwords, MongoDB credentialed
  URIs, Kafka secrets, or copied production payloads.
- Do not create a `credentials.md` catalog.
- If a referenced properties file may contain secrets, mention that output should be reviewed before
  sharing; do not copy the secret values into the catalog.
- Environment-specific but non-secret examples may be used when they are genuinely useful. Prefer a
  placeholder when the value varies between environments.

## Preview and Verification

From the repository root, preview the affected paths:

```text
GOD_COLOR=never ./god <service>
GOD_COLOR=never ./god --quiet
GOD_COLOR=never ./god --details
GOD_COLOR=never ./god <service> --details
GOD_COLOR=never ./god <service> <group>
GOD_COLOR=never ./god <service> <group> --help
GOD_COLOR=never ./god <service> <group> --details
GOD_COLOR=never ./god <service> <group> --tree
GOD_COLOR=never ./god <service> <group> --tree --full
GOD_COLOR=never ./god <service> <group> --keys
GOD_COLOR=never ./god q <search_terms>
GOD_COLOR=never ./god <service> q <search_terms>
GOD_COLOR=never ./god <service> <group> q <search_terms>
GOD_COLOR=never ./god q --any <search_terms>
GOD_COLOR=never ./god q --all <search_terms>
GOD_COLOR=never ./god q --exact '<phrase>'
GOD_COLOR=never ./god q --regex '<pattern>'
GOD_COLOR=never ./god q <search_terms> --tree
GOD_COLOR=never ./god q <search_terms> --tree --full
GOD_COLOR=never ./god q <search_terms> --details
GOD_COLOR=never ./god --version
```

Then run the non-operational checks:

```bash
bash -n BASH_GOD.sh god bash_god/core.sh bash_god/catalog.sh bash_god/art.sh bash_god/maintenance.sh bash_god/render.sh bash_god/search.sh bash_god/tree.sh bash_god/tests/smoke.sh packaging/*.sh packaging/tests/*.sh
zsh -n BASH_GOD.sh god bash_god/core.sh bash_god/catalog.sh bash_god/art.sh bash_god/render.sh bash_god/search.sh bash_god/tree.sh bash_god/tests/smoke.sh
./bash_god/tests/smoke.sh
./packaging/tests/runtime-package-smoke.sh
./packaging/tests/install-smoke.sh
./packaging/tests/maintenance-smoke.sh
git diff --check
```

If `shellcheck` is already installed, run it against the shell files. Do not install it merely to
complete a catalog edit.

Confirm all of the following:

- sourcing `BASH_GOD.sh` remains silent;
- the pre-rendered logo appears only for bare `god` on a TTY;
- `god help`, scoped routes, redirects, pipes, errors, and `--quiet` remain logo-free;
- top-level TTY commands begin with one blank line while redirected output and recursive routes do not
  gain extra padding;
- `NO_COLOR` emits no ANSI sequences even with `GOD_COLOR=always`, while preserving plain TTY art;
- `-q` still routes to search and is never interpreted as quiet mode;
- the new record appears in the expected group;
- the compact view shows one physical command line;
- `<number>`, `--help`, `--details`, `--tree`, `--tree --full`, and `--keys` show the expected knowledge
  at every meaningful scope;
- `q` or `-q` can find the record globally and when scoped to its service or group;
- full tree rendering may display `@run` values but does not execute them;
- no catalog command was executed;
- no secret or terminal-control value appears in output.

## Changes Beyond Catalog Data

Changing the catalog grammar or navigation model is a framework change, not a normal knowledge
addition. When such a change is genuinely required, update these together:

1. initialization/dispatch in `bash_god/core.sh`, discovery/validation in `bash_god/catalog.sh`,
   bare-TTY artwork in `bash_god/art.sh`, normal views in `bash_god/render.sh`, search in
   `bash_god/search.sh`, or hierarchy rendering in `bash_god/tree.sh`, according to ownership;
2. smoke coverage in `bash_god/tests/smoke.sh`;
3. `bash_god/docs/architecture/bash-god-knowledge-base-architecture.md`;
4. this `AGENTS.md` field reference and workflow.

Do not special-case one service in the dispatcher when the behavior can remain data-driven.

## Verification Status and Limitations / Risks

The current validator rejects malformed catalogs before rendering them. The smoke suite verifies
that catalogs remain inert, sourcing is silent, navigation is case-insensitive, default trees are
compact, full trees display inert native command lines, the logo respects TTY and quiet/color
contracts, and Bash and zsh can load the toolkit.

Current limitations:

- row numbers are positional and can change when records are reordered;
- accepted `@mode` values are currently shared across all services;
- catalogs are plain text and do not support arbitrary Markdown or nested command execution;
- smart search is ranked word matching, not an embedding model, so distant synonyms may still need
  a broader `--any` query or an explicit regex;
- correctness of a native command still depends on the installed CLI version and environment;
- BASH_GOD deliberately does not validate a displayed command by running it.

## Definition of Done

A catalog change is complete when it is correctly placed, searchable, understandable without old
notes or chat history, accurately marked for safety and compatibility, rendered cleanly, free of
secrets, and all non-operational verification checks pass.
