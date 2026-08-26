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

The builder emits a runtime archive, a standalone installer, and a SHA-256 file for each. The
installer snapshots and validates the supplied archive, probes the staged CLI, and activates only
the allowlisted runtime files.

## Architecture / Flow

```text
bash-god-VERSION/
  bin/god                              relocatable prefix launcher
  lib/bash-god/god                     repository CLI launcher
  lib/bash-god/bash_god/*.sh           six runtime modules
  lib/bash-god/bash_god/catalog/*/service.god
  share/licenses/bash-god/LICENSE
```

The installed `bin/god` must be a real file, not a symlink. It finds the internal runtime relative to
its installation prefix, while the internal launcher retains the repository-relative module layout
already exercised by the main smoke suite.

## Verification

```bash
./packaging/build-runtime.sh
./packaging/tests/runtime-package-smoke.sh
```

The builder writes `dist/bash-god-VERSION.tar.gz`, `dist/install-runtime.sh`, and a matching `.sha256`
file for each. It refuses to overwrite existing files or dangling symlinks. The package smoke test
builds from scratch, verifies the installer asset, installs beneath a temporary prefix, compares the
exact 16-file runtime allowlist, checks for credential material, exercises navigation/search/tree
views with an empty environment, rejects malformed packages and checksums, and verifies that
replacement requires `--replace` and retains a usable previous runtime.

## Local Installation Test

```bash
./packaging/install-runtime.sh --prefix /absolute/test/prefix \
  dist/bash-god-VERSION.tar.gz \
  dist/bash-god-VERSION.tar.gz.sha256
```

The default prefix is `$HOME/.local`. The installer does not use `sudo`, edit shell startup files, or
execute any catalog command. It refuses to replace an unrelated `bin/god` or runtime directory.

## Upgrade Flow

Build or download and verify the newer release assets, then pass `--replace` to the same installer:

```bash
./install-runtime.sh --replace --prefix /absolute/prefix \
  bash-god-NEW_VERSION.tar.gz \
  bash-god-NEW_VERSION.tar.gz.sha256
```

The installer accepts only a managed existing runtime, retains it in a uniquely named backup
directory, activates the verified replacement, and prints the backup path. There is deliberately no
networked `god update` command: runtime upgrades remain outside the display-only knowledge CLI.

## Release Checklist

1. Confirm the version in `bash_god/core.sh` and use the matching immutable tag `vVERSION`.
2. Run the main smoke suite and the runtime-package smoke suite.
3. Build into a clean `dist/` directory.
4. Publish the archive, installer, and both `.sha256` files as release assets.
5. Download the public assets and repeat an isolated-prefix install before announcing the release.

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
