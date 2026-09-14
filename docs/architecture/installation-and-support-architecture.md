# BASH_GOD Installation and Support Architecture

**Status:** Current direct-install contract; package-manager layouts are specified for local verification, not yet published.

## Context / Problem

BASH_GOD now has a native terminal helper as well as its shell runtime. A package manager must install both as one versioned unit, while the direct GitHub installer must still be able to update and remove only the files it owns. Mixing those ownership models can leave a launcher pointing at the wrong runtime or let BASH_GOD modify files owned by Homebrew or `dpkg`.

## Goals

- Keep `god` stable as the executable while giving the package a non-conflicting identity: `bash-god`.
- Make the shell runtime, catalog data, native helper, and license move together as one runtime unit.
- Let a launcher work through package-manager symlink chains without hard-coded installation paths.
- Keep user configuration and package-owned files separate.
- Make direct-release maintenance refuse installations it does not own.
- State tested facts separately from future distribution promises.

## Non-goals

- Publish a Homebrew tap, Debian package, or APT repository from this document.
- Make BASH_GOD translate arbitrary Linux commands to macOS or another platform.
- Require Go, Perl, Python, or `expect` for a normal installed runtime.
- Allow a package installation to overwrite a direct GitHub installation, or the reverse.

## Architecture Overview

```text
source checkout                  direct GitHub release                 package manager
--------------                   ---------------------                 ---------------
./god                            PREFIX/bin/god                        stable god link
  |                               |                                     |
src/ + catalog/                  PREFIX/lib/bash-god/god              package-private prefix
root god-tui (optional)          PREFIX/lib/bash-god/{src,catalog}      ├── bin/god
                                 PREFIX/libexec/bash-god/god-tui        ├── lib/bash-god/...
                                 PREFIX/share/licenses/bash-god/...      └── libexec/bash-god/god-tui
                                        |
                               direct-only install manifest
                                        |
                         BASH_GOD update / uninstall allowed
```

`packaging/god` resolves every launcher symlink before it calculates its prefix. This is the shared mechanism that makes a user-created PATH link, a Homebrew Cellar link, and a system launcher resolve to the runtime that contains the helper and catalog set.

## Key Components

| Component | Responsibility |
|---|---|
| `packaging/build-runtime.sh` | Builds the four target-specific release archives from the explicit runtime allowlist. |
| `packaging/god` | Real, relocatable launcher. It follows a bounded symlink chain and runs the sibling runtime. |
| `packaging/install-runtime.sh` | Direct-release installer; verifies assets, activates a target helper, and writes direct-install ownership metadata. |
| `packaging/install.sh` | Public direct-GitHub bootstrap for a user-owned prefix. |
| `src/maintenance.sh` | Allows update/removal only after an exact direct-GitHub ownership check. |
| `src/ui/tui.sh` | Uses only the private, manifest-matched helper in an installed runtime; static browsing remains available without it. |
| XDG directories | Hold user config, cache, state, and data outside all package-manager prefixes. |

## Flow / Behavior

### Ownership by channel

| Channel | Launcher | Runtime and helper | Ownership marker | Upgrade / removal owner |
|---|---|---|---|---|
| Source checkout | `./god` | repository `src/`, `catalog/`, optional root `god-tui` | none | developer / Git |
| Direct GitHub release | `PREFIX/bin/god` | `PREFIX/lib/bash-god`, `PREFIX/libexec/bash-god/god-tui` | `PREFIX/share/bash-god/install-manifest` | BASH_GOD after exact manifest validation |
| Homebrew formula | Formula `bin/god` symlinked to `libexec/bin/god` | Formula `libexec/{lib/bash-god,libexec/bash-god/god-tui}` | none | Homebrew |
| Debian package (planned) | `/usr/bin/god` | `/usr/lib/bash-god`, `/usr/libexec/bash-god/god-tui` | none | `dpkg` / APT |

The direct installer writes the manifest *after* it validates and activates a release archive. A normal release archive deliberately does not contain it. That distinction prevents a copied archive or package-managed layout from accidentally becoming eligible for automatic update or deletion.

### Homebrew layout

A formula unpacks one verified target archive into the formula's private `libexec` directory, then exposes only the launcher with Homebrew's relative `bin.install_symlink libexec/"bin/god"`. Homebrew itself may add another link from its global `bin`; the launcher follows both links and sees the formula `libexec` directory as its runtime prefix.

This uses Homebrew's intended private `libexec` boundary and relative symlink helper. The formula must never call the direct installer and must not create the direct-install manifest. `god --uninstall` therefore refuses safely and tells the operator to use the owning package manager.

### Debian layout

A `.deb` should stage the same selected Linux archive under `/usr`, with the real launcher at `/usr/bin/god`, runtime at `/usr/lib/bash-god`, and helper at `/usr/libexec/bash-god/god-tui`. The package must not use `/usr/local`, run `--resync`, invoke catalog commands, edit shell startup files, or create per-user XDG data during installation. It must contain no direct-install manifest.

The native helper makes the package architecture-specific: `amd64` and `arm64` packages carry their matching Linux helper. A package is not `Architecture: all` merely because most of its runtime is shell.

