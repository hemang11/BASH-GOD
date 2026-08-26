#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

_bash_god_package_die() {
  printf 'BASH_GOD package: %s\n' "$1" >&2
  exit 1
}

_bash_god_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  else
    _bash_god_package_die 'sha256sum or shasum is required to create the checksum.'
  fi
}

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [OUTPUT_DIRECTORY]\n' "$0" >&2
  exit 2
fi

_bash_god_package_file="${BASH_SOURCE[0]}"
_bash_god_package_dir="$(CDPATH= cd "$(dirname "$_bash_god_package_file")" 2>/dev/null && pwd -P)" || exit 1
_bash_god_repo_dir="$(CDPATH= cd "$_bash_god_package_dir/.." 2>/dev/null && pwd -P)" || exit 1
_bash_god_core="$_bash_god_repo_dir/bash_god/core.sh"

[ -r "$_bash_god_core" ] || _bash_god_package_die "cannot read $_bash_god_core"
_bash_god_version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$_bash_god_core")"
case "$_bash_god_version" in
  ''|*[!0-9.]*) _bash_god_package_die 'could not read a numeric BASH_GOD version from core.sh.' ;;
esac

_bash_god_output_dir="${1:-$_bash_god_repo_dir/dist}"
mkdir -p "$_bash_god_output_dir"
_bash_god_output_dir="$(CDPATH= cd "$_bash_god_output_dir" 2>/dev/null && pwd -P)" || exit 1

_bash_god_package_name="bash-god-$_bash_god_version"
_bash_god_archive="$_bash_god_output_dir/$_bash_god_package_name.tar.gz"
_bash_god_checksum="$_bash_god_archive.sha256"
_bash_god_installer_source="$_bash_god_package_dir/install-runtime.sh"
_bash_god_installer="$_bash_god_output_dir/install-runtime.sh"
_bash_god_installer_checksum="$_bash_god_installer.sha256"
_bash_god_bootstrap_source="$_bash_god_package_dir/install.sh"
_bash_god_bootstrap="$_bash_god_output_dir/install.sh"
_bash_god_bootstrap_checksum="$_bash_god_bootstrap.sha256"

for _bash_god_artifact in \
  "$_bash_god_archive" \
  "$_bash_god_checksum" \
  "$_bash_god_installer" \
  "$_bash_god_installer_checksum" \
  "$_bash_god_bootstrap" \
  "$_bash_god_bootstrap_checksum"; do
  if [ -e "$_bash_god_artifact" ] || [ -L "$_bash_god_artifact" ]; then
    _bash_god_package_die "refusing to overwrite an existing artifact in $_bash_god_output_dir"
  fi
done
[ -r "$_bash_god_installer_source" ] || _bash_god_package_die "cannot read $_bash_god_installer_source"
[ -r "$_bash_god_bootstrap_source" ] || _bash_god_package_die "cannot read $_bash_god_bootstrap_source"

_bash_god_stage="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-package.XXXXXX")" || exit 1
_bash_god_created_artifacts=()
_bash_god_publish_current=''
_bash_god_package_cleanup() {
  _bash_god_cleanup_status="$1"
  if [ "$_bash_god_cleanup_status" -ne 0 ]; then
    for _bash_god_created_artifact in "${_bash_god_created_artifacts[@]}"; do
      command rm -f -- "$_bash_god_created_artifact"
    done
  fi
  [ -z "$_bash_god_publish_current" ] || command rm -f -- "$_bash_god_publish_current"
  command rm -rf -- "$_bash_god_stage"
}
_bash_god_publish_file() {
  _bash_god_publish_source="$1"
  _bash_god_publish_target="$2"
  _bash_god_publish_mode="$3"

  _bash_god_publish_current="$(mktemp "$_bash_god_output_dir/.bash-god-publish.XXXXXX")" || \
    _bash_god_package_die 'could not create a private artifact publication file.'
  command cat "$_bash_god_publish_source" > "$_bash_god_publish_current"
  chmod "$_bash_god_publish_mode" "$_bash_god_publish_current"
  ln "$_bash_god_publish_current" "$_bash_god_publish_target" || \
    _bash_god_package_die "refusing to overwrite artifact: $_bash_god_publish_target"
  _bash_god_created_artifacts+=("$_bash_god_publish_target")
  command rm -f -- "$_bash_god_publish_current"
  _bash_god_publish_current=''
}
trap '_bash_god_package_cleanup $?' EXIT
trap 'exit 1' HUP INT TERM
_bash_god_root="$_bash_god_stage/$_bash_god_package_name"
_bash_god_staged_archive="$_bash_god_stage/$_bash_god_package_name.tar.gz"
_bash_god_staged_checksum="$_bash_god_staged_archive.sha256"
_bash_god_staged_installer="$_bash_god_stage/install-runtime.sh"
_bash_god_staged_installer_checksum="$_bash_god_staged_installer.sha256"
_bash_god_staged_bootstrap="$_bash_god_stage/install.sh"
_bash_god_staged_bootstrap_checksum="$_bash_god_staged_bootstrap.sha256"

