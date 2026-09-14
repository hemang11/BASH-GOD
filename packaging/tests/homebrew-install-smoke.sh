#!/usr/bin/env bash

# macOS-only, fake-only Homebrew installation proof. It bootstraps a disposable
# Homebrew prefix that shares only the read-only Homebrew program files, then
# installs a Formula that references fixture-local release archives. It never
# writes to the caller's real Cellar, taps, prefix, or BASH_GOD configuration.

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
renderer="$repo_dir/packaging/homebrew/render-formula.sh"
version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$repo_dir/src/core.sh")"

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

case "$(uname -s)" in
  Darwin) ;;
  *)
    printf '# Homebrew install smoke is macOS-only; Formula layout remains covered on this host.\n'
    exit 0
    ;;
esac

for tool in brew go ruby; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'BASH_GOD Homebrew install smoke requires %s.\n' "$tool" >&2
    exit 2
  fi
done

fixture="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-homebrew-install.XXXXXX")" || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

real_repository="$(brew --repository)"
real_brew="$real_repository/bin/brew"
real_library="$real_repository/Library/Homebrew"
real_core_tap="$real_repository/Library/Taps/homebrew/homebrew-core"
[ -x "$real_brew" ] && [ -d "$real_library" ] && [ -d "$real_core_tap" ] || {
  printf 'BASH_GOD Homebrew install smoke could not locate the Homebrew runtime.\n' >&2
  exit 2
}
test_brew="$fixture/bin/brew"
tap="$fixture/Library/Taps/hemang11/homebrew-bash-god"
formula="$tap/Formula/bash-god.rb"
assets="$fixture/assets"
fake_bin="$fixture/fake-bin"
mkdir -p "$fixture/bin" "$fixture/Library/Taps/homebrew" "$tap/Formula" "$assets" "$fake_bin" || exit 1
cp "$real_brew" "$test_brew"
ln -s "$real_library" "$fixture/Library/Homebrew"
ln -s "$real_core_tap" "$fixture/Library/Taps/homebrew/homebrew-core"
printf '%s\n' '#!/bin/sh' 'printf "aws-cli/2.36.1 Python/3 Darwin/arm64\n"' > "$fake_bin/aws"
printf '%s\n' '#!/bin/sh' 'printf "{\\"version\\":{\\"number\\":\\"8.15.0\\"}}\n"' > "$fake_bin/curl"
printf '%s\n' '#!/bin/sh' 'printf "Client Version: v1.36.1\n"' > "$fake_bin/kubectl"
printf '%s\n' '#!/bin/sh' 'printf "3.9.2\n"' > "$fake_bin/kafka-topics.sh"
printf '%s\n' '#!/bin/sh' 'printf "2.5.0\n"' > "$fake_bin/mongosh"
chmod 0755 "$fake_bin/aws"
chmod 0755 "$fake_bin/curl" "$fake_bin/kubectl" "$fake_bin/kafka-topics.sh" "$fake_bin/mongosh"
brew_env() {
  HOME="$fixture/brew-home" \
  PATH="$fake_bin:$PATH" \
  HOMEBREW_CACHE="$fixture/cache" \
  HOMEBREW_LOGS="$fixture/logs" \
  HOMEBREW_TEMP="$fixture/tmp" \
  HOMEBREW_NO_AUTO_UPDATE=1 \
  HOMEBREW_NO_INSTALL_FROM_API=1 \
  HOMEBREW_DEVELOPER=1 \
  "$test_brew" "$@"
}

if "$repo_dir/packaging/build-runtime.sh" "$assets" >/dev/null; then
  pass 'fixture builds the same target archive a Homebrew release will reference'
else
  fail 'fixture builds the same target archive a Homebrew release will reference'
  printf '\n1 of %d Homebrew install checks failed.\n' "$checks" >&2
  exit 1
fi

if "$renderer" \
  --version "$version" \
  --darwin-amd64 "$assets/bash-god-$version-darwin-amd64.tar.gz" \
  --darwin-arm64 "$assets/bash-god-$version-darwin-arm64.tar.gz" \
  --linux-amd64 "$assets/bash-god-$version-linux-amd64.tar.gz" \
  --linux-arm64 "$assets/bash-god-$version-linux-arm64.tar.gz" \
  --base-url "file://$assets" \
  --output "$formula"; then
  pass 'fixture Formula is rendered in a temporary tap path with local target archives'
