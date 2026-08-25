# BASH_GOD

**Version 0.0.1.1**

Your DevOps command memory: searchable, copy-ready native commands without another operational CLI to learn.

> BASH_GOD is a curated memory layer for frequently used DevOps operations. Native CLIs remain the source of truth.

## Context / Problem

Useful operational commands tend to disappear into shell history, old notes, and chat threads. BASH_GOD keeps the commands worth remembering in a small local catalog and makes them discoverable through routes such as `god mongo`, `god k8s describe`, or `god q "consumer lag"`.

BASH_GOD displays knowledge. It never executes a catalog command, connects to a host, or forwards native CLI arguments.

## Scope and Non-goals

BASH_GOD is intentionally:

- curated around common DevOps work, not every command in every manual;
- organized by service and memorable groups;
- searchable across titles, descriptions, commands, parameters, and notes;
- explicit about commands that write, warn, or delete;
- a bridge back to native help through each service's `native` group.

It is not a replacement for Kafka, MongoDB, Kubernetes, Elasticsearch, networking, or operating-system tools. It does not run commands, store credentials, auto-configure your shell, or guarantee that a native command matches every installed version.

## Install

Clone the repository and source its single entry point:

```bash
git clone https://github.com/hemang11/BASH-GOD.git
cd BASH-GOD
source ./BASH_GOD.sh
god
```

Sourcing is silent. BASH_GOD does not edit `.bashrc`, `.bash_profile`, or `.zshrc`. To load it in future shells, manually add this line to the startup file you choose, using the real clone location:

```bash
source "/absolute/path/to/BASH-GOD/BASH_GOD.sh"
```

On an interactive terminal, the bare `god` dashboard opens with a pre-rendered six-line BASH GOD
logo. It is stored in the toolkit—`figlet`, `toilet`, and other banner generators are not runtime
dependencies. The logo is omitted from `god help`, every scoped command, redirected or piped output,
and errors. Add the exact global `--quiet` option anywhere in a route to suppress it explicitly.

You can also use the executable without sourcing:

```bash
./god --version
./god kafka offset
```

## Quick Use

```bash
god                                  # Show available services
god --quiet                          # Show the dashboard without its logo
god kafka offset                     # Kafka offset and consumer-lag commands
god mongo service                    # MongoDB process and service checks
god k8s describe                     # Kubernetes describe commands
god general q "memory usage"         # Host CPU, memory, GPU, and storage knowledge
god network q "list listening ports" # Networking and connectivity knowledge
god elasticsearch shards             # Elasticsearch shard inspection
god kafka native                     # Native Kafka help commands
```

Service and group names must match exactly, but matching is case-insensitive: `god KAFKA OFFSET` and `god kafka offset` are equivalent. Search terms are forgiving and do not need to match an exact route.

### Navigation and search

| Route or key | Result |
|---|---|
| `god <service>` | Group map for one service |
| `god <service> <group>` | Numbered, copy-ready commands |
| `god <service> <group> <number>` | Explanation for one displayed row |
| `--help` | Titles and summaries at the current scope |
| `--details` | Full explanations at the current scope |
| `--tree` | Compact hierarchy |
| `--tree --full` | Hierarchy including native command lines |
| `--keys` | Navigation keys available at the current scope |
| `q` or `-q` | Smart search globally or inside a service/group |
| `--quiet` | Suppress decorative home artwork; accepted anywhere |

Examples:

```bash
god q consumer lag
god kafka q "describe topic"
god q --any consumer group
god q --all consumer group
god q --exact 'active members'
god q --regex 'offset|lag'
god kafka q "publish message" --tree --full
god --keys
god --version
```

View keys work at every meaningful scope. For example, `god --tree`, `god mongo --tree`, and `god mongo replica --tree --full` widen the same view. Row numbers are contextual positions in the currently displayed group; they can change when catalog records are reordered and are not permanent command IDs.

`--quiet` is deliberately distinct from search: only the full token `--quiet` changes decoration;
`-q` continues to mean query. Set `NO_COLOR` to disable ANSI color authoritatively, including when
`GOD_COLOR=always`; the plain logo still appears for a bare `god` on a TTY unless `--quiet` is used.

## How It Works

```text
BASH_GOD.sh                  sourced entry point
god                          direct executable
bash_god/
  core.sh                    routing and initialization
  catalog.sh                 catalog discovery and validation
  art.sh                     pre-rendered, bare-TTY-only identity
  render.sh                  normal terminal views
  search.sh                  ranked text and regex search
  tree.sh                    hierarchy views
  catalog/
    <service>/service.god    one catalog per service
  tests/smoke.sh             non-operational verification
```

