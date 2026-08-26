#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

_bash_god_install_die() {
  printf 'BASH_GOD install: %s\n' "$1" >&2
  exit 1
}

_bash_god_install_usage() {
  printf 'Usage: %s [--prefix PREFIX] [--replace] ARCHIVE CHECKSUM_FILE\n' "$0"
  printf '\nInstalls the CLI-only runtime under PREFIX (default: $HOME/.local).\n'
}

_bash_god_install_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  else
    _bash_god_install_die 'sha256sum or shasum is required to verify the package.'
  fi
}

if [ -n "${BASH_GOD_PREFIX:-}" ]; then
  _bash_god_install_prefix="$BASH_GOD_PREFIX"
elif [ -n "${HOME:-}" ]; then
  _bash_god_install_prefix="$HOME/.local"
else
  _bash_god_install_die 'HOME is unavailable; pass --prefix with an absolute path.'
fi
_bash_god_install_replace=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || _bash_god_install_die '--prefix requires a directory.'
      _bash_god_install_prefix="$2"
      shift 2
      ;;
    --replace)
      _bash_god_install_replace=1
      shift
      ;;
    --help|-h)
      _bash_god_install_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      _bash_god_install_die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -ne 2 ]; then
  _bash_god_install_usage >&2
  exit 2
fi

