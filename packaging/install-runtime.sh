#!/usr/bin/env bash

# Install a checksum-verified BASH_GOD runtime. This program is deliberately
# self-contained: public bootstrap and in-place updater download it before a
# runtime is trusted. It never asks the caller to identify an architecture.

set -o errexit
set -o nounset
set -o pipefail

_bash_god_install_die() {
  printf 'BASH_GOD install: %s\n' "$1" >&2
  exit 1
}

_bash_god_install_usage() {
  printf 'Usage: %s [--prefix PREFIX] [--replace] ARCHIVE CHECKSUM_FILE\n' "$0"
  printf '\nInstalls the CLI runtime and its native terminal helper under PREFIX (default: $HOME/.local).\n'
  printf '  --replace  Upgrade or reinstall a managed runtime and retain the previous version.\n'
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

_bash_god_install_platform() {
  local os arch

  os="$(uname -s 2>/dev/null)" || return 1
  arch="$(uname -m 2>/dev/null)" || return 1
  case "$os:$arch" in
    Darwin:x86_64|Darwin:amd64) printf '%s\n' darwin-amd64 ;;
    Darwin:arm64|Darwin:aarch64) printf '%s\n' darwin-arm64 ;;
    Linux:x86_64|Linux:amd64) printf '%s\n' linux-amd64 ;;
    Linux:arm64|Linux:aarch64) printf '%s\n' linux-arm64 ;;
    *) return 1 ;;
  esac
}

_bash_god_install_manifest_exact() {
  local file version artifact protocol expected actual

  file=$1
  version=$2
  artifact=$3
  protocol=$4
  expected="$(printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=%s\nprotocol=%s' \
    "$version" "$artifact" "$protocol")"
  actual="$(command cat "$file" 2>/dev/null)" || return 1
  [ "$actual" = "$expected" ]
}

# R08 changed the runtime layout from bash_god/ to src/ and added a private
# helper.  The first R08 installer must still be able to replace a real
# pre-R08 managed installation when its old updater downloads the deliberately
# retained, unsuffixed compatibility archive.  Do not treat a directory with
# only a similarly named core file as managed: verify the frozen old package
# shape, absence of mixed new-layout state, the real-file ownership manifest,
# and every old runtime file that package shipped.
_bash_god_install_legacy_runtime_is_managed() {
  local runtime core entry relative service catalog_found version expected actual

  runtime=$1
  core="$runtime/bash_god/core.sh"
  [ -d "$runtime" ] && [ ! -L "$runtime" ] || return 1
  [ ! -e "$runtime/src" ] && [ ! -L "$runtime/src" ] || return 1
  [ ! -e "$runtime/tui-manifest" ] && [ ! -L "$runtime/tui-manifest" ] || return 1
  [ ! -e "$_bash_god_install_helper" ] && [ ! -L "$_bash_god_install_helper" ] || return 1
  [ -f "$_bash_god_install_license_dir/LICENSE" ] && [ ! -L "$_bash_god_install_license_dir/LICENSE" ] || return 1
  [ -f "$_bash_god_install_manifest" ] && [ ! -L "$_bash_god_install_manifest" ] || return 1
  [ -z "$(command find "$runtime" -type l -print -quit 2>/dev/null)" ] || return 1

  for relative in \
    god \
    bash_god/art.sh \
    bash_god/catalog.sh \
    bash_god/core.sh \
    bash_god/discover.sh \
    bash_god/execute.sh \
    bash_god/maintenance.sh \
    bash_god/menu.sh \
    bash_god/render.sh \
    bash_god/resolve.sh \
    bash_god/search.sh \
    bash_god/tree.sh; do
    [ -f "$runtime/$relative" ] && [ ! -L "$runtime/$relative" ] || return 1
  done
  [ -x "$runtime/god" ] || return 1
  [ -d "$runtime/bash_god" ] && [ ! -L "$runtime/bash_god" ] || return 1
  [ -d "$runtime/bash_god/catalog" ] && [ ! -L "$runtime/bash_god/catalog" ] || return 1

  catalog_found=0
  while IFS= read -r entry; do
    relative=${entry#"$runtime"/}
    case "$relative" in
      god|bash_god|bash_god/art.sh|bash_god/catalog.sh|bash_god/core.sh|bash_god/discover.sh|bash_god/execute.sh|bash_god/maintenance.sh|bash_god/menu.sh|bash_god/render.sh|bash_god/resolve.sh|bash_god/search.sh|bash_god/tree.sh|bash_god/catalog)
        ;;
      bash_god/catalog/*/service.god)
        service=${relative#bash_god/catalog/}
        service=${service%/service.god}
        case "$service" in
          ''|*/*|*[!a-z0-9_-]*) return 1 ;;
        esac
        [ -f "$entry" ] && [ ! -L "$entry" ] || return 1
        catalog_found=1
        ;;
      bash_god/catalog/*)
        service=${relative#bash_god/catalog/}
        case "$service" in
          ''|*/*|*[!a-z0-9_-]*) return 1 ;;
        esac
        [ -d "$entry" ] && [ ! -L "$entry" ] || return 1
        ;;
      *) return 1 ;;
    esac
  done < <(command find "$runtime" -mindepth 1 -print 2>/dev/null)
  [ "$catalog_found" -eq 1 ] || return 1

  version="$(LC_ALL=C awk -F"'" '
    /^_BASH_GOD_VERSION=/ { count++; value=$2 }
    END {
      if (count == 1 && value ~ /^[0-9]+([.][0-9]+)*$/) print value
      else exit 1
    }
  ' "$core")" || return 1
  [ -n "$version" ] || return 1
  [ -n "${_bash_god_install_prefix_physical:-}" ] || return 1
  expected="$(printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s' \
    "$_bash_god_install_prefix_physical" "$version")"
  actual="$(command cat "$_bash_god_install_manifest" 2>/dev/null)" || return 1
  [ "$actual" = "$expected" ]
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
      _bash_god_install_prefix=$2
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

