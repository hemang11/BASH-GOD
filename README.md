# BASH_GOD

```text
██████╗  █████╗ ███████╗██╗  ██╗    ██████╗  ██████╗ ██████╗
██╔══██╗██╔══██╗██╔════╝██║  ██║   ██╔════╝ ██╔═══██╗██╔══██╗
██████╔╝███████║███████╗███████║   ██║  ███╗██║   ██║██║  ██║
██╔══██╗██╔══██║╚════██║██╔══██║   ██║   ██║██║   ██║██║  ██║
██████╔╝██║  ██║███████║██║  ██║   ╚██████╔╝╚██████╔╝██████╔╝
╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝
```

**Your DevOps command memory. Searchable, copy-ready native commands — with reviewed execution when a service supports it.**

[![GitHub release](https://img.shields.io/github/v/release/hemang11/BASH-GOD?style=flat-square&label=release&color=f6c344)](https://github.com/hemang11/BASH-GOD/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-f6c344?style=flat-square)](LICENSE)
[![Bash 3.2+](https://img.shields.io/badge/bash-3.2%2B-f6c344?style=flat-square)](https://www.gnu.org/software/bash/)

Stop searching Slack, old notes, and shell history for the command you used six months ago.

BASH_GOD keeps curated DevOps commands in a searchable local catalog. It shows you what to run, what it does, and what each parameter means. It never runs anything you have not seen and approved.

> BASH_GOD shows you the resolved command and runs it only after you confirm. Discoverable services
> resolve their installed tool family and version; endpoint-based services can also resolve a local
> or explicitly configured target during `god --resync`. PATH services use the same reviewed picker
> through your normal shell lookup. Every catalog command remains copy-ready, and native CLIs remain
> the source of truth.

## See it in action

```text
$ god kafka -q "consumer lag"

╭────────────────────────────────────────────────────────────────────────╮
│ KAFKA SEARCH RESULTS                                                   │
│ Smart search: consumer lag                                             │
╰────────────────────────────────────────────────────────────────────────╯

  ❯ Show consumer-group offsets and lag
    Show latest offsets for a topic [needs v3.0+ (have v1.1.0)]

  Show consumer-group offsets and lag
  $ /path/to/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group connections --describe
  ↑/↓ move · e edit · enter run · esc cancel
```

On a TTY, compatible runnable results open this in-place picker. Arrow keys change the selection,
`e` opens your normal terminal line editor with the complete command already there, Enter runs the
reviewed command, and Escape leaves immediately. Native stdout, stderr, exit status, and Ctrl-C pass
through unchanged. A tool that cannot be resolved falls back to the ordinary copy-ready search
results; no execution is offered.

## Install

First installation only:

```bash
bash <(curl -fsSL https://github.com/hemang11/BASH-GOD/releases/latest/download/install.sh)
```

Then use it normally:

```bash
god
```

The installer puts the launcher at `~/.local/bin/god` and the runtime at `~/.local/lib/bash-god`. It does not use `sudo` or edit `.bashrc`, `.bash_profile`, `.zshrc`, or another startup file. If `~/.local/bin` is not already in `PATH`, the installer prints the exact export to add.

A bare interactive `god` checks GitHub periodically. When a newer release exists, choose **Update** or **Not now** with the arrow keys and Enter. Offline checks fail silently, and scoped commands such as `god kafka` never perform the check.

Complete removal:

```bash
god --uninstall
```

Removal defaults to **Cancel** and shows every owned path before deleting anything. Choosing **Uninstall everything** purges the managed runtime, launcher, backups, metadata, configuration, cache, state, and BASH_GOD data. Package-manager installations and source checkouts are refused so their owning installation method stays in control.

For development, clone the repository and use `./god`, or source `BASH_GOD.sh`. Sourcing is silent and affects only the current shell:

```bash
git clone https://github.com/hemang11/BASH-GOD.git
cd BASH-GOD
source ./BASH_GOD.sh
god
```

## Remember only `god`

```bash
god                              # Discover services
god kafka                        # Browse Kafka knowledge
god kafka offset                 # See copy-ready offset commands
god kafka offset 1               # Explain one displayed command
god kafka q "Get all consumers in a broker"  # Search by remembered intent — on a TTY, pick, edit, or run a row
god kafka --tree --full          # Show the full Kafka command tree
god --paths                      # See what BASH_GOD has resolved on this machine
god --resync                     # Refresh every detectable service
god kafka --resync               # Force a fresh probe if Kafka moved
```

| What you remember | What to type |
|---|---|
| The service | `god mongo` |
| The service and subject | `god k8s describe` |
| Remembered service intent | `god kafka q "Get all consumers in a broker"` |
| A regular expression | `god q --regex 'offset\|lag'` |
| Everything below a route | `god kafka native --tree --full` |

Search is case-insensitive and checks command titles, descriptions, native syntax, parameters, options, and notes.

## What is included

| Area | Start here |
|---|---|
| AWS identity and Route 53 (executable when the AWS CLI resolves) | `god aws` |
| Elasticsearch (executable when curl resolves; version-aware after resync) | `god elasticsearch` |
| Host, CPU, memory, disk, and processes (executable through PATH) | `god general` |
| Kubernetes (executable when kubectl resolves) | `god k8s` |
| Kafka (executable when its installation resolves) | `god kafka` |
| MongoDB (executable when its MongoDB shell resolves) | `god mongo` |
| Networking, DNS, HTTP, and SSH (executable through PATH) | `god network` |

The catalog is deliberately curated around common operational work rather than every flag in every manual. Each service has a `native` group when you need the installed tool's full help.

## How it works

```text
god / BASH_GOD.sh
├── routing · search · rendering · tree views
├── discovery · compatibility · safe placeholder resolution
│        └── bash_god/catalog/<service>/service.god
├── in-place picker · normal command editor · reviewed execution
└── managed install/update/removal · bash_god/maintenance.sh
```

Every service owns one plain-text catalog. The same records power browsing, search, help, details, numbered explanations, and tree views, so there is no second command registry to maintain.

Catalog files are parsed as data; the file itself is never sourced or evaluated as code. A service
that declares `@discover` runs only after its tool family resolves. Its detected native version is
checked against each command's declared support range, so incompatible rows show why beside their
title and remain copy-ready but cannot be edited or run. Each executable catalog also declares a
connection model: local/none, endpoint, or client-managed context. During `god SERVICE --resync`,
an endpoint catalog can cache an explicit non-secret `host:port` target or a concrete local listener;
the reviewed command uses that Target for its declared endpoint, host, and port defaults. `god --paths`
shows the resolved client, catalog review version, and target. A service that declares
`@execution PATH` uses the same reviewed picker through normal PATH lookup. In every case, the value
of a confirmed `@run` line is passed as an argument-safe template—never before you have seen and
approved it. Catalogs without either marker stay display-only.

## Add your own command

Open `bash_god/catalog/<service>/service.god`, find the appropriate `@group`, and add one record:

```text
@command Check the MongoDB service status
@mode LOCAL
@description
Shows whether the local MongoDB systemd unit is running and displays recent status information.
@run
systemctl status mongod
@end
```

That one record automatically appears in group views, help, details, trees, numbered explanations, and search. A normal catalog change requires no dispatcher code.

Preview it without executing the native command:

```bash
./god mongo service
./god mongo service q "service status"
./bash_god/tests/smoke.sh
```

See the [contributor workflow](CONTRIBUTING.md) for a practical new-service and command-update path.
[`bash_god/AGENTS.md`](bash_god/AGENTS.md) remains the complete catalog contract.

## Safety

- BASH_GOD displays catalog commands. Services that declare `@discover` or `@execution PATH` can
  also run one—but only after the complete command is visible in the in-place interactive picker;
  press `e` to edit it in a normal readline prompt or Enter to run the selected row. Incompatible,
  unresolved, and display-only rows cannot execute.
- Values BASH_GOD fills in from your query or a prompt are never turned into shell syntax: they are
  passed as arguments to the command, not interpolated into its text.
- `WRITE`, `WARN`, and `DELETE` describe the native command's impact and stay visible on the selected
  picker row; they do not block execution once the operator presses Enter.
- Every record in an executable catalog is an actual command. Do not add a child-shell-only operation
  such as `cd`, `export`, `unset`, or `source`; express the useful one-command check instead.
- No terminal, no execution — the interactive picker and any value prompts require one, always.
- Replace every `<placeholder>` BASH_GOD did not fill in before running or copying a command.
- Never put credentials, tokens, private keys, authenticated URIs, or production payloads in a catalog.
- Once copied or run, a command is governed by the native tool, your identity, and your current environment.

## Verification

The test suite renders catalog knowledge but never runs the displayed native commands:

```bash
bash -n BASH_GOD.sh god bash_god/*.sh bash_god/tests/*.sh packaging/*.sh packaging/tests/*.sh
zsh -n BASH_GOD.sh god bash_god/*.sh bash_god/tests/*.sh packaging/*.sh packaging/tests/*.sh
./bash_god/tests/smoke.sh
./packaging/tests/runtime-package-smoke.sh
./packaging/tests/install-smoke.sh
./packaging/tests/maintenance-smoke.sh
```

## Limitations

- The catalog is intentionally useful rather than exhaustive.
- Search is ranked word matching, not an embedding or conversational model.
- Native flags and behavior can vary by installed version and environment.
- Automatic update and `god --uninstall` apply only to direct GitHub Release installations. Package-manager installs remain owned by their package manager.

## Documentation

- [Contribute catalog knowledge](CONTRIBUTING.md)
- [Full catalog contract](bash_god/AGENTS.md)
- [Knowledge-base architecture](bash_god/docs/architecture/bash-god-knowledge-base-architecture.md)
- [Build, verify, and publish runtime packages](packaging/README.md)

## License

BASH_GOD is available under the [MIT License](LICENSE). Use it, modify it, and share it—including commercially—while retaining the copyright and license notice. It is provided without warranty.
