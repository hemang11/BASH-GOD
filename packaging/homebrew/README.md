# Homebrew Formula Rendering

This directory holds the release-time formula renderer, not a checked-in formula with an old GitHub
Release checksum. The published formula lives in
[`hemang11/homebrew-tap`](https://github.com/hemang11/homebrew-tap) under `Formula/bash-god.rb`.
The release workflow owns normal publication: after it publishes a verified GitHub Release, it
downloads the four target archives again, verifies their published SHA-256 files, renders this
formula, and commits the result to the tap's `live` branch. A maintainer does not hand-edit the
formula for each version.

That workflow requires `HOMEBREW_TAP_TOKEN` as an encrypted secret in `hemang11/BASH-GOD`. Use a
fine-grained GitHub token restricted to `hemang11/homebrew-tap`, with only **Contents: Read and
write** repository permission. Never put the token in a catalog, formula, release asset, or Git
remote URL.

For local review, render the formula from exact immutable bytes:

```bash
packaging/homebrew/render-formula.sh \
  --version "$(awk -F\"'\" '/^_BASH_GOD_VERSION=/ { print $2; exit }' src/core.sh)" \
  --darwin-amd64 dist/bash-god-VERSION-darwin-amd64.tar.gz \
  --darwin-arm64 dist/bash-god-VERSION-darwin-arm64.tar.gz \
  --linux-amd64 dist/bash-god-VERSION-linux-amd64.tar.gz \
  --linux-arm64 dist/bash-god-VERSION-linux-arm64.tar.gz \
  --output Formula/bash-god.rb
```

The formula pins versioned GitHub Release URLs and SHA-256 checksums; it must never point at a
mutable `latest` download. It installs the selected archive beneath Formula-private `libexec` and
exposes the relocatable launcher through a relative `bin` symlink. It never uses the direct GitHub
installer or creates its ownership manifest. During each Formula install or upgrade, Homebrew runs
the packaged `god --resync` as a quiet, non-fatal post-install step. That hydrates the invoking
user's discovery cache with local client paths, versions, and candidate targets before the first
search; it does not run a catalog operation or make a failed optional client block installation. The
Formula writes an inert `package-owner` marker inside its private `libexec` runtime so BASH_GOD can
direct `god --uninstall` and its help footer to `brew uninstall bash-god` without guessing from paths.

Run `bash packaging/tests/homebrew-layout-smoke.sh` before a tap change. The test creates release
archives locally, validates the generated Formula syntax and hashes, and proves the real launcher
through a Homebrew-shaped Cellar/global symlink chain. On macOS, also run
`bash packaging/tests/homebrew-install-smoke.sh`; it uses a disposable Homebrew prefix to prove
installation, runtime resolution, and uninstall without changing the user's real Homebrew setup.
