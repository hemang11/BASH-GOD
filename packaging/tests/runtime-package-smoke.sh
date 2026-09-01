#!/usr/bin/env bash

set -o nounset
set -o pipefail

_bash_god_package_test_file="${BASH_SOURCE[0]}"
_bash_god_package_test_dir="$(CDPATH= cd "$(dirname "$_bash_god_package_test_file")" 2>/dev/null && pwd -P)" || exit 1
_bash_god_package_root="$(CDPATH= cd "$_bash_god_package_test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
_bash_god_expected_version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$_bash_god_package_root/bash_god/core.sh")"
_bash_god_package_name="bash-god-$_bash_god_expected_version"
_bash_god_mismatch_version="${_bash_god_expected_version}0"
_bash_god_mismatch_name="bash-god-$_bash_god_mismatch_version"
_bash_god_package_temp="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-runtime-smoke.XXXXXX")" || exit 1
trap 'rm -rf -- "$_bash_god_package_temp"' EXIT HUP INT TERM

_bash_god_package_checks=0
_bash_god_package_failures=0

_bash_god_package_pass() {
  _bash_god_package_checks=$((_bash_god_package_checks + 1))
  printf 'ok %02d - %s\n' "$_bash_god_package_checks" "$1"
}

_bash_god_package_fail() {
  _bash_god_package_checks=$((_bash_god_package_checks + 1))
  _bash_god_package_failures=$((_bash_god_package_failures + 1))
  printf 'not ok %02d - %s\n' "$_bash_god_package_checks" "$1"
}

_bash_god_package_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

_bash_god_package_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  else
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  fi
}

_bash_god_package_write_checksum() {
  local _bash_god_checksum_archive _bash_god_checksum_output

  _bash_god_checksum_archive="$1"
  _bash_god_checksum_output="$2"
  printf '%s  %s\n' "$(_bash_god_package_sha256 "$_bash_god_checksum_archive")" "$(basename "$_bash_god_checksum_archive")" > "$_bash_god_checksum_output"
}

_bash_god_package_output="$_bash_god_package_temp/output"
_bash_god_package_prefix="$_bash_god_package_temp/prefix"
mkdir -p "$_bash_god_package_output"

if "$_bash_god_package_root/packaging/build-runtime.sh" "$_bash_god_package_output" >/dev/null; then
  _bash_god_package_pass 'runtime archive builds'
else
  _bash_god_package_fail 'runtime archive builds'
fi

_bash_god_dangling_output="$_bash_god_package_temp/dangling-output"
_bash_god_dangling_target="$_bash_god_package_temp/dangling-target"
mkdir -p "$_bash_god_dangling_output"
ln -s "$_bash_god_dangling_target" "$_bash_god_dangling_output/$_bash_god_package_name.tar.gz"
_bash_god_dangling_status=0
"$_bash_god_package_root/packaging/build-runtime.sh" "$_bash_god_dangling_output" >/dev/null 2>&1 || _bash_god_dangling_status=$?
if [ "$_bash_god_dangling_status" -eq 1 ] && [ -L "$_bash_god_dangling_output/$_bash_god_package_name.tar.gz" ] && [ ! -e "$_bash_god_dangling_target" ]; then
  _bash_god_package_pass 'builder refuses dangling output symlinks without touching their target'
else
  _bash_god_package_fail 'builder refuses dangling output symlinks without touching their target'
fi

_bash_god_package_archive="$_bash_god_package_output/$_bash_god_package_name.tar.gz"
_bash_god_package_checksum="$_bash_god_package_archive.sha256"
_bash_god_package_installer="$_bash_god_package_output/install-runtime.sh"
_bash_god_package_installer_checksum="$_bash_god_package_installer.sha256"
_bash_god_package_installer_hash="$(_bash_god_package_sha256 "$_bash_god_package_installer")"
_bash_god_package_installer_help="$("$_bash_god_package_installer" --help)"
if [ -x "$_bash_god_package_installer" ] && [ ! -L "$_bash_god_package_installer" ] && \
   cmp -s "$_bash_god_package_installer" "$_bash_god_package_root/packaging/install-runtime.sh" && \
   [ "$(command cat "$_bash_god_package_installer_checksum")" = "$_bash_god_package_installer_hash  install-runtime.sh" ] && \
   _bash_god_package_contains "$_bash_god_package_installer_help" 'Upgrade or reinstall a managed runtime'; then
  _bash_god_package_pass 'builder emits a checksum-verifiable installer asset'
