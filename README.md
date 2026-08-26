# BASH_GOD

```text
██████╗  █████╗ ███████╗██╗  ██╗    ██████╗  ██████╗ ██████╗
██╔══██╗██╔══██╗██╔════╝██║  ██║   ██╔════╝ ██╔═══██╗██╔══██╗
██████╔╝███████║███████╗███████║   ██║  ███╗██║   ██║██║  ██║
██╔══██╗██╔══██║╚════██║██╔══██║   ██║   ██║██║   ██║██║  ██║
██████╔╝██║  ██║███████║██║  ██║   ╚██████╔╝╚██████╔╝██████╔╝
╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝
```

**Your DevOps command memory. Searchable, copy-ready native commands. Zero execution.**

[![GitHub release](https://img.shields.io/github/v/release/hemang11/BASH-GOD?style=flat-square&label=release&color=f6c344)](https://github.com/hemang11/BASH-GOD/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-f6c344?style=flat-square)](LICENSE)
[![Bash 3.2+](https://img.shields.io/badge/bash-3.2%2B-f6c344?style=flat-square)](https://www.gnu.org/software/bash/)

Stop searching Slack, old notes, and shell history for the command you used six months ago.

BASH_GOD keeps curated DevOps commands in a searchable local catalog. It shows you what to run, what it does, and what each parameter means. It never executes catalog commands for you.

> BASH_GOD is a curated memory layer and orchestrator for frequently used DevOps operations. Native CLIs remain the source of truth and are always accessible through native-help commands.

## See it in action

```console
$ god q "consumer lag"

OPEN                     OPERATION
------------------------ ----------------------------------------------
god kafka offset 1       Show consumer-group offsets and lag

$ god kafka offset 1

$ ./kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config ../config/consumer.properties --group connections --describe
```

BASH_GOD finds the native command. You decide whether to copy and run it.

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
god kafka q "Get all consumers in a broker"  # Search Kafka by remembered intent
god kafka --tree --full          # Show the full Kafka command tree
```

| What you remember | What to type |
|---|---|
| The service | `god mongo` |
| The service and subject | `god k8s describe` |
| Remembered Kafka intent | `god kafka q "Get all consumers in a broker"` |
| A regular expression | `god q --regex 'offset\|lag'` |
| Everything below a route | `god kafka native --tree --full` |

Search is case-insensitive and checks command titles, descriptions, native syntax, parameters, options, and notes.

## What is included

| Area | Start here |
|---|---|
| AWS identity and Route 53 | `god aws` |
| Elasticsearch | `god elasticsearch` |
| Host, CPU, memory, disk, and processes | `god general` |
| Kubernetes | `god k8s` |
| Kafka | `god kafka` |
| MongoDB | `god mongo` |
| Networking, DNS, HTTP, and SSH | `god network` |

The catalog is deliberately curated around common operational work rather than every flag in every manual. Each service has a `native` group when you need the installed tool's full help.

## How it works

```text
god / BASH_GOD.sh
├── routing · search · rendering · tree views
│        └── bash_god/catalog/<service>/service.god
└── managed install/update/removal · bash_god/maintenance.sh
```

Every service owns one plain-text catalog. The same records power browsing, search, help, details, numbered explanations, and tree views, so there is no second command registry to maintain.

Catalog files are parsed as data. They are never sourced, evaluated, or passed to a native CLI.

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

See the [catalog contribution guide](bash_god/AGENTS.md) for parameters, optional flags, risk markers, new groups, and new services.

## Safety

- BASH_GOD displays catalog commands; it does not execute them.
- The only executable workflow owned by `god` is its own managed update and removal; it never executes an `@run` catalog entry.
- Replace every `<placeholder>` before copying.
- `WRITE`, `WARN`, and `DELETE` describe the native command's impact.
- Never put credentials, tokens, private keys, authenticated URIs, or production payloads in a catalog.
- Once copied, a command is governed by the native tool, your identity, and your current environment.

## Verification

The test suite renders catalog knowledge but never runs the displayed native commands:

```bash
bash -n BASH_GOD.sh god bash_god/*.sh bash_god/tests/smoke.sh
zsh -n BASH_GOD.sh god bash_god/*.sh bash_god/tests/smoke.sh
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

- [Add or change catalog knowledge](bash_god/AGENTS.md)
- [Knowledge-base architecture](bash_god/docs/architecture/bash-god-knowledge-base-architecture.md)
- [Build, verify, and publish runtime packages](packaging/README.md)

## License

BASH_GOD is available under the [MIT License](LICENSE). Use it, modify it, and share it—including commercially—while retaining the copyright and license notice. It is provided without warranty.
