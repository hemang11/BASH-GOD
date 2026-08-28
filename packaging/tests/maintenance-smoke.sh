#!/usr/bin/env bash

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
maintenance="$repo_dir/bash_god/maintenance.sh"
version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$repo_dir/bash_god/core.sh")"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-maintenance-smoke.XXXXXX")" || exit 1
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

compare_output="$(bash -c '
  . "$1"
  printf "%s %s %s %s\n" \
    "$(_god_maintenance_compare_versions 0.0.1.2 0.0.1.3)" \
    "$(_god_maintenance_compare_versions 0.0.1.3 0.0.1.3)" \
    "$(_god_maintenance_compare_versions 1.10 1.9)" \
    "$(_god_maintenance_compare_versions 01.002 1.2)"
' _ "$maintenance")"
if [ "$compare_output" = '-1 0 1 0' ]; then
  pass 'numeric release comparison handles unequal component widths'
else
  fail 'numeric release comparison handles unequal component widths'
fi

source_options="$(bash -c '
  set +o nounset
  set +o pipefail
  . "$1"
  case "$-" in *u*) nounset=on ;; *) nounset=off ;; esac
  pipefail_state="$(set -o | while read -r name state; do
    [ "$name" = pipefail ] && printf "%s" "$state"
  done)"
  printf "%s %s\n" "$nounset" "$pipefail_state"
' _ "$maintenance")"
if [ "$source_options" = 'off off' ]; then
  pass 'loading maintenance helpers does not modify caller shell options'
else
  fail 'loading maintenance helpers does not modify caller shell options'
fi

offline_output="$(bash -c '
  . "$1"
  _god_maintenance_is_managed() { return 0; }
  _god_maintenance_cache_is_fresh() { return 1; }
  _god_maintenance_fetch_latest_version() { return 1; }
  _god_maintenance_defer_check() { :; }
  _god_maintenance_check "$2"
' _ "$maintenance" "$version")"
if [ -z "$offline_output" ]; then
  pass 'offline update checks fail silently'
else
  fail 'offline update checks fail silently'
fi

newer_version="${version%.*}.$(( ${version##*.} + 1 ))"

update_output="$(bash -c '
  . "$1"
  fixture_latest="$3"
  _god_maintenance_is_managed() { return 0; }
  _god_maintenance_cache_is_fresh() { return 1; }
  _god_maintenance_fetch_latest_version() { printf "%s\n" "$fixture_latest"; }
  _god_maintenance_defer_check() { :; }
  _god_maintenance_menu() { _god_maintenance_menu_choice=0; }
  _god_maintenance_install_update() { printf "installed:%s\n" "$1"; }
  status=0
  _god_maintenance_check "$2" || status=$?
  printf "status:%s\n" "$status"
' _ "$maintenance" "$version" "$newer_version")"
if contains "$update_output" "BASH_GOD $newer_version is available; you have $version." && \
   contains "$update_output" 'UPDATE AVAILABLE' && \
   contains "$update_output" "installed:$newer_version" && \
   contains "$update_output" 'status:10'; then
  pass 'accepted update installs only the newer release and asks for a fresh invocation'
else
  fail 'accepted update installs only the newer release and asks for a fresh invocation'
fi

cached_output="$(bash -c '
  . "$1"
  _god_maintenance_is_managed() { return 0; }
  _god_maintenance_cache_is_fresh() { return 0; }
  _god_maintenance_fetch_latest_version() { printf "unexpected\n"; }
  _god_maintenance_check "$2"
' _ "$maintenance" "$version")"
if [ -z "$cached_output" ]; then
  pass 'fresh update cache avoids a GitHub request'
else
  fail 'fresh update cache avoids a GitHub request'
fi

assets="$temporary/assets"
prefix="$temporary/prefix"
test_home="$temporary/home"
mkdir -p "$assets" "$test_home"
"$repo_dir/packaging/build-runtime.sh" "$assets" >/dev/null || exit 1
"$repo_dir/packaging/install-runtime.sh" --prefix "$prefix" \
  "$assets/bash-god-$version.tar.gz" "$assets/bash-god-$version.tar.gz.sha256" >/dev/null || exit 1