else
  _bash_god_package_fail 'builder emits a checksum-verifiable installer asset'
fi

_bash_god_package_bootstrap="$_bash_god_package_output/install.sh"
_bash_god_package_bootstrap_checksum="$_bash_god_package_bootstrap.sha256"
_bash_god_package_bootstrap_hash="$(_bash_god_package_sha256 "$_bash_god_package_bootstrap")"
_bash_god_package_bootstrap_help="$("$_bash_god_package_bootstrap" --help)"
if [ -x "$_bash_god_package_bootstrap" ] && [ ! -L "$_bash_god_package_bootstrap" ] && \
   cmp -s "$_bash_god_package_bootstrap" "$_bash_god_package_root/packaging/install.sh" && \
   [ "$(command cat "$_bash_god_package_bootstrap_checksum")" = "$_bash_god_package_bootstrap_hash  install.sh" ] && \
   _bash_god_package_contains "$_bash_god_package_bootstrap_help" 'Installs the latest BASH_GOD GitHub Release' && \
   _bash_god_package_contains "$_bash_god_package_bootstrap_help" 'god --uninstall'; then
  _bash_god_package_pass 'builder emits a checksum-verifiable public install asset'
else
  _bash_god_package_fail 'builder emits a checksum-verifiable public install asset'
fi

_bash_god_package_listing="$(tar -tzf "$_bash_god_package_archive" 2>/dev/null)"
if [ -f "$_bash_god_package_archive" ] && [ -f "$_bash_god_package_checksum" ] && \
   ! _bash_god_package_contains "$_bash_god_package_listing" 'BASH_GOD.sh' && \
   ! _bash_god_package_contains "$_bash_god_package_listing" 'README' && \
   ! _bash_god_package_contains "$_bash_god_package_listing" 'AGENTS.md' && \
   ! _bash_god_package_contains "$_bash_god_package_listing" '/tests/' && \
   ! _bash_god_package_contains "$_bash_god_package_listing" '/.git/'; then
  _bash_god_package_pass 'archive excludes source loaders and development files'
else
  _bash_god_package_fail 'archive excludes source loaders and development files'
fi

if "$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_package_prefix" "$_bash_god_package_archive" "$_bash_god_package_checksum" >/dev/null; then
  _bash_god_package_pass 'checksum-verified install succeeds under an isolated prefix'
else
  _bash_god_package_fail 'checksum-verified install succeeds under an isolated prefix'
fi

_bash_god_package_actual_files="$(CDPATH= cd "$_bash_god_package_prefix" && command find . -type f -print | LC_ALL=C sed 's#^\./##' | LC_ALL=C sort)"
_bash_god_package_expected_files='bin/god
lib/bash-god/bash_god/art.sh
lib/bash-god/bash_god/catalog.sh
lib/bash-god/bash_god/catalog/aws/service.god
lib/bash-god/bash_god/catalog/elasticsearch/service.god
lib/bash-god/bash_god/catalog/general/service.god
lib/bash-god/bash_god/catalog/k8s/service.god
lib/bash-god/bash_god/catalog/kafka/service.god
lib/bash-god/bash_god/catalog/mongo/service.god
lib/bash-god/bash_god/catalog/network/service.god
lib/bash-god/bash_god/core.sh
lib/bash-god/bash_god/discover.sh
lib/bash-god/bash_god/execute.sh
lib/bash-god/bash_god/maintenance.sh
lib/bash-god/bash_god/menu.sh
lib/bash-god/bash_god/render.sh
lib/bash-god/bash_god/resolve.sh
lib/bash-god/bash_god/search.sh
lib/bash-god/bash_god/tree.sh
lib/bash-god/god
share/bash-god/install-manifest
share/licenses/bash-god/LICENSE'
if [ "$_bash_god_package_actual_files" = "$_bash_god_package_expected_files" ] && \
   [ -x "$_bash_god_package_prefix/bin/god" ] && \
   [ ! -L "$_bash_god_package_prefix/bin/god" ] && \
   [ -x "$_bash_god_package_prefix/lib/bash-god/god" ]; then
  _bash_god_package_pass 'installed runtime matches the 22-file allowlist'
