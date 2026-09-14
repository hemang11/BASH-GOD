# Homebrew Formula Rendering

This directory holds the release-time formula renderer, not a checked-in formula with an old GitHub
Release checksum. The published formula lives in
[`hemang11/homebrew-tap`](https://github.com/hemang11/homebrew-tap) under `Formula/bash-god.rb`.
After `packaging/build-runtime.sh` creates all four target archives, render the formula from those
exact immutable bytes:

```bash
packaging/homebrew/render-formula.sh \
  --version "$(awk -F\"'\" '/^_BASH_GOD_VERSION=/ { print $2; exit }' src/core.sh)" \
  --darwin-amd64 dist/bash-god-VERSION-darwin-amd64.tar.gz \
  --darwin-arm64 dist/bash-god-VERSION-darwin-arm64.tar.gz \
  --linux-amd64 dist/bash-god-VERSION-linux-amd64.tar.gz \
  --linux-arm64 dist/bash-god-VERSION-linux-arm64.tar.gz \
  --output Formula/bash-god.rb
```

For a release, download the four published target archives again and render the formula from those
downloads before committing it to the tap. It installs the selected archive beneath Formula-private
`libexec` and exposes the relocatable launcher through a relative `bin` symlink. It never uses the
direct GitHub installer or creates its ownership manifest.

Run `bash packaging/tests/homebrew-layout-smoke.sh` before a tap change. The test creates release
archives locally, validates the generated Formula syntax and hashes, and proves the real launcher
through a Homebrew-shaped Cellar/global symlink chain. On macOS, also run
`bash packaging/tests/homebrew-install-smoke.sh`; it uses a disposable Homebrew prefix to prove
installation, runtime resolution, and uninstall without changing the user's real Homebrew setup.
