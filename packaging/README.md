# Runtime Packaging

## Context / Problem

This directory builds and verifies the CLI-only BASH_GOD distribution. The package is intentionally
smaller than the source repository and never includes personal shell aliases or the sourced
`BASH_GOD.sh` entry point.

## Scope

This workflow supports an unprivileged, real-file installation under an absolute prefix such as
`$HOME/.local`. It does not publish Homebrew, RPM, or APT repository metadata and does not edit shell
startup files.

## Implementation Summary

The builder emits a runtime archive, a low-level standalone installer, the public `install.sh`
bootstrap, and one SHA-256 file for each asset. The low-level installer snapshots and validates the
supplied archive, probes the staged CLI, activates only allowlisted runtime files, and records a
managed-install manifest. The public bootstrap resolves the latest GitHub Release and installs its
checksum-verified archive.

## Architecture / Flow

```text
bash-god-VERSION/
  bin/god                              relocatable prefix launcher
  lib/bash-god/god                     repository CLI launcher
  lib/bash-god/bash_god/*.sh           eleven runtime modules, including discovery and execution
  lib/bash-god/bash_god/catalog/*/service.god
  share/bash-god/install-manifest      direct-GitHub ownership metadata
  share/licenses/bash-god/LICENSE
```

The installed `bin/god` must be a real file, not a symlink. It finds the internal runtime relative to
its installation prefix, while the internal launcher retains the repository-relative module layout
already exercised by the main smoke suite.

Release assets are kept separate from the installed runtime:

```text
bash-god-VERSION.tar.gz
bash-god-VERSION.tar.gz.sha256
install-runtime.sh
install-runtime.sh.sha256
install.sh
install.sh.sha256
```

## Verification

```bash
./packaging/build-runtime.sh
./packaging/tests/runtime-package-smoke.sh
./packaging/tests/install-smoke.sh
./packaging/tests/maintenance-smoke.sh
```

The builder writes all six listed assets beneath `dist/`. It refuses to overwrite existing files or
dangling symlinks. The package smoke test builds from scratch, verifies both executable script
assets and all relevant checksums, installs beneath a temporary prefix, compares the exact 22-file
installed allowlist, checks for credential material, exercises navigation/search/tree views with an
empty environment, rejects malformed packages and checksums, and verifies that replacement requires
`--replace` and retains a usable previous runtime. The install and maintenance suites use isolated
homes and prefixes; they never change a real installation.

## Automated Quality Gates

`.github/workflows/smoke.yml` runs the main command-memory suite and all three packaging suites for
every pull request into `main`, every update to `main`, and every merge-queue candidate. The stable
required-check name is **Full smoke suite**.

`.github/workflows/release.yml` runs only for `v*` tags. It calls the same smoke workflow first,
checks that `vVERSION` matches `bash_god/core.sh`, rejects a tagged commit that is not contained in
`main`, builds the six release assets, and creates the GitHub Release only after every check passes.

GitHub Actions cannot make its own check mandatory. In the repository's `main` branch ruleset,
enable **Require a pull request before merging** and require the **Full smoke suite** status check.
That one-time repository setting turns the workflow result into the merge gate; without it, the
workflow reports failures but GitHub can still allow a merge.

## Public Installation

The public entry point is intentionally one command:

```bash
bash <(curl -fsSL https://github.com/hemang11/BASH-GOD/releases/latest/download/install.sh)
```

`install.sh` uses `$HOME/.local` by default, refuses unrelated or partial installations, downloads
the archive and low-level installer, verifies both against their release checksums, and performs no
downgrade. Re-running it while current is idempotent. An older direct-GitHub installation is upgraded
through the same verified replacement path.

The checksum beside `install.sh` remains a release asset for pinned/manual workflows. The one-line
bootstrap itself is trusted through HTTPS, then verifies every subsequently downloaded executable
and archive before activation.

## Local Installation Test

```bash
./packaging/install-runtime.sh --prefix /absolute/test/prefix \
  dist/bash-god-VERSION.tar.gz \
  dist/bash-god-VERSION.tar.gz.sha256
```

The default prefix is `$HOME/.local`. The installer does not use `sudo`, edit shell startup files, or
execute any catalog command. It refuses to replace an unrelated `bin/god` or runtime directory.

## Low-level Upgrade Flow

Build or download and verify the newer release assets, then pass `--replace` to the same installer:

```bash
./install-runtime.sh --replace --prefix /absolute/prefix \
  bash-god-NEW_VERSION.tar.gz \
  bash-god-NEW_VERSION.tar.gz.sha256
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

1. Merge through a pull request whose required **Full smoke suite** check passed.
2. Confirm the version in `bash_god/core.sh` and push the matching immutable tag `vVERSION` from
   `main`.
3. Let the release workflow repeat every smoke suite, build the clean assets, and publish the archive,
   both installers, public bootstrap, and all three `.sha256` files.
4. Download the public assets and repeat an isolated-prefix install before announcing the release.

The same prefix layout can later be consumed by RPM and DEB packaging without changing the runtime
catalog or dispatcher. This first release supports direct real-file installation only; Homebrew's
standard symlinked Cellar launcher needs separate formula work and is not supported yet.

## Limitations / Risks

- Checksums provide integrity for assets downloaded from the same trusted GitHub release; they are
  not a separate code-signing identity.
- Release archives are not reproducible byte-for-byte because tar ownership and timestamps are not
  normalized yet.
- An interrupted upgrade retains the previous runtime and attempts to restore it when activation has
  not completed; the installer prints any path that still needs manual recovery.
- The bootstrap and automatic check depend on GitHub's latest-release redirect; the low-level
  installer remains available for pinned or automated installation flows.