else
  _bash_god_package_fail 'installed runtime matches the 22-file allowlist'
fi

_bash_god_package_manifest="$(command cat "$_bash_god_package_prefix/share/bash-god/install-manifest")"
_bash_god_package_prefix_physical="$(CDPATH= cd "$_bash_god_package_prefix" && pwd -P)"
_bash_god_package_expected_manifest="$(printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s' "$_bash_god_package_prefix_physical" "$_bash_god_expected_version")"
if [ "$_bash_god_package_manifest" = "$_bash_god_package_expected_manifest" ]; then
  _bash_god_package_pass 'installer records exact GitHub-managed ownership metadata'
else
  _bash_god_package_fail 'installer records exact GitHub-managed ownership metadata'
fi

if ! LC_ALL=C grep -R -E 'AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN)[[:space:]]*=|ghp_|github_pat_|hvs\.' "$_bash_god_package_prefix" >/dev/null 2>&1; then
  _bash_god_package_pass 'runtime package contains no recognized credential material'
else
  _bash_god_package_fail 'runtime package contains no recognized credential material'
fi

_bash_god_package_cli="$_bash_god_package_prefix/bin/god"
_bash_god_package_version_output="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" --version 2>&1)"
if [ "$_bash_god_package_version_output" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$_bash_god_expected_version")" ]; then
  _bash_god_package_pass 'packaged launcher works from an empty environment'
else
  _bash_god_package_fail 'packaged launcher works from an empty environment'
fi

_bash_god_package_home="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" 2>&1)"
_bash_god_package_help="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" help 2>&1)"
_bash_god_package_quiet="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" --quiet 2>&1)"
_bash_god_package_escape="$(printf '\033')"
if [ "$_bash_god_package_home" = "$_bash_god_package_help" ] && \
   [ "$_bash_god_package_home" = "$_bash_god_package_quiet" ] && \
   _bash_god_package_contains "$_bash_god_package_home" 'god aws' && \
   _bash_god_package_contains "$_bash_god_package_home" 'god kafka' && \
   ! _bash_god_package_contains "$_bash_god_package_home" '██████╗' && \
   ! _bash_god_package_contains "$_bash_god_package_home" "$_bash_god_package_escape"; then
  _bash_god_package_pass 'non-interactive dashboard is complete and pipe-safe'
else
  _bash_god_package_fail 'non-interactive dashboard is complete and pipe-safe'
fi

_bash_god_package_kafka="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" kafka offset 2>&1)"
_bash_god_package_mongo="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" mongo service 1 2>&1)"
_bash_god_package_search="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" q consumer lag 2>&1)"
_bash_god_package_tree="$(env -i PATH=/usr/bin:/bin TERM=dumb LC_ALL=C GOD_COLOR=never "$_bash_god_package_cli" k8s logs --tree --full 2>&1)"
if _bash_god_package_contains "$_bash_god_package_kafka" 'kafka-consumer-groups.sh' && \
   _bash_god_package_contains "$_bash_god_package_mongo" 'systemctl status mongod' && \
   _bash_god_package_contains "$_bash_god_package_search" 'Show consumer-group offsets and lag' && \
   _bash_god_package_contains "$_bash_god_package_tree" 'kubectl logs'; then
  _bash_god_package_pass 'packaged navigation, search, rows, and full trees work'
else
  _bash_god_package_fail 'packaged navigation, search, rows, and full trees work'
fi

