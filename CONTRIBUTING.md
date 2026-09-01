# Contributing catalog knowledge to BASH_GOD

> **Agent start here:** read this guide, then read [`bash_god/AGENTS.md`](bash_god/AGENTS.md).
> Treat the catalog as data. Do not add a service-specific execution, renderer, or dispatcher branch
> to make one command work.

## Context / Problem

BASH_GOD is a human-friendly memory layer for native operational commands. A good contribution adds
the command a person would actually type, explains what it does, makes compatibility and risk clear,
and behaves consistently in search, trees, details, and the in-place picker.

The common failure mode is solving a catalog-data problem in the shared Bash engine, or adding a
command that is not genuinely runnable after the picker resolves it. This guide makes the intended
decision path explicit before an agent edits anything.

## Scope

This guide covers:

- adding or correcting commands in an existing service;
- adding a group or an entire service catalog;
- choosing discovery, PATH, or display-only execution metadata;
- adding or changing version compatibility, legacy tool fallback, and safety metadata;
- verifying a change without contacting a real service.

It does not authorize a release, a tag, a push, a native command against a live environment, or a
service-specific code branch. Those require an explicit request.

## Decision / Implementation Summary

One catalog owns one service:

```text
bash_god/catalog/<service>/service.god
```

The catalog is parsed as inert text. Shared modules validate, search, render, discover, resolve, and
execute it. Prefer changing only `service.god`; touch shared code only when the same missing behavior
applies to every service.

## Architecture / Flow

```text
catalog record
  → catalog validation
  → static views / search ranking
  → optional generic client and endpoint cache
  → in-place reviewed picker
  → positional placeholder binding
  → confirmed child-process execution
```

The renderer and picker are shared. A catalog supplies titles, descriptions, command text, metadata,
and discovery facts; it never supplies terminal behavior.

## Choose the right contribution path

| Need | Change | Do not do |
|---|---|---|
| Add a command | Edit the closest `@group` in the existing `service.god`. | Create another `.god` file or a dispatcher branch. |
| Add a service | Create `catalog/<service>/service.god`; discovery finds the route automatically. | Register the route by hand in `core.sh`. |
| Support a native CLI or interchangeable legacy CLI | Declare it in `@discover`; use ordered `probe` rows for true alternatives. | Add `if service == ...` logic. |
| Run a collection of host tools with no service version | Use `@execution PATH`. | Pretend the version of `curl`, `ssh`, or `hostname` is the service version. |
| Cache a service version reached through a client | Use a generic `@discover` probe and a `version` row that queries the service. | Add an Elasticsearch-, Mongo-, or Kafka-specific resolver. |
| Declare how executable commands reach their subject | Add `@connection NONE`, `@connection ENDPOINT <port>`, or `@connection CONTEXT` in the catalog. | Add a service-name branch for hostname, URI, kubeconfig, or AWS profile discovery. |
| Make a raw client expression runnable | Use the native client's CLI form, such as `mongosh --eval '…'`. | Add a non-executable `copy only` row. |
| Fix behavior in every service | Change the shared module and add cross-service regression coverage. | Patch one catalog's renderer or picker behavior. |

## Recipe: add or update a command

1. Find the closest service and group with `rg -n '^@group|^@command' bash_god/catalog/<service>/service.god`.
2. Reuse the group unless the operation creates a clear new navigational category.
3. Add one complete record. Keep `@run` to **one physical line**.
4. Use placeholders for environment-specific values; never put credentials, tokens, or authenticated
   URIs in a catalog.
5. Add an accurate `@risk` when the operation changes state or has a high-impact outcome.
6. Make search useful: write the title and description in the words an operator is likely to remember.
7. Run the preview and fake-only tests below. Do not run the catalog command itself as validation.

Use this shape:

```text
@command Show consumer-group offsets and lag
@mode MODERN
@since 0.10.1
@description
Shows committed offsets, log-end offsets, and lag for one consumer group.
@run
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group <consumer_group> --describe
@params
--group | <consumer_group> | Consumer group to inspect
@optional
--timeout | 10000 | Wait longer for a slow broker response
@notes
Review lag before resetting offsets or changing membership.
@end
```

