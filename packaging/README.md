# Runtime Packaging

## Context / Problem

This directory builds and verifies the CLI-only BASH_GOD distribution. The package is intentionally
smaller than the source repository and never includes personal shell aliases or the sourced
`BASH_GOD.sh` entry point.

## Scope

This workflow supports an unprivileged, real-file installation under an absolute prefix such as
`$HOME/.local`. It builds the immutable runtime assets and the reviewed Homebrew formula input, but
does not itself publish a tap, RPM, or APT repository and does not edit shell startup files.

## Implementation Summary

The builder emits four target-specific runtime archives, one narrow compatibility bridge archive, a
low-level standalone installer, the public `install.sh` bootstrap, and one SHA-256 file for each
asset. The low-level installer snapshots and validates the supplied archive, probes the staged CLI
and native helper, activates only allowlisted runtime files, and records a managed-install manifest.
The public bootstrap resolves the latest GitHub Release, detects one supported host target exactly,
and installs its checksum-verified archive.

Installed users never need Go. Release construction needs the Go version pinned in `go.mod`; source
contributors may optionally build a repository-root helper with
`go build -o god-tui ./cmd/god-tui`. Without that development helper, a source checkout correctly
uses the static search view.

The supported direct-install matrix is deliberately explicit:

```text
darwin-amd64   darwin-arm64   linux-amd64   linux-arm64
```

Unknown `uname` values and a mismatched target archive fail before extraction. The installer never
chooses an architecture by approximation.

## Architecture / Flow

```text
bash-god-VERSION/
  bin/god                              relocatable prefix launcher
  lib/bash-god/god                     repository CLI launcher
  lib/bash-god/tui-manifest            shell/helper version and protocol contract
  lib/bash-god/src/*.sh                eight core runtime modules
  lib/bash-god/src/ui/*.sh             six terminal UI modules, including the optional helper adapter
  lib/bash-god/catalog/*/service.god
  libexec/bash-god/god-tui             one selected native helper
  share/licenses/bash-god/LICENSE
  share/licenses/bash-god/THIRD_PARTY_NOTICES.md
```

The archive itself intentionally does **not** contain `share/bash-god/install-manifest`. The direct
installer writes that ownership record only after it has verified and activated an archive under a
user-owned prefix. A package-manager layout must never receive that record: Homebrew, `dpkg`, or
another owner remains responsible for its own upgrade and removal.

The package-owned `bin/god` is a real file. It finds the internal runtime relative to its installation
prefix, while its launcher resolution also supports an external symlink that points to that managed
file. The internal launcher retains the repository-relative module layout already exercised by the
main smoke suite.

Release assets are kept separate from the installed runtime:

```text
bash-god-VERSION-darwin-amd64.tar.gz
bash-god-VERSION-darwin-amd64.tar.gz.sha256
bash-god-VERSION-darwin-arm64.tar.gz
bash-god-VERSION-darwin-arm64.tar.gz.sha256
bash-god-VERSION-linux-amd64.tar.gz
bash-god-VERSION-linux-amd64.tar.gz.sha256
bash-god-VERSION-linux-arm64.tar.gz
bash-god-VERSION-linux-arm64.tar.gz.sha256
install-runtime.sh
install-runtime.sh.sha256
install.sh
install.sh.sha256
```

`bash-god-VERSION.tar.gz` and its checksum are also published as a **legacy update bridge**. It
contains all four helpers and is accepted only because an older direct-GitHub installation requests
the old unsuffixed archive name before it can run the target-aware updater. The new bootstrap and all
new runtime updates request only the target-specific archive. The current installer detects the host
and extracts exactly one matching helper from the bridge; this bridge is not treated as an
architecture-independent normal package.

## Verification

```bash
./packaging/build-runtime.sh
./packaging/tests/runtime-package-smoke.sh
./packaging/tests/homebrew-layout-smoke.sh
./packaging/tests/homebrew-install-smoke.sh
./packaging/tests/install-smoke.sh
./packaging/tests/maintenance-smoke.sh
```

The builder writes 14 assets beneath `dist/`: five archives, seven corresponding checksum files,
and the two executable installer scripts. It
refuses to overwrite existing files or dangling symlinks. The package smoke test builds from
scratch, verifies every checksum and helper mode, installs beneath temporary prefixes without Go on
`PATH`, checks the private-helper manifest through normal and symlinked launchers, verifies the
legacy bridge selection, rejects a foreign/unknown target before activation, rejects malformed
packages and checksums, and verifies that replacement retains the paired prior runtime and helper.
It also builds twice and requires byte-identical release assets. The install and maintenance suites
use isolated homes and prefixes; they never change a real installation. The Homebrew installation
suite uses an isolated temporary Cellar and confirms install, launcher resolution, and uninstall.

## Automated Quality Gates