The service directory becomes its route automatically. For example, `catalog/mongo/service.god` becomes `god mongo`. Help, search, trees, details, and numbered rows all read the same records, so there is no second command registry to maintain. `.god` files are parsed as inert text and are never sourced or evaluated.

## Add Knowledge

### Add one command

Open the service's single catalog, find the relevant `@group`, and paste a command record beneath related entries. For example, add this under the `resources` group in `bash_god/catalog/general/service.god`:

```text
@command Show filesystem inode usage
@mode LOCAL
@description
Shows inode consumption for mounted filesystems when disk space appears available but file creation fails.
@run
df -ih
@end
```

Then preview and search it without executing `df`:

```bash
GOD_COLOR=never ./god general resources
GOD_COLOR=never ./god general resources q "inode"
./bash_god/tests/smoke.sh
```

Read-only records need no risk field. Add `@risk WRITE`, `@risk WARN`, or `@risk DELETE` when the native command changes state, has high operational impact, or removes something.

### Add one service

Create `bash_god/catalog/redis/service.god`:

```text
@title Redis commands

@description
Curated Redis command knowledge. BASH_GOD displays these commands and never executes them.

@group health

@command Ping a Redis server
@mode MODERN
@description
Checks whether a Redis server accepts a basic request.
@run
redis-cli -h <host> -p <port> PING
@end
```

It is automatically available as `god redis`; no dispatcher edit is needed. See [the contribution guide](bash_god/AGENTS.md) for the complete catalog grammar, parameter format, authoring rules, and contributor checklist.

## Safety and Secrets

- Catalog commands are display-only. Verification renders them but never runs them.
- Replace every `<placeholder>` and review the complete command before copying it into a shell.
- `WRITE`, `WARN`, and `DELETE` labels describe the native command's impact; they are not execution controls.
- Never commit passwords, tokens, private keys, authenticated URIs, decrypted values, or production payloads.
- Use placeholders for environment-specific values and keep credential-bearing configuration outside the catalog.

Once copied, a command is outside BASH_GOD. Your native tool, identity, context, and environment determine what it will do.

## Verification

Run the non-operational checks from the repository root:

```bash
bash -n BASH_GOD.sh god bash_god/core.sh bash_god/catalog.sh bash_god/art.sh bash_god/render.sh bash_god/search.sh bash_god/tree.sh bash_god/tests/smoke.sh
zsh -n BASH_GOD.sh god bash_god/core.sh bash_god/catalog.sh bash_god/art.sh bash_god/render.sh bash_god/search.sh bash_god/tree.sh bash_god/tests/smoke.sh
./bash_god/tests/smoke.sh
git diff --check
```

If `shellcheck` is already installed, it is also useful. BASH_GOD does not require or install it.

## Troubleshooting

- **`god: command not found` after cloning:** run `source ./BASH_GOD.sh`, or use `./god` directly.
- **Unknown service or group:** run `god` or `god <service>` and use the displayed exact route; capitalization does not matter.
- **Search is too narrow:** try `god q --any <words>` or `god q --regex '<pattern>'`.
- **A native command fails:** open the service's `native` group and check the installed tool's help. BASH_GOD displays commands but does not test them against your environment.
- **Unwanted terminal color:** prefix a command with `GOD_COLOR=never`, or set `NO_COLOR`. When
  `NO_COLOR` is present it wins even over `GOD_COLOR=always`.
- **Unwanted home logo:** add `--quiet` anywhere, such as `god --quiet`. Redirects and pipes suppress
  it automatically.
- **Catalog validation fails:** compare the record with [the contribution guide](bash_god/AGENTS.md), especially required fields and the one-line `@run` rule.

## Limitations / Risks

- The catalog is intentionally incomplete and favors common operational memory.
- Smart search is ranked word matching, not an embedding or conversational model.
- Native flags and output can differ between tool versions and environments.
- Contextual row numbers may move when records are added or reordered.
- BASH_GOD cannot make a copied command safe after it leaves the display layer.

## Packaging Status

Direct clone/source and `./god` usage work today. Homebrew and APT packages are not published yet; release archives, checksums, formula metadata, and Linux repository plumbing are future distribution work.

## License

BASH_GOD is released under the [MIT License](LICENSE). In practical terms, you may use, copy, modify, distribute, and sell the software, including commercially, as long as the copyright and license notice remain. The software is provided without warranty.