### Required metadata

- `@command`, `@mode`, `@description`, `@run`, and `@end` are required for every record.
- Every record in a discovery catalog needs `@since`. Use `0.0` only for a `LOCAL` row that has no
  dependency on the detected service version.
- Every executable catalog needs one explicit `@connection` directive. `NONE` is valid for local
  and PATH commands; it means no shared service target is cached.
- Use `@until` for a known upper compatibility boundary; do not hide a command just because it is old.
- Use the same `@intent` only for two versions of exactly the same operation.
- `@risk WRITE`, `@risk WARN`, and `@risk DELETE` describe impact. Never omit a risk label to make a
  command look safer.
- Every record in an executable catalog must be a real child-process command. `cd`, `export`,
  `unset`, `source`, and raw in-client snippets do not meet that contract.

## Recipe: add a new service

1. Create exactly `bash_god/catalog/<service>/service.god`.
2. Add `@title`, a top-level `@description`, exactly one execution choice, and one connection
   declaration before the first group.
3. Add focused groups and records using the required metadata above.
4. Validate the catalog before changing shared code. If it appears in `god --tree` and search after
   validation, the route is already wired.
5. Add a fake-only catalog test and register it from `bash_god/tests/smoke.sh` when the service uses
   discovery or introduces a new generic execution shape.

### Execution choices

#### A. Discover one tool family and cache a service version

Use `@discover` when one command-line client (or a small, interchangeable family) owns the service
commands. This enables `god <service> --resync`, `god --resync`, `god --paths`, resolved absolute
preview commands, and per-command compatibility labels.

```text
@discover
probe | tool | Preferred client executable
probe | old-tool | Legacy fallback only when it accepts the same catalog command family
root | /usr/local/bin | Common installation directory
scan | /opt | Bounded fallback root
version | <probe> --version | Prints the selected client's version
```

`probe` order is policy: the first usable tool wins and is cached. Only list alternatives whose
catalog commands are truly interchangeable. The generic resolver will rewrite the leading catalog
tool to the selected absolute path; do not duplicate every record for the legacy spelling.

For a REST service, the selected probe can be a client while the `version` request reads the service:

```text
@discover
probe | curl | Client for this REST catalog
root | /usr/bin | System curl location
scan | /usr | Bounded fallback
version | <probe> -fsS --connect-timeout 1 --max-time 2 http://localhost:9200/ | Reads the service version

@connection ENDPOINT 9200
```

This is still declarative, generic discovery. Cache the service version from the response, not the
client version.

### Connection declaration

Every executable catalog declares one connection model:

```text
@connection NONE
@connection ENDPOINT 9092
@connection CONTEXT
```

- Use `NONE` for local/PATH tools such as general and network. A command may still prompt for a
  one-off host, but BASH_GOD has no service-wide endpoint to discover.
- Use `ENDPOINT <port>` for client/server catalogs. During explicit `god SERVICE --resync`, the
  generic engine uses a non-secret `target=host:port` override from
  `~/.config/bash-god/SERVICE.conf` when set; otherwise it may cache a concrete local listener at
  the declared port. `god --paths` shows only `Target: host:port` or `Target: unresolved`.
  Never put credentials or a URI in `target=`.
- Use `CONTEXT` for client-owned contexts such as Kubernetes kubeconfig or AWS profile/region. Do
  not manufacture a host or port for them.

The shared resolver replaces only the exact catalog default `localhost:<port>` in the reviewed
runtime model. Static views stay copy-ready and unchanged. A local listener is a candidate, not proof
that the advertised remote service endpoint is reachable.

#### B. Use the caller's PATH

Use `@execution PATH` only for a deliberately mixed host-tool catalog with no single product version
axis, such as general system or network commands. It has no discovery cache and does not participate
in `--resync` or `--paths`; declare `@connection NONE`.

#### C. Display only

Use neither marker when a catalog should only render knowledge. It retains static search/tree/detail
views and never offers the execution picker.

## Recipe: update compatibility for a new native release