mkdir -p \
  "$test_home/.config/bash-god" \
  "$test_home/.cache/bash-god" \
  "$test_home/.local/state/bash-god" \
  "$test_home/.local/share/bash-god" \
  "$prefix/lib/bash-god.backup-$version.fixture/runtime" \
  "$prefix/share/keep" \
  "$test_home/.config/keep"
printf 'owned\n' > "$test_home/.config/bash-god/config"
printf 'owned\n' > "$test_home/.cache/bash-god/cache"
printf 'owned\n' > "$test_home/.local/state/bash-god/state"
printf 'owned\n' > "$test_home/.local/share/bash-god/data"
printf 'owned\n' > "$prefix/lib/bash-god.backup-$version.fixture/runtime/old"
printf 'keep\n' > "$prefix/share/keep/value"
printf 'keep\n' > "$test_home/.config/keep/value"

printf 'unexpected=metadata\n' >> "$prefix/share/bash-god/install-manifest"
altered_status=0
HOME="$test_home" bash "$prefix/lib/bash-god/bash_god/maintenance.sh" uninstall "$version" >/dev/null 2>&1 || altered_status=$?
if [ "$altered_status" -eq 2 ] && [ -x "$prefix/bin/god" ]; then
  pass 'uninstall refuses an inexact ownership manifest'
else
  fail 'uninstall refuses an inexact ownership manifest'
fi
printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s\n' \
  "$(CDPATH= cd "$prefix" && pwd -P)" "$version" > "$prefix/share/bash-god/install-manifest"

cancel_output="$(HOME="$test_home" bash -c '
  . "$1"
  _god_maintenance_menu() { _god_maintenance_menu_choice=0; }
  _god_maintenance_main uninstall "$2"
' _ "$prefix/lib/bash-god/bash_god/maintenance.sh" "$version")"
if contains "$cancel_output" 'Uninstall cancelled. Nothing was changed.' && \
   contains "$cancel_output" "REMOVE BASH_GOD $version" && \
   contains "$cancel_output" 'PATHS TO REMOVE' && \
   [ -x "$prefix/bin/god" ] && [ -d "$test_home/.config/bash-god" ]; then
  pass 'uninstall defaults to cancellation without changing files'
else
  fail 'uninstall defaults to cancellation without changing files'
fi

purge_output="$(HOME="$test_home" bash -c '
  . "$1"
  _god_maintenance_menu() { _god_maintenance_menu_choice=1; }
  _god_maintenance_main uninstall "$2"
' _ "$prefix/lib/bash-god/bash_god/maintenance.sh" "$version")"
if contains "$purge_output" 'BASH_GOD was completely removed.' && \
   [ ! -e "$prefix/bin/god" ] && \
   [ ! -e "$prefix/lib/bash-god" ] && \
   [ -z "$(command find "$prefix/lib" -maxdepth 1 -name 'bash-god.backup-*' -print 2>/dev/null)" ] && \
   [ ! -e "$prefix/share/licenses/bash-god" ] && \
   [ ! -e "$prefix/share/bash-god" ] && \
   [ ! -e "$test_home/.config/bash-god" ] && \
   [ ! -e "$test_home/.cache/bash-god" ] && \
   [ ! -e "$test_home/.local/state/bash-god" ] && \
   [ ! -e "$test_home/.local/share/bash-god" ] && \
   [ -f "$prefix/share/keep/value" ] && \
   [ -f "$test_home/.config/keep/value" ]; then
  pass 'god --uninstall purges every owned path and preserves unrelated data'
else
  fail 'god --uninstall purges every owned path and preserves unrelated data'
fi

unmanaged_status=0
unmanaged_output="$(GOD_COLOR=never "$repo_dir/god" --uninstall 2>&1)" || unmanaged_status=$?
if [ "$unmanaged_status" -eq 2 ] && contains "$unmanaged_output" 'not a managed GitHub Release installation'; then
  pass 'source checkouts refuse managed-install removal'
else
  fail 'source checkouts refuse managed-install removal'
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d maintenance checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d maintenance checks failed.\n' "$failures" "$checks" >&2
exit 1