_bash_god_package_bad_checksum="$_bash_god_package_temp/bad.sha256"
printf '%064d  %s\n' 0 "$(basename "$_bash_god_package_archive")" > "$_bash_god_package_bad_checksum"
_bash_god_package_bad_prefix="$_bash_god_package_temp/bad-prefix"
_bash_god_package_bad_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_package_bad_prefix" "$_bash_god_package_archive" "$_bash_god_package_bad_checksum" >/dev/null 2>&1 || _bash_god_package_bad_status=$?
if [ "$_bash_god_package_bad_status" -eq 1 ] && [ ! -e "$_bash_god_package_bad_prefix" ]; then
  _bash_god_package_pass 'checksum failure prevents installation'
else
  _bash_god_package_fail 'checksum failure prevents installation'
fi

_bash_god_package_duplicate_checksum="$_bash_god_package_temp/duplicate.sha256"
cp "$_bash_god_package_checksum" "$_bash_god_package_duplicate_checksum"
command cat "$_bash_god_package_checksum" >> "$_bash_god_package_duplicate_checksum"
_bash_god_package_duplicate_prefix="$_bash_god_package_temp/duplicate-prefix"
_bash_god_package_duplicate_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_package_duplicate_prefix" "$_bash_god_package_archive" "$_bash_god_package_duplicate_checksum" >/dev/null 2>&1 || _bash_god_package_duplicate_status=$?
if [ "$_bash_god_package_duplicate_status" -eq 1 ] && [ ! -e "$_bash_god_package_duplicate_prefix" ]; then
  _bash_god_package_pass 'ambiguous checksum files are rejected'
else
  _bash_god_package_fail 'ambiguous checksum files are rejected'
fi

_bash_god_unexpected_work="$_bash_god_package_temp/unexpected-work"
_bash_god_unexpected_archive="$_bash_god_package_temp/$_bash_god_package_name-unexpected.tar.gz"
_bash_god_unexpected_checksum="$_bash_god_unexpected_archive.sha256"
mkdir -p "$_bash_god_unexpected_work"
tar -xzf "$_bash_god_package_archive" -C "$_bash_god_unexpected_work"
printf 'not part of the runtime\n' > "$_bash_god_unexpected_work/$_bash_god_package_name/unexpected.txt"
tar -czf "$_bash_god_unexpected_archive" -C "$_bash_god_unexpected_work" "$_bash_god_package_name"
_bash_god_package_write_checksum "$_bash_god_unexpected_archive" "$_bash_god_unexpected_checksum"
_bash_god_unexpected_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_package_temp/unexpected-prefix" "$_bash_god_unexpected_archive" "$_bash_god_unexpected_checksum" >/dev/null 2>&1 || _bash_god_unexpected_status=$?
if [ "$_bash_god_unexpected_status" -eq 1 ] && [ ! -e "$_bash_god_package_temp/unexpected-prefix" ]; then
  _bash_god_package_pass 'unexpected archive entries are rejected before extraction'
else
  _bash_god_package_fail 'unexpected archive entries are rejected before extraction'
fi

_bash_god_link_work="$_bash_god_package_temp/link-work"
_bash_god_link_archive="$_bash_god_package_temp/$_bash_god_package_name-link.tar.gz"
_bash_god_link_checksum="$_bash_god_link_archive.sha256"
mkdir -p "$_bash_god_link_work"
tar -xzf "$_bash_god_package_archive" -C "$_bash_god_link_work"
command rm -f "$_bash_god_link_work/$_bash_god_package_name/bin/god"
ln -s "$_bash_god_package_temp/link-target" "$_bash_god_link_work/$_bash_god_package_name/bin/god"
tar -czf "$_bash_god_link_archive" -C "$_bash_god_link_work" "$_bash_god_package_name"
_bash_god_package_write_checksum "$_bash_god_link_archive" "$_bash_god_link_checksum"
_bash_god_link_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_package_temp/link-prefix" "$_bash_god_link_archive" "$_bash_god_link_checksum" >/dev/null 2>&1 || _bash_god_link_status=$?
if [ "$_bash_god_link_status" -eq 1 ] && [ ! -e "$_bash_god_package_temp/link-prefix" ] && [ ! -e "$_bash_god_package_temp/link-target" ]; then
  _bash_god_package_pass 'archives containing symbolic links are rejected before extraction'
