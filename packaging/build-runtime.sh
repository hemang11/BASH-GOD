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

if [ -e "$_bash_god_archive" ] || [ -L "$_bash_god_archive" ] || \
   [ -e "$_bash_god_checksum" ] || [ -L "$_bash_god_checksum" ]; then
  _bash_god_package_die "refusing to overwrite an existing artifact in $_bash_god_output_dir"
fi

_bash_god_stage="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-package.XXXXXX")" || exit 1
_bash_god_archive_created=0
_bash_god_checksum_created=0
_bash_god_publish_archive=''
_bash_god_publish_checksum=''
_bash_god_package_cleanup() {
  _bash_god_cleanup_status="$1"
  if [ "$_bash_god_cleanup_status" -ne 0 ]; then
    [ "$_bash_god_checksum_created" -eq 0 ] || command rm -f -- "$_bash_god_checksum"
    [ "$_bash_god_archive_created" -eq 0 ] || command rm -f -- "$_bash_god_archive"
  fi
  [ -z "$_bash_god_publish_checksum" ] || command rm -f -- "$_bash_god_publish_checksum"
  [ -z "$_bash_god_publish_archive" ] || command rm -f -- "$_bash_god_publish_archive"
  command rm -rf -- "$_bash_god_stage"
}
trap '_bash_god_package_cleanup $?' EXIT
trap 'exit 1' HUP INT TERM
_bash_god_root="$_bash_god_stage/$_bash_god_package_name"
_bash_god_staged_archive="$_bash_god_stage/$_bash_god_package_name.tar.gz"
_bash_god_staged_checksum="$_bash_god_staged_archive.sha256"

mkdir -p \
  "$_bash_god_root/bin" \
  "$_bash_god_root/lib/bash-god/bash_god/catalog" \
  "$_bash_god_root/share/licenses/bash-god"

cp "$_bash_god_package_dir/god" "$_bash_god_root/bin/god"
cp "$_bash_god_repo_dir/god" "$_bash_god_root/lib/bash-god/god"
for _bash_god_module in art.sh catalog.sh core.sh render.sh search.sh tree.sh; do
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

# Publish through same-filesystem temporary files. Hard-link creation is atomic and never replaces an
# existing path, including one that appears after the initial check.
_bash_god_publish_archive="$(mktemp "$_bash_god_output_dir/.bash-god-archive.XXXXXX")" || \
  _bash_god_package_die 'could not create a private archive publication file.'
command cat "$_bash_god_staged_archive" > "$_bash_god_publish_archive"
chmod 0644 "$_bash_god_publish_archive"
ln "$_bash_god_publish_archive" "$_bash_god_archive" || \
  _bash_god_package_die "refusing to overwrite archive: $_bash_god_archive"
_bash_god_archive_created=1
command rm -f -- "$_bash_god_publish_archive"
_bash_god_publish_archive=''

_bash_god_publish_checksum="$(mktemp "$_bash_god_output_dir/.bash-god-checksum.XXXXXX")" || \
  _bash_god_package_die 'could not create a private checksum publication file.'
command cat "$_bash_god_staged_checksum" > "$_bash_god_publish_checksum"
chmod 0644 "$_bash_god_publish_checksum"
ln "$_bash_god_publish_checksum" "$_bash_god_checksum" || \
  _bash_god_package_die "refusing to overwrite checksum: $_bash_god_checksum"
_bash_god_checksum_created=1
command rm -f -- "$_bash_god_publish_checksum"
_bash_god_publish_checksum=''

printf 'Built %s\n' "$_bash_god_archive"
printf 'SHA-256 %s\n' "$_bash_god_hash"
printf 'Checksum %s\n' "$_bash_god_checksum"