### User-owned state

The runtime reads or writes only the normal XDG locations (or their documented home-directory fallbacks): configuration, cache, state, and data. They are not package payload and are not created by Homebrew or Debian installation. Direct `god --uninstall` may remove those directories only after the exact direct-release ownership check; package managers leave them to the user.

### Runtime capability and fallback

The installed command needs Bash and the ordinary host utilities used by the shell runtime. The rich picker additionally needs a compatible native helper, a controlling TTY, a non-`dumb` terminal, and its bounded local terminal facilities. If that capability is absent, mismatched, or unsupported, BASH_GOD retains the static copy-ready view; it does not download a helper or fail basic browsing.

Go is a release-build dependency only. `expect` is a test dependency only. Python or zsh is used only as a fallback for command-line editing when Bash readline prefill is unavailable. Perl is not a runtime dependency.

| Capability | Required locally | Fallback / boundary |
|---|---|---|
| Static browsing and search | Bash 3.2+ and normal base-system text utilities | No native helper, network, service client, Go, Python, zsh, or `expect` is required. |
| Reviewed picker | Static-browsing requirements, the matching packaged helper, `base64`, `mkfifo`, a controlling TTY, and a non-`dumb` terminal | Any missing or incompatible part keeps the static copy-ready result view. |
| Native `e` editing | Bash readline prefill when available; otherwise zsh `vared` or Python 3 readline | If no supported editor is present, editing fails clearly without affecting browsing or direct copying. |
| Discovery and native execution | The exact catalog-declared client and environment facts for the chosen command | BASH_GOD never installs a service client or server; a missing or ineligible requirement stays knowledge only. |
| Direct GitHub installation / maintenance | The bootstrap and updater use `curl` plus a host SHA-256 utility | Package-manager installation, upgrade, and removal are deliberately outside this path. |
| Build and test | Pinned Go toolchain; `expect` and zsh for real-PTY coverage | These are contributor/CI requirements, never a normal installed-runtime dependency. |

### Verified host matrix

The release target families are tested on these pinned CI hosts:

| Target artifact | Native verification host |
|---|---|
| `linux-amd64` | Ubuntu 24.04 x86_64 |
| `linux-arm64` | Ubuntu 24.04 ARM64 |
| `darwin-amd64` | macOS 15 Intel |
| `darwin-arm64` | macOS 14 Apple Silicon |

This is a verification matrix, not an implied guarantee for every terminal emulator, OS revision, or
Linux distribution. It is the concrete basis for direct-release artifacts and Homebrew's selected
target archives; public installation copy should name only the supported target families until
channel-specific support evidence establishes a broader support floor.

### Platform evidence and policy

The current release builder emits only these helper targets:

```text
darwin-amd64   darwin-arm64   linux-amd64   linux-arm64
```

The CI matrix supplies native terminal evidence for those target families, including Linux ARM and macOS Intel/Apple Silicon runners. That is evidence for the target matrix, not a promise about every macOS release, Linux distribution, terminal emulator, SSH configuration, or package-manager version. The public minimum OS policy remains intentionally uncommitted until clean Homebrew and Debian/Ubuntu installation jobs establish it. Documentation must not advertise a broader support floor meanwhile.

## Extensibility / How to Change It

- Add a release file only through the shared runtime allowlist in `packaging/build-runtime.sh`; update the staged-file assertions in `packaging/tests/runtime-package-smoke.sh` at the same time.
- Test a new launcher layout with real symlink chains before claiming package-manager support.
- Keep package-manager metadata outside the runtime archive and never add an ownership manifest to it.
- Add a target only when release build, installed-runtime PTY coverage, artifact validation, and the support statement can all be updated together.
- Treat package name, release-version mapping, Debian signing key custody, and repository hosting as explicit product decisions. Do not infer them from a local build.

## Verification

- `packaging/tests/runtime-package-smoke.sh` builds target archives, validates their exact file inventory and helper protocol, installs into temporary prefixes, and checks a symlinked launcher.
- `packaging/tests/install-smoke.sh` and `packaging/tests/maintenance-smoke.sh` verify direct-release installation, update, ownership checks, and conservative removal with isolated homes.
- `packaging/tests/installed-tui-pty-smoke.sh` exercises a staged installed artifact through a real PTY and fake native clients.
- The Homebrew layout is designed against the official [Formula Cookbook](https://docs.brew.sh/Formula-Cookbook), which specifies private `libexec` use and `bin.install_symlink` for relative links.
- The Debian layout follows the official [Debian Maintainers' Guide](https://www.debian.org/doc/manuals/maint-guide/), which reserves `/usr/local` for the system administrator and directs packages to standard system paths.

## Limitations / Risks

- A direct archive checksum is integrity evidence, not an independent signing identity.
- Production APT signing, hosting, and Debian package metadata remain unsettled by this architecture note.
- Homebrew ownership is verified separately from direct-release ownership. Debian remains unavailable
  until its own install, upgrade, removal, and CI verification gates pass.
- A package manager cannot safely reconcile a pre-existing direct installation in the same command name/path; installation documentation must require the operator to choose and remove the previous owner deliberately.