`.github/workflows/smoke.yml` runs the main command-memory suite and packaging suites for every pull
request into `main`, every update to `main`, and every merge-queue candidate. Its required checks
are **Full smoke suite**, **Native terminal runtime (linux-arm64)**, **Native terminal runtime
(darwin-amd64)**, and **Native terminal runtime (darwin-arm64)**.

`.github/workflows/release.yml` runs only for `v*` tags. It calls the same smoke workflow first,
checks that `vVERSION` matches `src/core.sh`, rejects a tagged commit that is not contained in
`main`, installs the pinned Go toolchain, cross-compiles the four helpers, builds the target assets
and bridge, and creates the GitHub Release only after every check passes.

GitHub Actions cannot make its own checks mandatory. The repository's `main` protection requires a
pull request, one approval, resolved conversations, an up-to-date base, and all four contexts above.
It also applies to administrators, so a failed native terminal job cannot be bypassed by merging
directly to `main`.

## Public Installation

The public entry point is intentionally one command:

```bash
bash <(curl -fsSL https://github.com/hemang11/BASH-GOD/releases/latest/download/install.sh)
```

`install.sh` uses `$HOME/.local` by default, refuses unrelated or partial installations, downloads
the matching target archive and low-level installer, verifies both against their release checksums,
and performs no downgrade. Re-running it while current is idempotent. An older direct-GitHub
installation is upgraded through the verified unsuffixed bridge exactly once; after that, the
installed target-aware updater uses the matching archive directly.

The checksum beside `install.sh` remains a release asset for pinned/manual workflows. The one-line
bootstrap itself is trusted through HTTPS, then verifies every subsequently downloaded executable
and archive before activation.

## Local Installation Test

```bash
./packaging/install-runtime.sh --prefix /absolute/test/prefix \
  dist/bash-god-VERSION-OS-ARCH.tar.gz \
  dist/bash-god-VERSION-OS-ARCH.tar.gz.sha256
```

The default prefix is `$HOME/.local`. The installer does not use `sudo`, edit shell startup files, or
execute any catalog command. It refuses to replace an unrelated `bin/god` or runtime directory.

## Low-level Upgrade Flow

Build or download and verify the newer release assets, then pass `--replace` to the same installer:

```bash
./install-runtime.sh --replace --prefix /absolute/prefix \
  bash-god-NEW_VERSION-OS-ARCH.tar.gz \
  bash-god-NEW_VERSION-OS-ARCH.tar.gz.sha256
```

The installer accepts only a managed existing runtime, retains it in a uniquely named backup
directory, activates the verified replacement, and prints the backup path.

## Update and Removal

The direct-GitHub runtime contains `maintenance.sh`. Only a bare interactive `god` invocation may
perform a cached latest-release check; scoped knowledge commands, redirects, pipes, `--quiet`, and
sourcing do not. When a newer version exists, an arrow-key menu offers **Update** or **Not now**.
Network failure is silent and deferred.

`god --uninstall` is the explicit removal route. It verifies the install manifest and launcher
marker, lists every target, defaults to **Cancel**, and only then offers **Uninstall everything**.
Confirmation removes all BASH_GOD-owned runtime, launcher, backups, license, metadata, configuration,
cache, state, and data. It refuses source checkouts and package-manager-owned installations.

## Release Checklist

1. Merge through a pull request whose four required smoke and native-terminal checks passed.
2. Confirm the version in `src/core.sh` and push the matching immutable tag `vVERSION` from
   `main`.
3. Let the release workflow repeat every smoke suite, build the clean target assets and bridge, and
   publish both installers, public bootstrap, and every `.sha256` file.
4. Render `Formula/bash-god.rb` from the published target archives, then review, install, test, and
   publish it in `hemang11/homebrew-tap`.
5. Download the host target asset and repeat an isolated-prefix install before announcing the release.

The Homebrew tap installs the same staged runtime without changing the catalog or dispatcher.
Debian packaging remains deferred; see the [installation and support architecture](../docs/architecture/installation-and-support-architecture.md)
for the ownership and launcher contract.

## Limitations / Risks

- Checksums provide integrity for assets downloaded from the same trusted GitHub release; they are
  not a separate code-signing identity.
- The helper is cross-compiled on the release runner. The package suite executes the current host's
  helper and validates every other target's archive structure, mode, manifest, and checksum; native
  PTY behavior on each target still requires native release-CI evidence.
- Release archives normalize file ordering, timestamps, and ownership; the package suite compares
  two clean builds byte-for-byte.
- An interrupted upgrade retains the previous runtime and attempts to restore it when activation has
  not completed; the installer prints any path that still needs manual recovery.
- The bootstrap and automatic check depend on GitHub's latest-release redirect; the low-level
  installer remains available for pinned or automated installation flows.