mkdir -p \
  "$_bash_god_root/bin" \
  "$_bash_god_root/lib/bash-god/bash_god/catalog" \
  "$_bash_god_root/share/licenses/bash-god"

cp "$_bash_god_package_dir/god" "$_bash_god_root/bin/god"
cp "$_bash_god_repo_dir/god" "$_bash_god_root/lib/bash-god/god"
for _bash_god_module in art.sh catalog.sh core.sh maintenance.sh render.sh search.sh tree.sh; do
  cp "$_bash_god_repo_dir/bash_god/$_bash_god_module" "$_bash_god_root/lib/bash-god/bash_god/$_bash_god_module"
done

_bash_god_catalog_count=0
for _bash_god_catalog in "$_bash_god_repo_dir"/bash_god/catalog/*/service.god; do
  [ -f "$_bash_god_catalog" ] || continue
  _bash_god_service="${_bash_god_catalog%/service.god}"
  _bash_god_service="${_bash_god_service##*/}"
  case "$_bash_god_service" in
    ''|*[!a-z0-9_-]*) _bash_god_package_die "unsafe service directory: $_bash_god_service" ;;
  esac
  mkdir -p "$_bash_god_root/lib/bash-god/bash_god/catalog/$_bash_god_service"
  cp "$_bash_god_catalog" "$_bash_god_root/lib/bash-god/bash_god/catalog/$_bash_god_service/service.god"
  _bash_god_catalog_count=$((_bash_god_catalog_count + 1))
done
[ "$_bash_god_catalog_count" -gt 0 ] || _bash_god_package_die 'no service catalogs were found.'

cp "$_bash_god_repo_dir/LICENSE" "$_bash_god_root/share/licenses/bash-god/LICENSE"
command find "$_bash_god_root" -type d -exec chmod 0755 {} \;
command find "$_bash_god_root" -type f -exec chmod 0644 {} \;
chmod 0755 "$_bash_god_root/bin/god" "$_bash_god_root/lib/bash-god/god"

(
  CDPATH= cd "$_bash_god_stage"
  COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 tar -czf "$_bash_god_staged_archive" "$_bash_god_package_name"
)

_bash_god_hash="$(_bash_god_sha256 "$_bash_god_staged_archive")"
printf '%s  %s\n' "$_bash_god_hash" "$(basename "$_bash_god_archive")" > "$_bash_god_staged_checksum"
cp "$_bash_god_installer_source" "$_bash_god_staged_installer"
chmod 0755 "$_bash_god_staged_installer"
_bash_god_installer_hash="$(_bash_god_sha256 "$_bash_god_staged_installer")"
printf '%s  %s\n' "$_bash_god_installer_hash" "$(basename "$_bash_god_installer")" > "$_bash_god_staged_installer_checksum"
cp "$_bash_god_bootstrap_source" "$_bash_god_staged_bootstrap"
chmod 0755 "$_bash_god_staged_bootstrap"
_bash_god_bootstrap_hash="$(_bash_god_sha256 "$_bash_god_staged_bootstrap")"
printf '%s  %s\n' "$_bash_god_bootstrap_hash" "$(basename "$_bash_god_bootstrap")" > "$_bash_god_staged_bootstrap_checksum"

# Publish through same-filesystem temporary files. Hard-link creation is atomic and never replaces an
# existing path, including one that appears after the initial check.
_bash_god_publish_file "$_bash_god_staged_archive" "$_bash_god_archive" 0644
_bash_god_publish_file "$_bash_god_staged_checksum" "$_bash_god_checksum" 0644
_bash_god_publish_file "$_bash_god_staged_installer" "$_bash_god_installer" 0755
_bash_god_publish_file "$_bash_god_staged_installer_checksum" "$_bash_god_installer_checksum" 0644
_bash_god_publish_file "$_bash_god_staged_bootstrap" "$_bash_god_bootstrap" 0755
_bash_god_publish_file "$_bash_god_staged_bootstrap_checksum" "$_bash_god_bootstrap_checksum" 0644

printf 'Built %s\n' "$_bash_god_archive"
printf 'SHA-256 %s\n' "$_bash_god_hash"
printf 'Checksum %s\n' "$_bash_god_checksum"
printf 'Installer %s\n' "$_bash_god_installer"
printf 'Installer SHA-256 %s\n' "$_bash_god_installer_hash"
printf 'Installer checksum %s\n' "$_bash_god_installer_checksum"
printf 'Bootstrap %s\n' "$_bash_god_bootstrap"
printf 'Bootstrap SHA-256 %s\n' "$_bash_god_bootstrap_hash"
printf 'Bootstrap checksum %s\n' "$_bash_god_bootstrap_checksum"