1. Read the native release notes and identify the exact changed syntax.
2. Keep a record's existing `@since` when it still works.
3. Add a new record with the first verified `@since` for a new syntax.
4. Add `@until` only when the old syntax is known to stop working.
5. Join overlapping old/new records with `@intent`; leave disjoint operations independent.
6. Every discovery catalog must declare `@synced <version>`. Update it only when the whole catalog
   was actually reviewed against that version; the validator rejects an omitted review baseline.

Compatibility is per command. Never replace it with a service-wide "N commands hidden" decision or
hide the version information only in a header.

## Shared-code change gate

Before editing `core.sh`, `render.sh`, `search.sh`, `menu.sh`, `discover.sh`, `resolve.sh`, or
`execute.sh`, answer this:

> Would the same behavior be correct for Kafka, MongoDB, Kubernetes, AWS, Elasticsearch, general,
> and network catalogs when their metadata requests it?

If the answer is no, the change belongs in catalog data or needs product direction. If yes, keep the
engine generic and update all affected shared tests plus `bash_god/AGENTS.md` and architecture docs.

## Preview and verification

Use read-only rendering first:

```bash
GOD_COLOR=never ./god <service>
GOD_COLOR=never ./god <service> <group>
GOD_COLOR=never ./god <service> q "remembered words"
GOD_COLOR=never ./god <service> q "remembered words" --tree --full
GOD_COLOR=never ./god <service> --details
```

Then validate without reaching a real service:

```bash
bash -n BASH_GOD.sh god bash_god/*.sh bash_god/tests/*.sh
zsh -n BASH_GOD.sh god bash_god/*.sh bash_god/tests/*.sh
bash bash_god/tests/smoke.sh
git diff --check
```

For a new discovery catalog, its test must use a temporary fake client and isolated `HOME`,
`XDG_CONFIG_HOME`, and `XDG_STATE_HOME`. Prove all of these:

- the catalog validates;
- the fake discovery probe finds the configured path and caches the intended version;
- endpoint catalogs resolve a fake local listener or a `target=` override only during resync, and
  rewrite only the reviewed runtime model;
- the catalog spelling stays human-copyable;
- only the leading declared client is rewritten in the rich model;
- placeholder values remain positional arguments, including quoted URLs and JSON;
- a stale or unresolved path falls back to the static `MATCHING OPERATIONS` view;
- no real native command, network request, cluster, or service is contacted.

## Agent handoff brief

Give an implementation agent this brief with the target service and desired command behavior filled
in:

```text
Read CONTRIBUTING.md and bash_god/AGENTS.md before editing.

Task: <add/update service or command>
Catalog target: bash_god/catalog/<service>/service.god
Execution model: <DISCOVER | PATH | DISPLAY ONLY>
Compatibility facts: <verified since/until values, or explicitly unknown>
Risks: <READ ONLY | WRITE | WARN | DELETE>

Constraints:
- Keep catalog data service-specific; do not add a service-name branch to shared Bash code.
- Every executable row must be a real command; no copy-only or raw shell snippets.
- Keep @run to one physical line and use placeholders for environment values.
- Add/adjust only fake-only tests; never call a real native service command.
- Show the exact files changed and run the focused suite plus bash_god/tests/smoke.sh and git diff --check.
- Do not commit, tag, publish, or push.
```

## Verification

This guide is aligned with the current catalog grammar, generic discovery/cache model, version policy,
in-place picker, and smoke-suite entrypoint. The smoke suite validates catalog structure and uses
synthetic clients for discovery and execution-flow checks.

## Limitations / Risks

- A catalog cannot prove a command works in every operator environment; `@since` and `@until` must
  come from verified native behavior, not intuition.
- Discovery confirms a client and caches a version response. Endpoint discovery runs only during
  explicit resync, never rendering; a local listener remains a candidate until a reviewed command is
  run by the operator.
- Rich execution needs Bash, a capable TTY, and a bare Perl executable for terminal key reads; it
  must not require optional Perl modules. The static command view remains the correct fallback
  for unresolved services, non-TTY output, and unsupported terminals.