else
  _bash_god_package_fail 'archives containing symbolic links are rejected before extraction'
fi

_bash_god_mismatch_work="$_bash_god_package_temp/mismatch-work"
_bash_god_mismatch_archive="$_bash_god_package_temp/$_bash_god_mismatch_name.tar.gz"
_bash_god_mismatch_checksum="$_bash_god_mismatch_archive.sha256"
mkdir -p "$_bash_god_mismatch_work"
tar -xzf "$_bash_god_package_archive" -C "$_bash_god_mismatch_work"
mv "$_bash_god_mismatch_work/$_bash_god_package_name" "$_bash_god_mismatch_work/$_bash_god_mismatch_name"
tar -czf "$_bash_god_mismatch_archive" -C "$_bash_god_mismatch_work" "$_bash_god_mismatch_name"
_bash_god_package_write_checksum "$_bash_god_mismatch_archive" "$_bash_god_mismatch_checksum"
_bash_god_mismatch_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_package_temp/mismatch-prefix" "$_bash_god_mismatch_archive" "$_bash_god_mismatch_checksum" >/dev/null 2>&1 || _bash_god_mismatch_status=$?
if [ "$_bash_god_mismatch_status" -eq 1 ] && [ ! -e "$_bash_god_package_temp/mismatch-prefix" ]; then
  _bash_god_package_pass 'archive and embedded CLI versions must match exactly'
else
  _bash_god_package_fail 'archive and embedded CLI versions must match exactly'
fi

_bash_god_symlink_prefix="$_bash_god_package_temp/symlink-prefix"
_bash_god_symlink_target="$_bash_god_package_temp/symlink-launcher-target"
mkdir -p "$_bash_god_symlink_prefix/bin"
ln -s "$_bash_god_symlink_target" "$_bash_god_symlink_prefix/bin/god"
_bash_god_symlink_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_symlink_prefix" "$_bash_god_package_archive" "$_bash_god_package_checksum" >/dev/null 2>&1 || _bash_god_symlink_status=$?
if [ "$_bash_god_symlink_status" -eq 1 ] && [ -L "$_bash_god_symlink_prefix/bin/god" ] && [ ! -e "$_bash_god_symlink_target" ]; then
  _bash_god_package_pass 'installer refuses a symlinked destination launcher'
else
  _bash_god_package_fail 'installer refuses a symlinked destination launcher'
fi

_bash_god_package_reinstall_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --prefix "$_bash_god_package_prefix" "$_bash_god_package_archive" "$_bash_god_package_checksum" >/dev/null 2>&1 || _bash_god_package_reinstall_status=$?
_bash_god_package_replace_status=0
"$_bash_god_package_root/packaging/install-runtime.sh" --replace --prefix "$_bash_god_package_prefix" "$_bash_god_package_archive" "$_bash_god_package_checksum" >/dev/null || _bash_god_package_replace_status=$?
_bash_god_package_backup_container="$(command find "$_bash_god_package_prefix/lib" -type d -name 'bash-god.backup-*' -print | LC_ALL=C awk 'NR == 1 { print; exit }')"
if [ "$_bash_god_package_reinstall_status" -eq 1 ] && [ "$_bash_god_package_replace_status" -eq 0 ] && [ -n "$_bash_god_package_backup_container" ] && \
   [ -x "$_bash_god_package_backup_container/runtime/god" ] && \
   [ "$(GOD_COLOR=never "$_bash_god_package_backup_container/runtime/god" --version)" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$_bash_god_expected_version")" ]; then
  _bash_god_package_pass 'replacement is explicit and retains the previous runtime'
else
  _bash_god_package_fail 'replacement is explicit and retains the previous runtime'
fi

if [ "$_bash_god_package_failures" -eq 0 ]; then
  printf '\n%d package checks passed.\n' "$_bash_god_package_checks"
  exit 0
fi

printf '\n%d of %d package checks failed.\n' "$_bash_god_package_failures" "$_bash_god_package_checks" >&2
exit 1
