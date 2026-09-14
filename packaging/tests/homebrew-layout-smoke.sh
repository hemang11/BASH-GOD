#!/usr/bin/env bash

# Fake-only Homebrew layout proof. It validates the formula renderer and the
# real launcher through the same nested Cellar/libexec/global-bin symlink shape
# that Homebrew uses, without installing anything into a user's Homebrew tree.

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
renderer="$repo_dir/packaging/homebrew/render-formula.sh"

checks=0
failures=0

pass() {
  checks=$((checks + 1))
  printf 'ok %02d - %s\n' "$checks" "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'not ok %02d - %s\n' "$checks" "$1"
}

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  else
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  fi
}

platform() {
  case "$(uname -s):$(uname -m)" in
    Darwin:x86_64|Darwin:amd64) printf '%s\n' darwin-amd64 ;;
    Darwin:arm64|Darwin:aarch64) printf '%s\n' darwin-arm64 ;;
    Linux:x86_64|Linux:amd64) printf '%s\n' linux-amd64 ;;
    Linux:arm64|Linux:aarch64) printf '%s\n' linux-arm64 ;;
    *) return 1 ;;
  esac
}

fixture="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-homebrew-layout.XXXXXX")" || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

if ! command -v go >/dev/null 2>&1; then
  fail 'Homebrew layout proof requires Go to build the native helper artifacts'
  printf '\n%d Homebrew layout checks passed.\n' "$((checks - failures))"
  exit 1
fi
if ! command -v ruby >/dev/null 2>&1; then
  fail 'Homebrew layout proof requires Ruby to parse the generated Formula'
  printf '\n%d Homebrew layout checks passed.\n' "$((checks - failures))"
  exit 1
fi

host_target="$(platform)" || {
  fail 'Homebrew layout proof requires a host in the release target matrix'
  printf '\n%d Homebrew layout checks passed.\n' "$((checks - failures))"
  exit 1
}
version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$repo_dir/src/core.sh")"
assets="$fixture/assets"
formula="$fixture/bash-god.rb"
mkdir -p "$assets" "$fixture/home" "$fixture/config" "$fixture/cache" "$fixture/state" "$fixture/data" "$fixture/homebrew-cache" || exit 1

if "$repo_dir/packaging/build-runtime.sh" "$assets" >/dev/null; then
  pass 'release builder creates the archive set used by the Homebrew formula'
else
  fail 'release builder creates the archive set used by the Homebrew formula'
  printf '\n%d of %d Homebrew layout checks failed.\n' "$failures" "$checks" >&2
  exit 1
fi

"$renderer" \
  --version "$version" \
  --darwin-amd64 "$assets/bash-god-$version-darwin-amd64.tar.gz" \
  --darwin-arm64 "$assets/bash-god-$version-darwin-arm64.tar.gz" \
  --linux-amd64 "$assets/bash-god-$version-linux-amd64.tar.gz" \
  --linux-arm64 "$assets/bash-god-$version-linux-arm64.tar.gz" \
  --output "$formula"
render_status=$?
install_method_count="$(LC_ALL=C awk '$0 == "  def install" { count++ } END { print count + 0 }' "$formula")"
if [ "$render_status" -eq 0 ] && ruby -c "$formula" >/dev/null 2>&1 && \
   contains "$(command cat "$formula")" 'bin.install_symlink libexec/"bin/god"' && \
   ! contains "$(command cat "$formula")" "  version \"$version\"" && \
   [ "$install_method_count" -eq 1 ] && \
   contains "$(command cat "$formula")" "bash-god-$version-darwin-arm64.tar.gz" && \
   contains "$(command cat "$formula")" "$(sha256 "$assets/bash-god-$version-darwin-arm64.tar.gz")" && \
   contains "$(command cat "$formula")" "$(sha256 "$assets/bash-god-$version-linux-amd64.tar.gz")"; then
  pass 'renderer creates a syntax-valid multi-target formula with exact archive checksums'
else
  fail 'renderer creates a syntax-valid multi-target formula with exact archive checksums'
fi