else
  fail 'fixture Formula is rendered in a temporary tap path with local target archives'
fi

# Homebrew's post-install sandbox resolves the home base from the actual
# account, rather than the fixture's HOME override. Make only this disposable
# Formula verbose and assert the shared resync summary; the layout proof checks
# the narrow writable-state declaration carried by the real Formula.
sed -i '' 's/print_stdout: false, print_stderr: false/print_stdout: true, print_stderr: true/' "$formula"

trust_status=0
trust_output="$(brew_env trust --tap hemang11/homebrew-bash-god 2>&1)" || trust_status=$?
if [ "$trust_status" -eq 0 ]; then
  pass 'fixture trusts only its temporary Homebrew tap with the current Homebrew policy'
else
  fail 'fixture trusts only its temporary Homebrew tap with the current Homebrew policy'
  printf '%s\n' "$trust_output"
  exit 1
fi

install_status=0
install_output="$(brew_env install --formula "$formula" --build-from-source 2>&1)" || install_status=$?
installed_prefix="$(brew_env --prefix bash-god 2>/dev/null || :)"
owner_marker="$installed_prefix/libexec/share/bash-god/package-owner"
if [ "$install_status" -eq 0 ] && [ -x "$fixture/bin/god" ] && \
   [ "$(command cat "$owner_marker" 2>/dev/null)" = homebrew ] && \
   contains "$install_output" '5 of 5 detectable services refreshed.'; then
  pass 'Homebrew installs, links god, and invokes the all-service discovery sync'
else
  fail 'Homebrew installs, links god, and invokes the all-service discovery sync'
  printf '%s\n' "$install_output"
fi

owner_uninstall_status=0
owner_uninstall_output="$(HOME="$fixture/brew-home" GOD_COLOR=never "$fixture/bin/god" --uninstall 2>&1)" || owner_uninstall_status=$?
if [ "$owner_uninstall_status" -eq 2 ] && contains "$owner_uninstall_output" 'brew uninstall bash-god'; then
  pass 'the installed Homebrew runtime directs removal back to Homebrew'
else
  fail 'the installed Homebrew runtime directs removal back to Homebrew'
  printf '%s\n' "$owner_uninstall_output"
fi

version_output="$(HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_CACHE_HOME="$fixture/user-cache" XDG_STATE_HOME="$fixture/state" XDG_DATA_HOME="$fixture/data" BASH_GOD_SKIP_INITIAL_RESYNC=1 GOD_COLOR=never "$fixture/bin/god" --version 2>&1)"
if [ "$version_output" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$version")" ]; then
  pass 'the real Formula symlink resolves the Cellar-private runtime and helper'
else
  fail 'the real Formula symlink resolves the Cellar-private runtime and helper'
  printf '%s\n' "$version_output"
fi

quiet_output="$(HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_CACHE_HOME="$fixture/user-cache" XDG_STATE_HOME="$fixture/state" XDG_DATA_HOME="$fixture/data" BASH_GOD_SKIP_INITIAL_RESYNC=1 GOD_COLOR=never "$fixture/bin/god" general --quiet 2>&1)"
if printf '%s\n' "$quiet_output" | LC_ALL=C grep -F 'GENERAL COMMANDS' >/dev/null && \
   grep -F 'assert_match "BASH_GOD #{version}", shell_output("#{bin}/god --version")' "$formula" >/dev/null && \
   grep -F 'assert_match "GENERAL COMMANDS", shell_output("#{bin}/god general --quiet")' "$formula" >/dev/null; then
  pass 'the installed runtime and Formula test block cover version and harmless browsing'
else
  fail 'the installed runtime and Formula test block cover version and harmless browsing'
fi

uninstall_status=0
uninstall_output="$(brew_env uninstall --formula bash-god 2>&1)" || uninstall_status=$?
if [ "$uninstall_status" -eq 0 ] && [ ! -e "$fixture/bin/god" ] && \
   [ ! -e "$fixture/Cellar/bash-god" ]; then
  pass 'Homebrew uninstall removes the disposable package-owned runtime and link'
else
  fail 'Homebrew uninstall removes the disposable package-owned runtime and link'
  printf '%s\n' "$uninstall_output"
fi

if [ "$failures" -ne 0 ]; then
  printf '\n%d of %d Homebrew install checks failed.\n' "$failures" "$checks" >&2
  exit 1
fi

printf '\n%d Homebrew install checks passed.\n' "$checks"