_bash_god_install_archive=$1
_bash_god_install_checksum=$2
[ -f "$_bash_god_install_archive" ] && [ -r "$_bash_god_install_archive" ] || \
  _bash_god_install_die "archive is not a readable regular file: $_bash_god_install_archive"
[ -f "$_bash_god_install_checksum" ] && [ -r "$_bash_god_install_checksum" ] || \
  _bash_god_install_die "checksum is not a readable regular file: $_bash_god_install_checksum"
case "$_bash_god_install_prefix" in
  /*) ;;
  *) _bash_god_install_die 'PREFIX must be an absolute path.' ;;
esac

_bash_god_install_platform="$( _bash_god_install_platform )" || \
  _bash_god_install_die 'unsupported host platform; supported targets are darwin-amd64, darwin-arm64, linux-amd64, and linux-arm64.'

_bash_god_install_archive_name="$(basename "$_bash_god_install_archive")"
case "$_bash_god_install_archive_name" in
  ''|*[!A-Za-z0-9._-]*) _bash_god_install_die 'archive filename contains unsupported characters.' ;;
esac

_bash_god_install_kind=''
_bash_god_install_version=''
_bash_god_install_artifact=''
for _bash_god_install_candidate in darwin-amd64 darwin-arm64 linux-amd64 linux-arm64; do
  case "$_bash_god_install_archive_name" in
    "bash-god-"*"-$_bash_god_install_candidate.tar.gz")
      _bash_god_install_version="${_bash_god_install_archive_name#bash-god-}"
      _bash_god_install_version="${_bash_god_install_version%-$_bash_god_install_candidate.tar.gz}"
      _bash_god_install_kind=target
      _bash_god_install_artifact=$_bash_god_install_candidate
      break
      ;;
  esac
done
if [ -z "$_bash_god_install_kind" ]; then
  case "$_bash_god_install_archive_name" in
    bash-god-*.tar.gz)
      _bash_god_install_version="${_bash_god_install_archive_name#bash-god-}"
      _bash_god_install_version="${_bash_god_install_version%.tar.gz}"
      _bash_god_install_kind=multi
      _bash_god_install_artifact=multi
      ;;
    *) _bash_god_install_die 'archive filename does not identify a BASH_GOD release.' ;;
  esac
fi
case "$_bash_god_install_version" in
  ''|*[!0-9.]*) _bash_god_install_die 'archive version is not numeric.' ;;
esac
if [ "$_bash_god_install_kind" = target ] && [ "$_bash_god_install_artifact" != "$_bash_god_install_platform" ]; then
  _bash_god_install_die "archive targets $_bash_god_install_artifact, but this host is $_bash_god_install_platform; no architecture was guessed."
fi

# Copy caller-controlled inputs once, then verify and extract only private snapshots.
_bash_god_install_stage="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-install.XXXXXX")" || exit 1
_bash_god_install_new_runtime=''
_bash_god_install_new_helper=''
_bash_god_install_new_launcher=''
_bash_god_install_new_manifest=''
_bash_god_install_runtime_target=''
_bash_god_install_helper_target=''
_bash_god_install_backup=''
_bash_god_install_backup_runtime=''
_bash_god_install_backup_helper=''
_bash_god_install_activated_runtime=0
_bash_god_install_activated_helper=0
_bash_god_install_cleanup() {
  if [ "${_bash_god_install_complete:-0}" != 1 ]; then
    if [ "$_bash_god_install_activated_helper" -eq 1 ] && [ -n "$_bash_god_install_helper_target" ]; then
      command rm -rf -- "$_bash_god_install_helper_target"
    fi
    if [ -n "$_bash_god_install_backup_helper" ] && [ -d "$_bash_god_install_backup_helper" ] && \
       [ ! -e "$_bash_god_install_helper_target" ]; then
      mv "$_bash_god_install_backup_helper" "$_bash_god_install_helper_target" || \
        printf 'BASH_GOD install: recovery needed; previous helper remains at %s\n' "$_bash_god_install_backup_helper" >&2
    fi
    if [ "$_bash_god_install_activated_runtime" -eq 1 ] && [ -n "$_bash_god_install_runtime_target" ]; then
      command rm -rf -- "$_bash_god_install_runtime_target"
    fi
    if [ -n "$_bash_god_install_backup_runtime" ] && [ -d "$_bash_god_install_backup_runtime" ] && \
       [ ! -e "$_bash_god_install_runtime_target" ]; then
      mv "$_bash_god_install_backup_runtime" "$_bash_god_install_runtime_target" || \
        printf 'BASH_GOD install: recovery needed; previous runtime remains at %s\n' "$_bash_god_install_backup_runtime" >&2
    fi
  fi
  command rm -rf -- "$_bash_god_install_stage"
  [ -z "$_bash_god_install_new_runtime" ] || command rm -rf -- "$_bash_god_install_new_runtime"
  [ -z "$_bash_god_install_new_helper" ] || command rm -rf -- "$_bash_god_install_new_helper"
  [ -z "$_bash_god_install_new_launcher" ] || command rm -f -- "$_bash_god_install_new_launcher"
  [ -z "$_bash_god_install_new_manifest" ] || command rm -f -- "$_bash_god_install_new_manifest"
}
trap '_bash_god_install_cleanup' EXIT
trap 'exit 1' HUP INT TERM
_bash_god_install_archive_snapshot="$_bash_god_install_stage/package.tar.gz"
_bash_god_install_checksum_snapshot="$_bash_god_install_stage/package.sha256"
cp "$_bash_god_install_archive" "$_bash_god_install_archive_snapshot" || \
  _bash_god_install_die 'could not snapshot the archive for verification.'
cp "$_bash_god_install_checksum" "$_bash_god_install_checksum_snapshot" || \
  _bash_god_install_die 'could not snapshot the checksum for verification.'
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
[ "${#_bash_god_install_expected_hash}" -eq 64 ] || \
  _bash_god_install_die 'the expected SHA-256 hash must contain 64 hexadecimal characters.'
_bash_god_install_actual_hash="$(_bash_god_install_sha256 "$_bash_god_install_archive_snapshot")"
_bash_god_install_expected_hash="$(printf '%s' "$_bash_god_install_expected_hash" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
_bash_god_install_actual_hash="$(printf '%s' "$_bash_god_install_actual_hash" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
[ "$_bash_god_install_actual_hash" = "$_bash_god_install_expected_hash" ] || \
  _bash_god_install_die 'SHA-256 verification failed; the archive was not installed.'

_bash_god_install_listing="$(tar -tzf "$_bash_god_install_archive_snapshot")" || \
  _bash_god_install_die 'cannot read the package archive.'
_bash_god_install_top=''
while IFS= read -r _bash_god_install_entry; do
  [ -n "$_bash_god_install_entry" ] || continue
  case "$_bash_god_install_entry" in
    /*|..|../*|*/..|*/../*) _bash_god_install_die "unsafe archive path: $_bash_god_install_entry" ;;
  esac
  _bash_god_install_first="${_bash_god_install_entry%%/*}"
  if [ -z "$_bash_god_install_top" ]; then
    _bash_god_install_top=$_bash_god_install_first
  elif [ "$_bash_god_install_first" != "$_bash_god_install_top" ]; then
    _bash_god_install_die 'archive must contain exactly one top-level package directory.'
  fi
done <<EOF
$_bash_god_install_listing
EOF

_bash_god_install_expected_top="bash-god-$_bash_god_install_version"
if [ "$_bash_god_install_kind" = target ]; then
  _bash_god_install_expected_top="$_bash_god_install_expected_top-$_bash_god_install_artifact"
fi
[ "$_bash_god_install_top" = "$_bash_god_install_expected_top" ] || \
  _bash_god_install_die 'archive top-level directory does not match its filename.'

while IFS= read -r _bash_god_install_entry; do
  [ -n "$_bash_god_install_entry" ] || continue
  _bash_god_install_relative="${_bash_god_install_entry#$_bash_god_install_top}"
  _bash_god_install_relative="${_bash_god_install_relative#/}"
  case "$_bash_god_install_relative" in
    ''|bin/|lib/|lib/bash-god/|lib/bash-god/src/|lib/bash-god/src/ui/|lib/bash-god/catalog/|libexec/|libexec/bash-god/|share/|share/licenses/|share/licenses/bash-god/)
      ;;
    bin/god|lib/bash-god/god|lib/bash-god/tui-manifest|lib/bash-god/src/catalog.sh|lib/bash-god/src/core.sh|lib/bash-god/src/discover.sh|lib/bash-god/src/eligibility.sh|lib/bash-god/src/execute.sh|lib/bash-god/src/interaction.sh|lib/bash-god/src/maintenance.sh|lib/bash-god/src/resolve.sh|lib/bash-god/src/search.sh|lib/bash-god/src/ui/art.sh|lib/bash-god/src/ui/input.sh|lib/bash-god/src/ui/menu.sh|lib/bash-god/src/ui/render.sh|lib/bash-god/src/ui/tree.sh|lib/bash-god/src/ui/tui.sh|share/licenses/bash-god/LICENSE|share/licenses/bash-god/THIRD_PARTY_NOTICES.md)
      ;;
    lib/bash-god/catalog/*/)
      _bash_god_install_service="${_bash_god_install_relative#lib/bash-god/catalog/}"
      _bash_god_install_service="${_bash_god_install_service%/}"
      case "$_bash_god_install_service" in
        ''|*/*|*[!a-z0-9_-]*) _bash_god_install_die "unexpected archive directory: $_bash_god_install_entry" ;;
      esac
      ;;
    lib/bash-god/catalog/*/service.god)
      _bash_god_install_service="${_bash_god_install_relative#lib/bash-god/catalog/}"
      _bash_god_install_service="${_bash_god_install_service%/service.god}"
      case "$_bash_god_install_service" in
        ''|*/*|*[!a-z0-9_-]*) _bash_god_install_die "unexpected catalog path: $_bash_god_install_entry" ;;
      esac
      ;;
    libexec/bash-god/god-tui)
      [ "$_bash_god_install_kind" = target ] || _bash_god_install_die "unexpected helper path: $_bash_god_install_entry"
      ;;
    libexec/bash-god/*/)
      [ "$_bash_god_install_kind" = multi ] || _bash_god_install_die "unexpected helper directory: $_bash_god_install_entry"
      _bash_god_install_service="${_bash_god_install_relative#libexec/bash-god/}"
      _bash_god_install_service="${_bash_god_install_service%/}"
      case "$_bash_god_install_service" in
        darwin-amd64|darwin-arm64|linux-amd64|linux-arm64) ;;
        *) _bash_god_install_die "unexpected helper directory: $_bash_god_install_entry" ;;
      esac
      ;;
    libexec/bash-god/*/god-tui)
      [ "$_bash_god_install_kind" = multi ] || _bash_god_install_die "unexpected helper path: $_bash_god_install_entry"
      _bash_god_install_service="${_bash_god_install_relative#libexec/bash-god/}"
      _bash_god_install_service="${_bash_god_install_service%/god-tui}"
      case "$_bash_god_install_service" in
        darwin-amd64|darwin-arm64|linux-amd64|linux-arm64) ;;
        *) _bash_god_install_die "unexpected helper path: $_bash_god_install_entry" ;;
      esac
      ;;
    *) _bash_god_install_die "unexpected archive entry: $_bash_god_install_entry" ;;
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
  lib/bash-god/tui-manifest \
  lib/bash-god/src/catalog.sh \
  lib/bash-god/src/core.sh \
  lib/bash-god/src/discover.sh \
  lib/bash-god/src/eligibility.sh \
  lib/bash-god/src/execute.sh \
  lib/bash-god/src/interaction.sh \
  lib/bash-god/src/maintenance.sh \
  lib/bash-god/src/resolve.sh \
  lib/bash-god/src/search.sh \
  lib/bash-god/src/ui/art.sh \
  lib/bash-god/src/ui/input.sh \
  lib/bash-god/src/ui/menu.sh \
  lib/bash-god/src/ui/render.sh \
  lib/bash-god/src/ui/tree.sh \
  lib/bash-god/src/ui/tui.sh \
  share/licenses/bash-god/LICENSE \
  share/licenses/bash-god/THIRD_PARTY_NOTICES.md; do
  [ -f "$_bash_god_install_root/$_bash_god_install_required" ] || \
    _bash_god_install_die "package is missing $_bash_god_install_required"
done
if [ "$_bash_god_install_kind" = target ]; then
  _bash_god_install_helper_source="$_bash_god_install_root/libexec/bash-god/god-tui"
else
  _bash_god_install_helper_source="$_bash_god_install_root/libexec/bash-god/$_bash_god_install_platform/god-tui"
fi
[ -f "$_bash_god_install_helper_source" ] || \
  _bash_god_install_die "package does not contain a helper for $_bash_god_install_platform"
_bash_god_install_catalogs="$(command find "$_bash_god_install_root/lib/bash-god/catalog" -type f -name service.god -print)"
[ -n "$_bash_god_install_catalogs" ] || _bash_god_install_die 'package contains no service catalogs.'
[ -z "$(command find "$_bash_god_install_root" -type l -print -quit)" ] || \
  _bash_god_install_die 'package extraction contains a symbolic link.'

_bash_god_install_protocol="$(LC_ALL=C awk -F= '
  /^_GOD_TUI_PROTOCOL_VERSION=/ {
    count++
    value=$2
    gsub(/[[:space:]]/, "", value)
  }
  END {
    if (count == 1 && value ~ /^[1-9][0-9]*$/) print value
    else exit 1
  }
' "$_bash_god_install_root/lib/bash-god/src/ui/tui.sh")" || \
  _bash_god_install_die 'package has an invalid helper protocol declaration.'
_bash_god_install_manifest_exact "$_bash_god_install_root/lib/bash-god/tui-manifest" \
  "$_bash_god_install_version" "$_bash_god_install_artifact" "$_bash_god_install_protocol" || \
  _bash_god_install_die 'package helper manifest does not match the archive identity.'

chmod 0755 "$_bash_god_install_root/bin/god" "$_bash_god_install_root/lib/bash-god/god" \
  "$_bash_god_install_helper_source"
_bash_god_install_probe="$(GOD_COLOR=never "$_bash_god_install_root/bin/god" --version)" || \
  _bash_god_install_die 'staged CLI failed its version check.'
_bash_god_install_probe_first="$(printf '%s\n' "$_bash_god_install_probe" | LC_ALL=C awk 'NR == 1 { print; exit }')"
[ "$_bash_god_install_probe_first" = "BASH_GOD $_bash_god_install_version" ] || \
  _bash_god_install_die 'staged CLI version does not match the archive version.'
_bash_god_install_helper_protocol="$("$_bash_god_install_helper_source" --protocol-version 2>/dev/null)" || \
  _bash_god_install_die "helper cannot run on $_bash_god_install_platform"
[ "$_bash_god_install_helper_protocol" = "$_bash_god_install_protocol" ] || \
  _bash_god_install_die 'helper protocol does not match the shell runtime.'

_bash_god_install_bin_dir="$_bash_god_install_prefix/bin"
_bash_god_install_lib_parent="$_bash_god_install_prefix/lib"
_bash_god_install_runtime="$_bash_god_install_lib_parent/bash-god"
_bash_god_install_runtime_target=$_bash_god_install_runtime
_bash_god_install_libexec_parent="$_bash_god_install_prefix/libexec"
_bash_god_install_helper="$_bash_god_install_libexec_parent/bash-god"
_bash_god_install_helper_target=$_bash_god_install_helper
_bash_god_install_license_dir="$_bash_god_install_prefix/share/licenses/bash-god"
_bash_god_install_metadata_dir="$_bash_god_install_prefix/share/bash-god"
_bash_god_install_manifest="$_bash_god_install_metadata_dir/install-manifest"
_bash_god_install_launcher="$_bash_god_install_bin_dir/god"
_bash_god_install_prefix_physical=''

if [ -L "$_bash_god_install_launcher" ]; then
  _bash_god_install_die "refusing to replace a symlinked launcher: $_bash_god_install_launcher"
fi
if [ -e "$_bash_god_install_launcher" ]; then
  [ -f "$_bash_god_install_launcher" ] && \
    LC_ALL=C grep -q '^# Real-file launcher installed at PREFIX/bin/god by the runtime package\.$' \
      "$_bash_god_install_launcher" || \
    _bash_god_install_die "refusing to replace an unmanaged launcher: $_bash_god_install_launcher"
fi
if [ -L "$_bash_god_install_runtime" ]; then
  _bash_god_install_die "refusing to replace a symlinked runtime: $_bash_god_install_runtime"
fi
if [ -e "$_bash_god_install_runtime" ]; then
  [ "$_bash_god_install_replace" -eq 1 ] || \
    _bash_god_install_die "runtime already exists; review it, then rerun with --replace: $_bash_god_install_runtime"
  _bash_god_install_prefix_physical="$(CDPATH= cd "$_bash_god_install_prefix" 2>/dev/null && pwd -P)" || \
    _bash_god_install_die 'could not resolve the physical installation prefix.'
  if [ -x "$_bash_god_install_runtime/god" ] && [ -r "$_bash_god_install_runtime/src/core.sh" ]; then
    :
  elif _bash_god_install_legacy_runtime_is_managed "$_bash_god_install_runtime"; then
    :
  else
    _bash_god_install_die "refusing to replace an unmanaged runtime: $_bash_god_install_runtime"
  fi
fi
if [ -L "$_bash_god_install_libexec_parent" ] || [ -L "$_bash_god_install_helper" ]; then
  _bash_god_install_die "refusing to write through a symlinked helper path: $_bash_god_install_helper"
fi
if [ -e "$_bash_god_install_helper" ]; then
  [ -d "$_bash_god_install_helper" ] && [ -x "$_bash_god_install_helper/god-tui" ] || \
    _bash_god_install_die "refusing to replace an unmanaged helper: $_bash_god_install_helper"
  [ -e "$_bash_god_install_runtime" ] || \
    _bash_god_install_die "helper exists without a managed runtime: $_bash_god_install_helper"
fi
if [ -L "$_bash_god_install_license_dir" ] || [ -L "$_bash_god_install_license_dir/LICENSE" ] || \
   [ -L "$_bash_god_install_license_dir/THIRD_PARTY_NOTICES.md" ]; then
  _bash_god_install_die "refusing to write through a symlinked license path: $_bash_god_install_license_dir"
fi
if [ -L "$_bash_god_install_metadata_dir" ] || [ -L "$_bash_god_install_manifest" ]; then
  _bash_god_install_die "refusing to write through a symlinked metadata path: $_bash_god_install_metadata_dir"
fi

mkdir -p "$_bash_god_install_bin_dir" "$_bash_god_install_lib_parent" \
  "$_bash_god_install_libexec_parent" "$_bash_god_install_license_dir" "$_bash_god_install_metadata_dir"
if [ -z "$_bash_god_install_prefix_physical" ]; then
  _bash_god_install_prefix_physical="$(CDPATH= cd "$_bash_god_install_prefix" 2>/dev/null && pwd -P)" || \
    _bash_god_install_die 'could not resolve the physical installation prefix.'
fi
_bash_god_install_new_runtime="$(mktemp -d "$_bash_god_install_lib_parent/.bash-god.new.XXXXXX")" || \
  _bash_god_install_die 'could not create a private runtime staging directory.'
cp -R "$_bash_god_install_root/lib/bash-god/." "$_bash_god_install_new_runtime/"
printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=%s\nprotocol=%s\n' \
  "$_bash_god_install_version" "$_bash_god_install_platform" "$_bash_god_install_protocol" > \
  "$_bash_god_install_new_runtime/tui-manifest"
chmod 0755 "$_bash_god_install_new_runtime" "$_bash_god_install_new_runtime/god"
GOD_COLOR=never "$_bash_god_install_new_runtime/god" --version >/dev/null || \
  _bash_god_install_die 'copied runtime failed its version check.'

_bash_god_install_new_helper="$(mktemp -d "$_bash_god_install_libexec_parent/.bash-god.new.XXXXXX")" || \
  _bash_god_install_die 'could not create a private helper staging directory.'
cp "$_bash_god_install_helper_source" "$_bash_god_install_new_helper/god-tui"
chmod 0755 "$_bash_god_install_new_helper/god-tui"
[ "$("$_bash_god_install_new_helper/god-tui" --protocol-version 2>/dev/null)" = "$_bash_god_install_protocol" ] || \
  _bash_god_install_die 'copied helper protocol does not match the shell runtime.'

_bash_god_install_new_launcher="$(mktemp "$_bash_god_install_bin_dir/.god.new.XXXXXX")" || \
  _bash_god_install_die 'could not create a private launcher staging file.'
cp "$_bash_god_install_root/bin/god" "$_bash_god_install_new_launcher"
chmod 0755 "$_bash_god_install_new_launcher"

_bash_god_install_new_manifest="$(mktemp "$_bash_god_install_metadata_dir/.install-manifest.new.XXXXXX")" || \
  _bash_god_install_die 'could not create a private install manifest.'
printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s\n' \
  "$_bash_god_install_prefix_physical" "$_bash_god_install_version" > "$_bash_god_install_new_manifest"
chmod 0644 "$_bash_god_install_new_manifest"

if [ -e "$_bash_god_install_runtime" ]; then
  _bash_god_install_old_version="$(GOD_COLOR=never "$_bash_god_install_runtime/god" --version 2>/dev/null | LC_ALL=C awk 'NR == 1 { print $2 }')"
  case "$_bash_god_install_old_version" in
    ''|*[!0-9.]*) _bash_god_install_old_version=unknown ;;
  esac
  _bash_god_install_backup="$(mktemp -d "$_bash_god_install_lib_parent/bash-god.backup-$_bash_god_install_old_version.XXXXXX")" || \
    _bash_god_install_die 'could not create a private backup directory.'
  _bash_god_install_backup_runtime="$_bash_god_install_backup/runtime"
  _bash_god_install_backup_helper="$_bash_god_install_backup/helper"
  mv "$_bash_god_install_runtime" "$_bash_god_install_backup_runtime"
  if [ -e "$_bash_god_install_helper" ]; then
    mv "$_bash_god_install_helper" "$_bash_god_install_backup_helper"
  else
    _bash_god_install_backup_helper=''
  fi
fi
if ! mv "$_bash_god_install_new_runtime" "$_bash_god_install_runtime"; then
  _bash_god_install_die 'could not activate the staged runtime.'
fi
_bash_god_install_new_runtime=''
_bash_god_install_activated_runtime=1
if ! mv "$_bash_god_install_new_helper" "$_bash_god_install_helper"; then
  _bash_god_install_die 'could not activate the staged helper.'
fi
_bash_god_install_new_helper=''
_bash_god_install_activated_helper=1
mv -f "$_bash_god_install_new_launcher" "$_bash_god_install_launcher"
_bash_god_install_new_launcher=''
cp "$_bash_god_install_root/share/licenses/bash-god/LICENSE" "$_bash_god_install_license_dir/LICENSE"
cp "$_bash_god_install_root/share/licenses/bash-god/THIRD_PARTY_NOTICES.md" \
  "$_bash_god_install_license_dir/THIRD_PARTY_NOTICES.md"
mv -f "$_bash_god_install_new_manifest" "$_bash_god_install_manifest"
_bash_god_install_new_manifest=''

GOD_COLOR=never "$_bash_god_install_launcher" --version >/dev/null || \
  _bash_god_install_die 'installed CLI failed its final version check.'
[ "$("$_bash_god_install_helper/god-tui" --protocol-version 2>/dev/null)" = "$_bash_god_install_protocol" ] || \
  _bash_god_install_die 'installed helper protocol does not match the shell runtime.'
_bash_god_install_complete=1

# Best-effort discovery for every service that declares @discover, so the
# common case needs no separate `god SERVICE --resync` before it can execute.
# The opt-out exists for offline/package-fixture environments only: it keeps a
# staging test from accidentally probing a client installed on its host.
if [ "${BASH_GOD_SKIP_INITIAL_RESYNC:-0}" != 1 ]; then
  for _bash_god_install_catalog in "$_bash_god_install_runtime/catalog"/*/service.god; do
    [ -f "$_bash_god_install_catalog" ] || continue
    if LC_ALL=C grep -q '^@discover$' "$_bash_god_install_catalog" 2>/dev/null; then
      _bash_god_install_discover_service="${_bash_god_install_catalog%/service.god}"
      _bash_god_install_discover_service="${_bash_god_install_discover_service##*/}"
      GOD_COLOR=never "$_bash_god_install_launcher" "$_bash_god_install_discover_service" --resync >/dev/null 2>&1 || true
    fi
  done
fi

printf 'Installed BASH_GOD %s for %s\n' "$_bash_god_install_version" "$_bash_god_install_platform"
printf 'Command: %s\n' "$_bash_god_install_launcher"
if [ -n "$_bash_god_install_backup" ]; then
  printf 'Previous runtime retained at: %s\n' "$_bash_god_install_backup"
fi
case ":${PATH:-}:" in
  *":$_bash_god_install_bin_dir:"*) ;;
  *) printf 'Add this directory to PATH: export PATH="%s:$PATH"\n' "$_bash_god_install_bin_dir" ;;
esac