# Lint a neutral copy of the generated file. Homebrew still loads an already
# installed tap Formula/bash-god.rb and sees its BashGod#install alongside the
# isolated copy, so exclude only that external duplicate-method false positive.
# The assertion above proves the generated Formula itself has exactly one
# install method; tap publication separately audits the named installed file.
if command -v brew >/dev/null 2>&1; then
  style_formula="$fixture/generated-homebrew-formula.rb"
  cp "$formula" "$style_formula" || exit 1
  brew_style_status=0
  brew_style_output="$(HOMEBREW_DEVELOPER=1 HOMEBREW_CACHE="$fixture/homebrew-cache" HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 brew style --except-cops Lint/DuplicateMethods "$style_formula" 2>&1)" || brew_style_status=$?
  if [ "$brew_style_status" -eq 0 ]; then
    pass 'Homebrew style accepts the generated Formula DSL'
  else
    fail 'Homebrew style accepts the generated Formula DSL'
    printf '%s\n' "$brew_style_output"
  fi
else
  printf '# Homebrew is unavailable; Ruby syntax still verifies the generated Formula on this host.\n'
fi

render_again_status=0
render_again_output="$("$renderer" \
  --version "$version" \
  --darwin-amd64 "$assets/bash-god-$version-darwin-amd64.tar.gz" \
  --darwin-arm64 "$assets/bash-god-$version-darwin-arm64.tar.gz" \
  --linux-amd64 "$assets/bash-god-$version-linux-amd64.tar.gz" \
  --linux-arm64 "$assets/bash-god-$version-linux-arm64.tar.gz" \
  --output "$formula" 2>&1)" || render_again_status=$?
if [ "$render_again_status" -ne 0 ] && \
   contains "$render_again_output" 'refusing to overwrite an existing formula'; then
  pass 'renderer preserves an already reviewed formula instead of replacing it'
else
  fail 'renderer preserves an already reviewed formula instead of replacing it'
fi

cellar="$fixture/Homebrew Cellar/bash-god/$version"
global_bin="$fixture/Homebrew Prefix/bin"
stage="$fixture/stage"
host_archive="$assets/bash-god-$version-$host_target.tar.gz"
package_root="bash-god-$version-$host_target"
mkdir -p "$cellar/libexec" "$cellar/bin" "$global_bin" "$stage" || exit 1
tar -xzf "$host_archive" -C "$stage" || exit 1
mv "$stage/$package_root"/* "$cellar/libexec/" || exit 1
ln -s '../libexec/bin/god' "$cellar/bin/god"
ln -s "$cellar/bin/god" "$global_bin/god"

version_output="$(HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_CACHE_HOME="$fixture/cache" XDG_STATE_HOME="$fixture/state" XDG_DATA_HOME="$fixture/data" BASH_GOD_SKIP_INITIAL_RESYNC=1 GOD_COLOR=never "$global_bin/god" --version 2>&1)"
quiet_output="$(HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_CACHE_HOME="$fixture/cache" XDG_STATE_HOME="$fixture/state" XDG_DATA_HOME="$fixture/data" BASH_GOD_SKIP_INITIAL_RESYNC=1 GOD_COLOR=never "$global_bin/god" general --quiet 2>&1)"
if [ "$version_output" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$version")" ] && \
   contains "$quiet_output" 'GENERAL COMMANDS' && \
   [ "$(readlink "$cellar/bin/god")" = '../libexec/bin/god' ]; then
  pass 'nested Homebrew-style links resolve the private runtime and preserve harmless browsing'
else
  fail 'nested Homebrew-style links resolve the private runtime and preserve harmless browsing'
fi

uninstall_status=0
uninstall_output="$(HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_CACHE_HOME="$fixture/cache" XDG_STATE_HOME="$fixture/state" XDG_DATA_HOME="$fixture/data" BASH_GOD_SKIP_INITIAL_RESYNC=1 GOD_COLOR=never "$global_bin/god" --uninstall 2>&1)" || uninstall_status=$?
if [ "$uninstall_status" -eq 2 ] && \
   contains "$uninstall_output" 'not a managed GitHub Release installation' && \
   [ -x "$cellar/libexec/bin/god" ] && \
   [ -x "$cellar/libexec/libexec/bash-god/god-tui" ] && \
   [ ! -e "$cellar/libexec/share/bash-god/install-manifest" ]; then
  pass 'package-managed layout refuses BASH_GOD maintenance without changing Formula-owned files'
else
  fail 'package-managed layout refuses BASH_GOD maintenance without changing Formula-owned files'
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d Homebrew layout checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d Homebrew layout checks failed.\n' "$failures" "$checks" >&2
exit 1
