#!/usr/bin/env bash

# Fake-only verification for the multi-platform direct runtime. It builds
# archives locally but never starts a catalog command or contacts a service.

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$repo_dir/src/core.sh")"
protocol="$(LC_ALL=C awk -F= '
  /^_GOD_TUI_PROTOCOL_VERSION=/ { count++; value=$2; gsub(/[[:space:]]/, "", value) }
  END { if (count == 1 && value ~ /^[1-9][0-9]*$/) print value; else exit 1 }
' "$repo_dir/src/ui/tui.sh")" || exit 1
temporary="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-runtime-smoke.XXXXXX")" || exit 1
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

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
  case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  else
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  fi
}

asset_digests() {
  local directory asset

  directory=$1
  for asset in "$directory"/*; do
    [ -f "$asset" ] || continue
    printf '%s  %s\n' "$(sha256 "$asset")" "$(basename "$asset")"
  done | LC_ALL=C sort
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

# Frozen, fake-only pre-R08 installed shape. It mirrors the runtime ownership
# boundary produced before src/ and god-tui existed: a real launcher, the
# bash_god/ module set, catalog files, license, and exact install manifest.
# Keep it deliberately small, but do not reduce the historical layout to only
# core.sh; that would let the migration test bless a partial destination.
stage_pre_r08_install() {
  local fixture_prefix fixture_version runtime catalog prefix_physical module

  fixture_prefix=$1
  fixture_version=$2
  runtime="$fixture_prefix/lib/bash-god"
  catalog="$runtime/bash_god/catalog/legacy"
  mkdir -p "$fixture_prefix/bin" "$catalog" \
    "$fixture_prefix/share/licenses/bash-god" "$fixture_prefix/share/bash-god"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '# Real-file launcher installed at PREFIX/bin/god by the runtime package.' \
    'launcher_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || exit 1' \
    'exec "$launcher_dir/../lib/bash-god/god" "$@"' > "$fixture_prefix/bin/god"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    "  --version) printf 'BASH_GOD %s\\nLicense: MIT\\n' '$fixture_version' ;;" \
    '  *) exit 0 ;;' \
    'esac' > "$runtime/god"

  for module in art catalog discover execute maintenance menu render resolve search tree; do
    printf '# frozen pre-R08 %s module\n' "$module" > "$runtime/bash_god/$module.sh"
  done
  printf "_BASH_GOD_VERSION='%s'\n" "$fixture_version" > "$runtime/bash_god/core.sh"
  printf '@service legacy\n' > "$catalog/service.god"
  printf 'MIT fixture\n' > "$fixture_prefix/share/licenses/bash-god/LICENSE"
  prefix_physical="$(CDPATH= cd "$fixture_prefix" && pwd -P)"
  printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s\n' \
    "$prefix_physical" "$fixture_version" > "$fixture_prefix/share/bash-god/install-manifest"
  chmod 0755 "$fixture_prefix/bin/god" "$runtime/god"
}

host_platform="$(platform)" || {
  printf 'not ok 01 - test host is outside the supported archive matrix\n' >&2
  exit 1
}
targets='darwin-amd64 darwin-arm64 linux-amd64 linux-arm64'
assets="$temporary/assets"
prefix="$temporary/prefix"
compat_prefix="$temporary/compat-prefix"
fake_bin="$temporary/fake-bin"
fake_home="$temporary/home"
mkdir -p "$assets" "$fake_bin" "$fake_home"

# Ensure automatic post-install resync never reaches an actual local REST
# endpoint. The remaining discovery probes are absent from this test PATH.
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$fake_bin/curl"
chmod 0755 "$fake_bin/curl"
test_path="$fake_bin:/usr/bin:/bin"

# A cross-compilation failure occurs before any artifact publication. On the
# macOS Bash 3.2 shipped by default, expanding an empty array under nounset
# used to obscure that real compiler error during EXIT cleanup.
failed_assets="$temporary/failed-assets"
printf '%s\n' '#!/usr/bin/env bash' 'exit 97' > "$fake_bin/go"
chmod 0755 "$fake_bin/go"
failed_build_status=0
failed_build_output="$(PATH="$test_path" bash "$repo_dir/packaging/build-runtime.sh" "$failed_assets" 2>&1)" || failed_build_status=$?
command rm -f -- "$fake_bin/go"
if [ "$failed_build_status" -eq 1 ] && \
   contains "$failed_build_output" 'could not compile god-tui for darwin-amd64' && \
   ! contains "$failed_build_output" 'unbound variable' && \
   [ -z "$(command find "$failed_assets" -mindepth 1 -print -quit)" ]; then
  pass 'a pre-publication helper build failure preserves its compiler error under nounset'
else
  fail 'a pre-publication helper build failure preserves its compiler error under nounset'
  printf '%s\n' "$failed_build_output"
fi

if "$repo_dir/packaging/build-runtime.sh" "$assets" >/dev/null; then
  pass 'builder cross-compiles all supported helper artifacts'
else
  fail 'builder cross-compiles all supported helper artifacts'
  printf '\n1 of %d package checks failed.\n' "$checks" >&2
  exit 1
fi

expected_assets="bash-god-$version.tar.gz
bash-god-$version.tar.gz.sha256
install-runtime.sh
install-runtime.sh.sha256
install.sh
install.sh.sha256"
for target in $targets; do
  expected_assets="$expected_assets
bash-god-$version-$target.tar.gz
bash-god-$version-$target.tar.gz.sha256"
done
actual_assets="$(command find "$assets" -mindepth 1 -maxdepth 1 -type f -print | LC_ALL=C sed 's#.*/##' | LC_ALL=C sort)"
if [ "$actual_assets" = "$(printf '%b' "$expected_assets" | LC_ALL=C sort)" ]; then
  pass 'builder emits the four target archives, legacy bridge, installers, and checksums'
else
  fail 'builder emits the four target archives, legacy bridge, installers, and checksums'
  printf 'expected assets:\n%s\nactual assets:\n%s\n' "$(printf '%b' "$expected_assets" | LC_ALL=C sort)" "$actual_assets"
fi

reproducible_assets="$temporary/reproducible-assets"
if "$repo_dir/packaging/build-runtime.sh" "$reproducible_assets" >/dev/null && \
   [ "$(asset_digests "$assets")" = "$(asset_digests "$reproducible_assets")" ]; then
  pass 'two clean builds produce byte-identical release assets'
else
  fail 'two clean builds produce byte-identical release assets'
fi

checksums_ok=1
for archive in "$assets"/*.tar.gz; do
  checksum="$archive.sha256"
  expected="$(LC_ALL=C awk -v file="$(basename "$archive")" '$2 == file { print $1; exit }' "$checksum")"
  [ "$expected" = "$(sha256 "$archive")" ] || checksums_ok=0
done
for asset in install-runtime.sh install.sh; do
  expected="$(LC_ALL=C awk -v file="$asset" '$2 == file { print $1; exit }' "$assets/$asset.sha256")"
  [ "$expected" = "$(sha256 "$assets/$asset")" ] || checksums_ok=0
done
if [ "$checksums_ok" -eq 1 ]; then
  pass 'every release asset has an exact SHA-256 sidecar'
else
  fail 'every release asset has an exact SHA-256 sidecar'
fi

bridge="bash-god-$version"
bridge_archive="$assets/$bridge.tar.gz"
bridge_listing="$(tar -tzf "$bridge_archive")"
bridge_helpers_ok=1
for target in $targets; do
  contains "$bridge_listing" "$bridge/libexec/bash-god/$target/god-tui" || bridge_helpers_ok=0
done
bridge_manifest="$(tar -xOf "$bridge_archive" "$bridge/lib/bash-god/tui-manifest")"
if [ "$bridge_helpers_ok" -eq 1 ] && \
   [ "$bridge_manifest" = "$(printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=multi\nprotocol=%s' "$version" "$protocol")" ]; then
  pass 'legacy compatibility archive explicitly bundles all four helpers'
else
  fail 'legacy compatibility archive explicitly bundles all four helpers'
fi

target_archives_ok=1
for target in $targets; do
  package="bash-god-$version-$target"
  archive="$assets/$package.tar.gz"
  listing="$(tar -tzf "$archive")"
  manifest="$(tar -xOf "$archive" "$package/lib/bash-god/tui-manifest")"
  contains "$listing" "$package/libexec/bash-god/god-tui" || target_archives_ok=0
  contains "$listing" "$package/libexec/bash-god/darwin-amd64/god-tui" && target_archives_ok=0
  [ "$manifest" = "$(printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=%s\nprotocol=%s' "$version" "$target" "$protocol")" ] || target_archives_ok=0
  if ! LC_ALL=C tar -tvzf "$archive" | LC_ALL=C awk -v path="$package/libexec/bash-god/god-tui" '$NF == path && $1 ~ /^-rwx/ { found = 1 } END { exit !found }'; then
    target_archives_ok=0
  fi
done
if [ "$target_archives_ok" -eq 1 ]; then
  pass 'each target archive has one executable helper and a matching manifest'
else
  fail 'each target archive has one executable helper and a matching manifest'
fi

installer="$assets/install-runtime.sh"
installer_checksum="$assets/install-runtime.sh.sha256"
bootstrap="$assets/install.sh"
if [ -x "$installer" ] && [ -x "$bootstrap" ] && \
   cmp -s "$installer" "$repo_dir/packaging/install-runtime.sh" && \
   cmp -s "$bootstrap" "$repo_dir/packaging/install.sh" && \
   [ "$(LC_ALL=C awk '$2 == "install-runtime.sh" { print $1; exit }' "$installer_checksum")" = "$(sha256 "$installer")" ]; then
  pass 'installer and bootstrap assets are executable and checksum-verifiable'
else
  fail 'installer and bootstrap assets are executable and checksum-verifiable'
fi

host_archive="$assets/bash-god-$version-$host_platform.tar.gz"
host_checksum="$host_archive.sha256"
install_status=0
HOME="$fake_home" XDG_CONFIG_HOME="$temporary/config" XDG_CACHE_HOME="$temporary/cache" \
XDG_STATE_HOME="$temporary/state" XDG_DATA_HOME="$temporary/data" PATH="$test_path" \
BASH_GOD_SKIP_INITIAL_RESYNC=1 \
bash "$installer" --prefix "$prefix" "$host_archive" "$host_checksum" >/dev/null 2>&1 || install_status=$?
if [ "$install_status" -eq 0 ] && [ -x "$prefix/bin/god" ] && \
   [ -x "$prefix/libexec/bash-god/god-tui" ] && \
   [ "$(GOD_COLOR=never "$prefix/bin/god" --version)" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$version")" ] && \
   [ "$("$prefix/libexec/bash-god/god-tui" --protocol-version)" = "$protocol" ]; then
  pass 'offline staged install activates the host helper without Go on PATH'
else
  fail 'offline staged install activates the host helper without Go on PATH'
fi

installed_manifest="$(command cat "$prefix/lib/bash-god/tui-manifest")"
expected_manifest="$(printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=%s\nprotocol=%s' "$version" "$host_platform" "$protocol")"
if [ "$installed_manifest" = "$expected_manifest" ] && \
   [ -r "$prefix/share/licenses/bash-god/THIRD_PARTY_NOTICES.md" ]; then
  pass 'installed runtime records the selected helper target and bundled notices'
else
  fail 'installed runtime records the selected helper target and bundled notices'
fi

helper_lookup="$(TERM=xterm-256color PATH="$test_path" bash -c '
  . "$1/lib/bash-god/src/core.sh"
  _god_tui_find_helper
' _ "$prefix")"
prefix_physical="$(CDPATH= cd "$prefix" && pwd -P)"
if [ "$helper_lookup" = "$prefix_physical/libexec/bash-god/god-tui" ]; then
  pass 'installed runtime resolves its private helper through the manifest contract'
else
  fail 'installed runtime resolves its private helper through the manifest contract'
fi

symlink_bin="$temporary/symlink-bin"
mkdir -p "$symlink_bin"
ln -s "$prefix/bin/god" "$symlink_bin/god"
if [ "$(GOD_COLOR=never "$symlink_bin/god" --version)" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$version")" ]; then
  pass 'a symlinked launcher still finds the installed runtime and helper prefix'
else
  fail 'a symlinked launcher still finds the installed runtime and helper prefix'
fi

compat_status=0
HOME="$fake_home" XDG_CONFIG_HOME="$temporary/compat-config" XDG_CACHE_HOME="$temporary/compat-cache" \
XDG_STATE_HOME="$temporary/compat-state" XDG_DATA_HOME="$temporary/compat-data" PATH="$test_path" \
BASH_GOD_SKIP_INITIAL_RESYNC=1 \
bash "$installer" --prefix "$compat_prefix" "$bridge_archive" "$bridge_archive.sha256" >/dev/null 2>&1 || compat_status=$?
if [ "$compat_status" -eq 0 ] && [ -x "$compat_prefix/libexec/bash-god/god-tui" ] && \
   [ "$(command cat "$compat_prefix/lib/bash-god/tui-manifest")" = "$expected_manifest" ]; then
  pass 'legacy unsuffixed bridge selects one verified local helper during offline install'
else
  fail 'legacy unsuffixed bridge selects one verified local helper during offline install'
fi

# This is the actual R08 migration boundary, not another empty-prefix bridge
# install. Pre-R08 maintenance invokes the new installer with --replace and
# the unsuffixed archive, so stage the frozen old managed layout first.
legacy_prefix="$temporary/pre-r08-prefix"
legacy_version='0.0.1.0'
stage_pre_r08_install "$legacy_prefix" "$legacy_version"
legacy_upgrade_status=0
HOME="$fake_home" XDG_CONFIG_HOME="$temporary/legacy-config" XDG_CACHE_HOME="$temporary/legacy-cache" \
XDG_STATE_HOME="$temporary/legacy-state" XDG_DATA_HOME="$temporary/legacy-data" PATH="$test_path" \
BASH_GOD_SKIP_INITIAL_RESYNC=1 \
bash "$installer" --replace --prefix "$legacy_prefix" "$bridge_archive" "$bridge_archive.sha256" >/dev/null 2>&1 || legacy_upgrade_status=$?
legacy_backup="$(command find "$legacy_prefix/lib" -maxdepth 1 -type d -name "bash-god.backup-$legacy_version.*" -print | LC_ALL=C awk 'NR == 1 { print; exit }')"
legacy_manifest="$(command cat "$legacy_prefix/share/bash-god/install-manifest" 2>/dev/null)"
legacy_expected_manifest="$(printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s' \
  "$(CDPATH= cd "$legacy_prefix" && pwd -P)" "$version")"
if [ "$legacy_upgrade_status" -eq 0 ] && \
   [ -x "$legacy_prefix/bin/god" ] && \
   [ -x "$legacy_prefix/lib/bash-god/god" ] && \
   [ -r "$legacy_prefix/lib/bash-god/src/core.sh" ] && \
   [ ! -e "$legacy_prefix/lib/bash-god/bash_god" ] && \
   [ -x "$legacy_prefix/libexec/bash-god/god-tui" ] && \
   [ "$("$legacy_prefix/libexec/bash-god/god-tui" --protocol-version)" = "$protocol" ] && \
   [ "$(GOD_COLOR=never "$legacy_prefix/bin/god" --version)" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$version")" ] && \
   [ "$(command cat "$legacy_prefix/lib/bash-god/tui-manifest")" = "$expected_manifest" ] && \
   [ "$legacy_manifest" = "$legacy_expected_manifest" ] && \
   [ -r "$legacy_backup/runtime/bash_god/core.sh" ] && \
   [ ! -e "$legacy_backup/helper" ]; then
  pass 'a staged pre-R08 managed runtime upgrades through the verified unsuffixed bridge'
else
  fail 'a staged pre-R08 managed runtime upgrades through the verified unsuffixed bridge'
fi

partial_legacy_prefix="$temporary/partial-pre-r08-prefix"
stage_pre_r08_install "$partial_legacy_prefix" "$legacy_version"
command rm -f -- "$partial_legacy_prefix/lib/bash-god/bash_god/menu.sh"
partial_legacy_status=0
partial_legacy_output="$(BASH_GOD_SKIP_INITIAL_RESYNC=1 PATH="$test_path" \
  bash "$installer" --replace --prefix "$partial_legacy_prefix" "$bridge_archive" "$bridge_archive.sha256" 2>&1)" || partial_legacy_status=$?
if [ "$partial_legacy_status" -eq 1 ] && \
   contains "$partial_legacy_output" 'refusing to replace an unmanaged runtime' && \
   [ -x "$partial_legacy_prefix/lib/bash-god/god" ] && \
   [ ! -e "$partial_legacy_prefix/libexec/bash-god" ]; then
  pass 'a partial pre-R08-shaped destination is not mistaken for a managed runtime'
else
  fail 'a partial pre-R08-shaped destination is not mistaken for a managed runtime'
fi

linked_legacy_prefix="$temporary/linked-pre-r08-prefix"
stage_pre_r08_install "$linked_legacy_prefix" "$legacy_version"
mv "$linked_legacy_prefix/lib/bash-god/bash_god/core.sh" "$temporary/linked-core.sh"
ln -s "$temporary/linked-core.sh" "$linked_legacy_prefix/lib/bash-god/bash_god/core.sh"
linked_legacy_status=0
linked_legacy_output="$(BASH_GOD_SKIP_INITIAL_RESYNC=1 PATH="$test_path" \
  bash "$installer" --replace --prefix "$linked_legacy_prefix" "$bridge_archive" "$bridge_archive.sha256" 2>&1)" || linked_legacy_status=$?
if [ "$linked_legacy_status" -eq 1 ] && \
   contains "$linked_legacy_output" 'refusing to replace an unmanaged runtime' && \
   [ -L "$linked_legacy_prefix/lib/bash-god/bash_god/core.sh" ] && \
   [ ! -e "$linked_legacy_prefix/libexec/bash-god" ]; then
  pass 'a symlinked pre-R08 core remains refused before activation'
else
  fail 'a symlinked pre-R08 core remains refused before activation'
fi

mismatch_target=darwin-amd64
[ "$mismatch_target" != "$host_platform" ] || mismatch_target=linux-amd64
mismatch_archive="$assets/bash-god-$version-$mismatch_target.tar.gz"
mismatch_prefix="$temporary/mismatch-prefix"
mismatch_status=0
mismatch_output="$(PATH="$test_path" bash "$installer" --prefix "$mismatch_prefix" "$mismatch_archive" "$mismatch_archive.sha256" 2>&1)" || mismatch_status=$?
if [ "${mismatch_status:-0}" -eq 1 ] && contains "$mismatch_output" 'no architecture was guessed' && [ ! -e "$mismatch_prefix" ]; then
  pass 'foreign target archives fail before extraction or activation'
else
  fail 'foreign target archives fail before extraction or activation'
fi

printf '%s\n' '#!/usr/bin/env bash' 'case "$1" in -s) printf "Plan9\\n" ;; -m) printf "mips64\\n" ;; *) exit 1 ;; esac' > "$fake_bin/uname"
chmod 0755 "$fake_bin/uname"
unknown_prefix="$temporary/unknown-prefix"
unknown_status=0
unknown_output="$(PATH="$test_path" bash "$installer" --prefix "$unknown_prefix" "$host_archive" "$host_checksum" 2>&1)" || unknown_status=$?
command rm -f -- "$fake_bin/uname"
if [ "${unknown_status:-0}" -eq 1 ] && contains "$unknown_output" 'unsupported host platform' && [ ! -e "$unknown_prefix" ]; then
  pass 'unknown uname values fail clearly instead of selecting a nearby helper'
else
  fail 'unknown uname values fail clearly instead of selecting a nearby helper'
fi

bad_checksum="$temporary/bad.sha256"
printf '%064d  %s\n' 0 "$(basename "$host_archive")" > "$bad_checksum"
bad_prefix="$temporary/bad-prefix"
bad_status=0
bash "$installer" --prefix "$bad_prefix" "$host_archive" "$bad_checksum" >/dev/null 2>&1 || bad_status=$?
if [ "$bad_status" -eq 1 ] && [ ! -e "$bad_prefix" ]; then
  pass 'checksum failure prevents a native helper install'
else
  fail 'checksum failure prevents a native helper install'
fi

unexpected_work="$temporary/unexpected-work"
unexpected_archive="$temporary/bash-god-$version-$host_platform-unexpected.tar.gz"
unexpected_checksum="$unexpected_archive.sha256"
mkdir -p "$unexpected_work"
tar -xzf "$host_archive" -C "$unexpected_work"
printf 'not part of the runtime\n' > "$unexpected_work/bash-god-$version-$host_platform/unexpected.txt"
tar -czf "$unexpected_archive" -C "$unexpected_work" "bash-god-$version-$host_platform"
printf '%s  %s\n' "$(sha256 "$unexpected_archive")" "$(basename "$unexpected_archive")" > "$unexpected_checksum"
unexpected_prefix="$temporary/unexpected-prefix"
unexpected_status=0
bash "$installer" --prefix "$unexpected_prefix" "$unexpected_archive" "$unexpected_checksum" >/dev/null 2>&1 || unexpected_status=$?
if [ "$unexpected_status" -eq 1 ] && [ ! -e "$unexpected_prefix" ]; then
  pass 'unexpected archive entries are rejected before helper activation'
else
  fail 'unexpected archive entries are rejected before helper activation'
fi

reinstall_status=0
BASH_GOD_SKIP_INITIAL_RESYNC=1 bash "$installer" --prefix "$prefix" "$host_archive" "$host_checksum" >/dev/null 2>&1 || reinstall_status=$?
replace_status=0
BASH_GOD_SKIP_INITIAL_RESYNC=1 bash "$installer" --replace --prefix "$prefix" "$host_archive" "$host_checksum" >/dev/null 2>&1 || replace_status=$?
backup="$(command find "$prefix/lib" -maxdepth 1 -type d -name 'bash-god.backup-*' -print | LC_ALL=C awk 'NR == 1 { print; exit }')"
if [ "$reinstall_status" -eq 1 ] && [ "$replace_status" -eq 0 ] && [ -x "$backup/runtime/god" ] && \
   [ -x "$backup/helper/god-tui" ] && [ -x "$prefix/libexec/bash-god/god-tui" ]; then
  pass 'explicit replacement retains the paired prior runtime and helper'
else
  fail 'explicit replacement retains the paired prior runtime and helper'
fi

# A deliberate --replace preserves the previous runtime below lib/ for
# rollback.  Assert the active footprint here; the paired backup itself is
# verified immediately above and the no-Go-source assertion still spans it.
installed_files="$(CDPATH= cd "$prefix" && command find . -path './lib/bash-god.backup-*' -prune -o -type f -print | LC_ALL=C sed 's#^\./##' | LC_ALL=C sort)"
expected_files='bin/god
lib/bash-god/catalog/aws/service.god
lib/bash-god/catalog/elasticsearch/service.god
lib/bash-god/catalog/general/service.god
lib/bash-god/catalog/k8s/service.god
lib/bash-god/catalog/kafka/service.god
lib/bash-god/catalog/mongo/service.god
lib/bash-god/catalog/network/service.god
lib/bash-god/god
lib/bash-god/src/catalog.sh
lib/bash-god/src/core.sh
lib/bash-god/src/discover.sh
lib/bash-god/src/eligibility.sh
lib/bash-god/src/execute.sh
lib/bash-god/src/interaction.sh
lib/bash-god/src/maintenance.sh
lib/bash-god/src/resolve.sh
lib/bash-god/src/search.sh
lib/bash-god/src/ui/art.sh
lib/bash-god/src/ui/input.sh
lib/bash-god/src/ui/menu.sh
lib/bash-god/src/ui/render.sh
lib/bash-god/src/ui/tree.sh
lib/bash-god/src/ui/tui.sh
lib/bash-god/tui-manifest
libexec/bash-god/god-tui
share/bash-god/install-manifest
share/licenses/bash-god/LICENSE
share/licenses/bash-god/THIRD_PARTY_NOTICES.md'
if [ "$installed_files" = "$expected_files" ] && \
   [ -z "$(command find "$prefix" \( -name '*.go' -o -name go.mod -o -name go.sum \) -print)" ]; then
  pass 'active installed runtime has the exact shell, native helper, and notice allowlist without Go sources'
else
  fail 'active installed runtime has the exact shell, native helper, and notice allowlist without Go sources'
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d package checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d package checks failed.\n' "$failures" "$checks" >&2
exit 1