_bash_god_install_archive="$1"
_bash_god_install_checksum="$2"
[ -f "$_bash_god_install_archive" ] && [ -r "$_bash_god_install_archive" ] || _bash_god_install_die "archive is not a readable regular file: $_bash_god_install_archive"
[ -f "$_bash_god_install_checksum" ] && [ -r "$_bash_god_install_checksum" ] || _bash_god_install_die "checksum is not a readable regular file: $_bash_god_install_checksum"
case "$_bash_god_install_prefix" in
  /*) ;;
  *) _bash_god_install_die 'PREFIX must be an absolute path.' ;;
esac

_bash_god_install_archive_name="$(basename "$_bash_god_install_archive")"
case "$_bash_god_install_archive_name" in
  ''|*[!A-Za-z0-9._-]*) _bash_god_install_die 'archive filename contains unsupported characters.' ;;
esac

# Copy both caller-controlled inputs once, then verify and extract only these private snapshots.
_bash_god_install_stage="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-install.XXXXXX")" || exit 1
_bash_god_install_new_runtime=''
_bash_god_install_new_launcher=''
_bash_god_install_cleanup() {
  command rm -rf -- "$_bash_god_install_stage"
  [ -z "$_bash_god_install_new_runtime" ] || command rm -rf -- "$_bash_god_install_new_runtime"
  [ -z "$_bash_god_install_new_launcher" ] || command rm -f -- "$_bash_god_install_new_launcher"
}
trap '_bash_god_install_cleanup' EXIT
trap 'exit 1' HUP INT TERM
_bash_god_install_archive_snapshot="$_bash_god_install_stage/package.tar.gz"
_bash_god_install_checksum_snapshot="$_bash_god_install_stage/package.sha256"
cp "$_bash_god_install_archive" "$_bash_god_install_archive_snapshot" || _bash_god_install_die 'could not snapshot the archive for verification.'
cp "$_bash_god_install_checksum" "$_bash_god_install_checksum_snapshot" || _bash_god_install_die 'could not snapshot the checksum for verification.'
chmod 0600 "$_bash_god_install_archive_snapshot" "$_bash_god_install_checksum_snapshot"

if ! _bash_god_install_expected_hash="$(LC_ALL=C awk -v file="$_bash_god_install_archive_name" '
  $2 == file || $2 == "*" file { count++; hash = $1; fields = NF }
  END { if (count == 1 && fields == 2) print hash; else exit 1 }
' "$_bash_god_install_checksum_snapshot")"; then
  _bash_god_install_die 'checksum file must contain exactly one SHA-256 entry for the archive.'
fi
case "$_bash_god_install_expected_hash" in
  ''|*[!0-9A-Fa-f]*) _bash_god_install_die 'checksum file does not contain a valid SHA-256 entry for the archive.' ;;
esac
[ "${#_bash_god_install_expected_hash}" -eq 64 ] || _bash_god_install_die 'the expected SHA-256 hash must contain 64 hexadecimal characters.'
_bash_god_install_actual_hash="$(_bash_god_install_sha256 "$_bash_god_install_archive_snapshot")"
_bash_god_install_expected_hash="$(printf '%s' "$_bash_god_install_expected_hash" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
_bash_god_install_actual_hash="$(printf '%s' "$_bash_god_install_actual_hash" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
[ "$_bash_god_install_actual_hash" = "$_bash_god_install_expected_hash" ] || _bash_god_install_die 'SHA-256 verification failed; the archive was not installed.'

_bash_god_install_listing="$(tar -tzf "$_bash_god_install_archive_snapshot")" || _bash_god_install_die 'cannot read the package archive.'
_bash_god_install_top=''
while IFS= read -r _bash_god_install_entry; do
  [ -n "$_bash_god_install_entry" ] || continue
  case "$_bash_god_install_entry" in
    /*|..|../*|*/..|*/../*) _bash_god_install_die "unsafe archive path: $_bash_god_install_entry" ;;
  esac
  _bash_god_install_first="${_bash_god_install_entry%%/*}"
  if [ -z "$_bash_god_install_top" ]; then
    _bash_god_install_top="$_bash_god_install_first"
  elif [ "$_bash_god_install_first" != "$_bash_god_install_top" ]; then
    _bash_god_install_die 'archive must contain exactly one top-level package directory.'
  fi
done <<EOF
$_bash_god_install_listing
EOF

case "$_bash_god_install_top" in
  bash-god-[0-9]*) ;;
  *) _bash_god_install_die 'archive top-level directory does not identify a BASH_GOD release.' ;;
esac
_bash_god_install_version="${_bash_god_install_top#bash-god-}"
case "$_bash_god_install_version" in
  ''|*[!0-9.]*) _bash_god_install_die 'archive version is not numeric.' ;;
esac

while IFS= read -r _bash_god_install_entry; do
  [ -n "$_bash_god_install_entry" ] || continue
  _bash_god_install_relative="${_bash_god_install_entry#$_bash_god_install_top}"
  _bash_god_install_relative="${_bash_god_install_relative#/}"
  case "$_bash_god_install_relative" in
    ''|bin/|lib/|lib/bash-god/|lib/bash-god/bash_god/|lib/bash-god/bash_god/catalog/|share/|share/licenses/|share/licenses/bash-god/)
      ;;
    bin/god|lib/bash-god/god|lib/bash-god/bash_god/art.sh|lib/bash-god/bash_god/catalog.sh|lib/bash-god/bash_god/core.sh|lib/bash-god/bash_god/render.sh|lib/bash-god/bash_god/search.sh|lib/bash-god/bash_god/tree.sh|share/licenses/bash-god/LICENSE)
      ;;
    lib/bash-god/bash_god/catalog/*/)
      _bash_god_install_service="${_bash_god_install_relative#lib/bash-god/bash_god/catalog/}"
      _bash_god_install_service="${_bash_god_install_service%/}"
      case "$_bash_god_install_service" in
        ''|*/*|*[!a-z0-9_-]*) _bash_god_install_die "unexpected archive directory: $_bash_god_install_entry" ;;
      esac
      ;;
    lib/bash-god/bash_god/catalog/*/service.god)
      _bash_god_install_service="${_bash_god_install_relative#lib/bash-god/bash_god/catalog/}"
      _bash_god_install_service="${_bash_god_install_service%/service.god}"
      case "$_bash_god_install_service" in
        ''|*/*|*[!a-z0-9_-]*) _bash_god_install_die "unexpected catalog path: $_bash_god_install_entry" ;;
      esac
      ;;
    *)
      _bash_god_install_die "unexpected archive entry: $_bash_god_install_entry"
      ;;
  esac
done <<EOF
$_bash_god_install_listing
EOF

if ! tar -tvzf "$_bash_god_install_archive_snapshot" | LC_ALL=C awk 'substr($1, 1, 1) != "d" && substr($1, 1, 1) != "-" { bad = 1 } END { exit bad }'; then
  _bash_god_install_die 'archive contains a link or unsupported filesystem entry.'
fi

tar -xzf "$_bash_god_install_archive_snapshot" -C "$_bash_god_install_stage"
_bash_god_install_root="$_bash_god_install_stage/$_bash_god_install_top"

for _bash_god_install_required in \
  bin/god \
  lib/bash-god/god \
  lib/bash-god/bash_god/art.sh \
  lib/bash-god/bash_god/catalog.sh \
  lib/bash-god/bash_god/core.sh \
  lib/bash-god/bash_god/render.sh \
  lib/bash-god/bash_god/search.sh \
  lib/bash-god/bash_god/tree.sh \
  share/licenses/bash-god/LICENSE; do
  [ -f "$_bash_god_install_root/$_bash_god_install_required" ] || _bash_god_install_die "package is missing $_bash_god_install_required"
done
_bash_god_install_catalogs="$(command find "$_bash_god_install_root/lib/bash-god/bash_god/catalog" -type f -name service.god -print)"
[ -n "$_bash_god_install_catalogs" ] || _bash_god_install_die 'package contains no service catalogs.'
[ -z "$(command find "$_bash_god_install_root" -type l -print -quit)" ] || _bash_god_install_die 'package extraction contains a symbolic link.'

chmod 0755 "$_bash_god_install_root/bin/god" "$_bash_god_install_root/lib/bash-god/god"
_bash_god_install_probe="$(GOD_COLOR=never "$_bash_god_install_root/bin/god" --version)" || _bash_god_install_die 'staged CLI failed its version check.'
_bash_god_install_probe_first="$(printf '%s\n' "$_bash_god_install_probe" | LC_ALL=C awk 'NR == 1 { print; exit }')"
[ "$_bash_god_install_probe_first" = "BASH_GOD $_bash_god_install_version" ] || _bash_god_install_die 'staged CLI version does not match the archive version.'

_bash_god_install_bin_dir="$_bash_god_install_prefix/bin"
_bash_god_install_lib_parent="$_bash_god_install_prefix/lib"
_bash_god_install_runtime="$_bash_god_install_lib_parent/bash-god"
_bash_god_install_license_dir="$_bash_god_install_prefix/share/licenses/bash-god"
_bash_god_install_launcher="$_bash_god_install_bin_dir/god"

if [ -L "$_bash_god_install_launcher" ]; then
  _bash_god_install_die "refusing to replace a symlinked launcher: $_bash_god_install_launcher"
fi
if [ -e "$_bash_god_install_launcher" ]; then
  [ -f "$_bash_god_install_launcher" ] && LC_ALL=C grep -q '^# Real-file launcher installed at PREFIX/bin/god by the runtime package\.$' "$_bash_god_install_launcher" || _bash_god_install_die "refusing to replace an unmanaged launcher: $_bash_god_install_launcher"
fi
if [ -L "$_bash_god_install_runtime" ]; then
  _bash_god_install_die "refusing to replace a symlinked runtime: $_bash_god_install_runtime"
fi
if [ -e "$_bash_god_install_runtime" ]; then
  [ "$_bash_god_install_replace" -eq 1 ] || _bash_god_install_die "runtime already exists; review it, then rerun with --replace: $_bash_god_install_runtime"
  [ -x "$_bash_god_install_runtime/god" ] && [ -r "$_bash_god_install_runtime/bash_god/core.sh" ] || _bash_god_install_die "refusing to replace an unmanaged runtime: $_bash_god_install_runtime"
fi
if [ -L "$_bash_god_install_license_dir" ] || [ -L "$_bash_god_install_license_dir/LICENSE" ]; then
  _bash_god_install_die "refusing to write through a symlinked license path: $_bash_god_install_license_dir"
fi

mkdir -p "$_bash_god_install_bin_dir" "$_bash_god_install_lib_parent" "$_bash_god_install_license_dir"
_bash_god_install_new_runtime="$(mktemp -d "$_bash_god_install_lib_parent/.bash-god.new.XXXXXX")" || _bash_god_install_die 'could not create a private runtime staging directory.'
cp -R "$_bash_god_install_root/lib/bash-god/." "$_bash_god_install_new_runtime/"
chmod 0755 "$_bash_god_install_new_runtime"
GOD_COLOR=never "$_bash_god_install_new_runtime/god" --version >/dev/null || _bash_god_install_die 'copied runtime failed its version check.'

_bash_god_install_new_launcher="$(mktemp "$_bash_god_install_bin_dir/.god.new.XXXXXX")" || _bash_god_install_die 'could not create a private launcher staging file.'
cp "$_bash_god_install_root/bin/god" "$_bash_god_install_new_launcher"
chmod 0755 "$_bash_god_install_new_launcher"

_bash_god_install_backup=''
if [ -e "$_bash_god_install_runtime" ]; then
  _bash_god_install_old_version="$(GOD_COLOR=never "$_bash_god_install_runtime/god" --version 2>/dev/null | LC_ALL=C awk 'NR == 1 { print $2 }')"
  case "$_bash_god_install_old_version" in
    ''|*[!0-9.]*) _bash_god_install_old_version=unknown ;;
  esac
  _bash_god_install_backup_container="$(mktemp -d "$_bash_god_install_lib_parent/bash-god.backup-$_bash_god_install_old_version.XXXXXX")" || _bash_god_install_die 'could not create a private backup directory.'
  _bash_god_install_backup="$_bash_god_install_backup_container/runtime"
  mv "$_bash_god_install_runtime" "$_bash_god_install_backup"
fi
if ! mv "$_bash_god_install_new_runtime" "$_bash_god_install_runtime"; then
  if [ -n "$_bash_god_install_backup" ] && [ -d "$_bash_god_install_backup" ]; then
    mv "$_bash_god_install_backup" "$_bash_god_install_runtime" || true
  fi
  _bash_god_install_die 'could not activate the staged runtime.'
fi
_bash_god_install_new_runtime=''
mv -f "$_bash_god_install_new_launcher" "$_bash_god_install_launcher"
_bash_god_install_new_launcher=''
cp "$_bash_god_install_root/share/licenses/bash-god/LICENSE" "$_bash_god_install_license_dir/LICENSE"

GOD_COLOR=never "$_bash_god_install_launcher" --version >/dev/null || _bash_god_install_die 'installed CLI failed its final version check.'
printf 'Installed BASH_GOD %s\n' "$_bash_god_install_version"
printf 'Command: %s\n' "$_bash_god_install_launcher"
if [ -n "$_bash_god_install_backup" ]; then
  printf 'Previous runtime retained at: %s\n' "$_bash_god_install_backup"
fi
case ":${PATH:-}:" in
  *":$_bash_god_install_bin_dir:"*) ;;
  *) printf 'Add this directory to PATH: export PATH="%s:$PATH"\n' "$_bash_god_install_bin_dir" ;;
esac
