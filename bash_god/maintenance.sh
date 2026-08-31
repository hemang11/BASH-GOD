#!/usr/bin/env bash

# BASH_GOD self-maintenance. This file is executed in a dedicated Bash process;
# catalog command records remain inert and are never evaluated here.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_god_maintenance_repository='hemang11/BASH-GOD'
_god_maintenance_download_dir=''

# The interactive picker is shared with the catalog search views.
_god_maintenance_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || \
  _god_maintenance_dir=''
if [ -n "$_god_maintenance_dir" ] && [ -r "$_god_maintenance_dir/menu.sh" ]; then
  # shellcheck source=menu.sh
  . "$_god_maintenance_dir/menu.sh" || exit 1
fi

_god_maintenance_die() {
  printf 'BASH_GOD maintenance: %s\n' "$1" >&2
  exit 1
}

_god_maintenance_cleanup() {
  if [ -n "$_god_maintenance_download_dir" ] && [ -d "$_god_maintenance_download_dir" ]; then
    command rm -rf -- "$_god_maintenance_download_dir"
  fi
}

_god_maintenance_style_init() {
  local locale_name color_mode

  locale_name="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  color_mode="${GOD_COLOR:-auto}"

  case "$locale_name" in
    *UTF-8*|*UTF8*|*utf-8*|*utf8*)
      _god_style_top_left='╭'
      _god_style_top_right='╮'
      _god_style_bottom_left='╰'
      _god_style_bottom_right='╯'
      _god_style_vertical='│'
      _god_style_horizontal='─'
      _god_style_bullet='•'
      _god_style_marker='❯'
      _god_style_keys='↑/↓ or j/k to move · enter to confirm'
      ;;
    *)
      _god_style_top_left='+'
      _god_style_top_right='+'
      _god_style_bottom_left='+'
      _god_style_bottom_right='+'
      _god_style_vertical='|'
      _god_style_horizontal='-'
      _god_style_bullet='-'
      _god_style_marker='>'
      _god_style_keys='up/down or j/k to move, enter to confirm'
      ;;
  esac

  _god_style_reset=''
  _god_style_bold=''
  _god_style_dim=''
  _god_style_brand=''
  _god_style_accent=''
  _god_style_warning=''

  if [ -z "${NO_COLOR+x}" ]; then
    if [ "$color_mode" = always ] || {
      [ "$color_mode" != never ] &&
      [ "${TERM:-}" != dumb ] &&
      [ -t 1 ]
    }; then
      _god_style_reset="$(printf '\033[0m')"
      _god_style_bold="$(printf '\033[1m')"
      _god_style_dim="$(printf '\033[2m')"
      _god_style_brand="$(printf '\033[1;35m')"
      _god_style_accent="$(printf '\033[1;36m')"
      _god_style_warning="$(printf '\033[1;33m')"
    fi
  fi
}

_god_maintenance_repeat() {
  local character count output

  character=$1
  count=$2
  output=''
  while [ "$count" -gt 0 ]; do
    output="${output}${character}"
    count=$((count - 1))
  done
  printf '%s' "$output"
}

_god_maintenance_banner() {
  local title subtitle

  title=$1
  subtitle=$2

  printf '\n%s%s' "$_god_style_brand" "$_god_style_top_left"
  _god_maintenance_repeat "$_god_style_horizontal" 72
  printf '%s%s\n' "$_god_style_top_right" "$_god_style_reset"
  printf '%s%s%s %-70.70s %s%s\n' "$_god_style_brand" "$_god_style_vertical" \
    "$_god_style_reset$_god_style_bold" "$title" "$_god_style_brand$_god_style_vertical" "$_god_style_reset"
  if [ -n "$subtitle" ]; then
    printf '%s%s%s %-70.70s %s%s\n' "$_god_style_brand" "$_god_style_vertical" \
      "$_god_style_reset$_god_style_dim" "$subtitle" "$_god_style_brand$_god_style_vertical" "$_god_style_reset"
  fi
  printf '%s%s' "$_god_style_brand" "$_god_style_bottom_left"
  _god_maintenance_repeat "$_god_style_horizontal" 72
  printf '%s%s\n' "$_god_style_bottom_right" "$_god_style_reset"
}

_god_maintenance_section() {
  printf '\n%s%s%s\n\n' "$_god_style_bold" "$1" "$_god_style_reset"
}

_god_maintenance_path_row() {
  printf '  %s%s%s %s\n' "$_god_style_dim" "$_god_style_bullet" "$_god_style_reset" "$1"
}

_god_maintenance_version_is_valid() {
  case "$1" in
    ''|.*|*.|*..*|*[!0-9.]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Prints -1 when LEFT is older, 0 when equal, and 1 when LEFT is newer.
_god_maintenance_compare_versions() {
  local left right left_component right_component

  left=$1
  right=$2
  while [ -n "$left" ] || [ -n "$right" ]; do
    case "$left" in
      *.*) left_component=${left%%.*}; left=${left#*.} ;;
      '') left_component=0 ;;
      *) left_component=$left; left='' ;;
    esac
    case "$right" in
      *.*) right_component=${right%%.*}; right=${right#*.} ;;
      '') right_component=0 ;;
      *) right_component=$right; right='' ;;
    esac

    while [ "${left_component#0}" != "$left_component" ]; do
      left_component=${left_component#0}
    done
    while [ "${right_component#0}" != "$right_component" ]; do
      right_component=${right_component#0}
    done
    left_component=${left_component:-0}
    right_component=${right_component:-0}

    if [ "${#left_component}" -lt "${#right_component}" ]; then
      printf '%s\n' -1
      return 0
    fi
    if [ "${#left_component}" -gt "${#right_component}" ]; then
      printf '%s\n' 1
      return 0
    fi
    if [[ "$left_component" < "$right_component" ]]; then
      printf '%s\n' -1
      return 0
    fi
    if [[ "$left_component" > "$right_component" ]]; then
      printf '%s\n' 1
      return 0
    fi
  done
  printf '%s\n' 0
}

_god_maintenance_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  else
    _god_maintenance_die 'sha256sum or shasum is required to install an update'
  fi
}

_god_maintenance_verify() {
  local file checksum name expected actual

  file=$1
  checksum=$2
  name=${file##*/}
  if ! expected="$(LC_ALL=C awk -v file="$name" '
    $2 == file || $2 == "*" file { count++; hash = $1; fields = NF }
    END { if (count == 1 && fields == 2) print hash; else exit 1 }
  ' "$checksum")"; then
    _god_maintenance_die "invalid checksum file for $name"
  fi
  case "$expected" in
    ''|*[!0-9A-Fa-f]*) _god_maintenance_die "invalid SHA-256 value for $name" ;;
  esac
  [ "${#expected}" -eq 64 ] || _god_maintenance_die "invalid SHA-256 length for $name"
  actual="$(_god_maintenance_sha256 "$file")"
  expected="$(printf '%s' "$expected" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  actual="$(printf '%s' "$actual" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [ "$expected" = "$actual" ] || _god_maintenance_die "SHA-256 verification failed for $name"
}

_god_maintenance_fetch_latest_version() {
  local effective tag version

  command -v curl >/dev/null 2>&1 || return 1
  effective="$(curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 2 --max-time 5 \
    -o /dev/null -w '%{url_effective}' \
    "https://github.com/${_god_maintenance_repository}/releases/latest" 2>/dev/null)" || return 1
  effective=${effective%/}
  tag=${effective##*/}
  case "$tag" in
    v[0-9]*) version=${tag#v} ;;
    *) return 1 ;;
  esac
  _god_maintenance_version_is_valid "$version" || return 1
  [ "$effective" = "https://github.com/${_god_maintenance_repository}/releases/tag/$tag" ] || return 1
  printf '%s\n' "$version"
}

_god_maintenance_xdg_dir() {
  local configured fallback

  configured=$1
  fallback=$2
  case "$configured" in
    /) _god_maintenance_die 'an XDG base directory cannot be the filesystem root' ;;
    /*) printf '%s/bash-god\n' "${configured%/}" ;;
    *) printf '%s/%s/bash-god\n' "$HOME" "$fallback" ;;
  esac
}

_god_maintenance_init_paths() {
  local file dir runtime lib_parent

  [ -n "${HOME:-}" ] || _god_maintenance_die 'HOME is unavailable'
  file=${BASH_SOURCE[0]}
  dir="$(CDPATH= cd "$(dirname "$file")" 2>/dev/null && pwd -P)" || \
    _god_maintenance_die 'cannot resolve the maintenance module directory'
  runtime="$(CDPATH= cd "$dir/.." 2>/dev/null && pwd -P)" || \
    _god_maintenance_die 'cannot resolve the runtime directory'
  lib_parent="$(CDPATH= cd "$runtime/.." 2>/dev/null && pwd -P)" || \
    _god_maintenance_die 'cannot resolve the runtime parent directory'
  _god_maintenance_prefix="$(CDPATH= cd "$lib_parent/.." 2>/dev/null && pwd -P)" || \
    _god_maintenance_die 'cannot resolve the installation prefix'
  _god_maintenance_runtime=$runtime
  _god_maintenance_launcher="$_god_maintenance_prefix/bin/god"
  _god_maintenance_license_dir="$_god_maintenance_prefix/share/licenses/bash-god"
  _god_maintenance_metadata_dir="$_god_maintenance_prefix/share/bash-god"
  _god_maintenance_manifest="$_god_maintenance_metadata_dir/install-manifest"
  _god_maintenance_config_dir="$(_god_maintenance_xdg_dir "${XDG_CONFIG_HOME:-}" '.config')"
  _god_maintenance_cache_dir="$(_god_maintenance_xdg_dir "${XDG_CACHE_HOME:-}" '.cache')"
  _god_maintenance_state_dir="$(_god_maintenance_xdg_dir "${XDG_STATE_HOME:-}" '.local/state')"
  _god_maintenance_data_dir="$(_god_maintenance_xdg_dir "${XDG_DATA_HOME:-}" '.local/share')"
  _god_maintenance_next_check="$_god_maintenance_cache_dir/next-update-check"
}

_god_maintenance_is_managed() {
  local current_version expected_manifest actual_manifest

  current_version=$1
  expected_manifest="$(printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s' \
    "$_god_maintenance_prefix" "$current_version")"
  actual_manifest=''
  if [ ! -L "$_god_maintenance_manifest" ] && [ -f "$_god_maintenance_manifest" ]; then
    actual_manifest="$(command cat "$_god_maintenance_manifest" 2>/dev/null)" || return 1
  fi
  [ ! -L "$_god_maintenance_launcher" ] &&
    [ -f "$_god_maintenance_launcher" ] &&
    [ -x "$_god_maintenance_launcher" ] &&
    LC_ALL=C grep -Fqx '# Real-file launcher installed at PREFIX/bin/god by the runtime package.' \
      "$_god_maintenance_launcher" &&
    [ ! -L "$_god_maintenance_runtime" ] &&
    [ -d "$_god_maintenance_runtime" ] &&
    [ "$actual_manifest" = "$expected_manifest" ]
}

_god_maintenance_cache_ttl() {
  local ttl

  ttl=${GOD_UPDATE_CHECK_TTL:-86400}
  case "$ttl" in
    ''|*[!0-9]*) ttl=86400 ;;
  esac
  printf '%s\n' "$ttl"
}

_god_maintenance_cache_is_fresh() {
  local now next

  [ -f "$_god_maintenance_next_check" ] && [ ! -L "$_god_maintenance_next_check" ] || return 1
  IFS= read -r next < "$_god_maintenance_next_check" || return 1
  case "$next" in
    ''|*[!0-9]*) return 1 ;;
  esac
  now=$(date +%s) || return 1
  [ "$now" -lt "$next" ]
}

_god_maintenance_defer_check() {
  local delay now next temporary

  delay=$1
  now=$(date +%s) || return 0
  next=$((now + delay))
  if [ -L "$_god_maintenance_cache_dir" ]; then
    return 0
  fi
  mkdir -p "$_god_maintenance_cache_dir" 2>/dev/null || return 0
  temporary="$(mktemp "$_god_maintenance_cache_dir/.next-update-check.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$next" > "$temporary"
  chmod 0600 "$temporary" 2>/dev/null || true
  mv -f "$temporary" "$_god_maintenance_next_check" 2>/dev/null || command rm -f -- "$temporary"
}

_god_maintenance_has_tty() {
  [ -t 0 ] && [ -t 1 ]
}

# Two-choice wrapper over the shared picker. The name is part of the test
# surface: packaging/tests/maintenance-smoke.sh stubs this exact function.
_god_maintenance_menu() {
  local first first_hint second second_hint selected danger rows tab

  first=$1
  first_hint=$2
  second=$3
  second_hint=$4
  selected=${5:-0}
  danger=${6:-0}

  tab="$(printf '\t')"
  rows="${first}${tab}${first_hint}${tab}"
  rows="${rows}
${second}${tab}${second_hint}${tab}"
  [ "$danger" -eq 1 ] && rows="${rows}danger"

  _god_menu_style_init
  if ! _god_menu_select "$rows" "$((selected + 1))"; then
    printf 'An interactive terminal is required; nothing was changed.\n' >&2
    _god_maintenance_menu_choice=0
    return 0
  fi

  if [ "$_god_menu_choice" -lt 0 ]; then
    _god_maintenance_menu_choice=0
  else
    _god_maintenance_menu_choice=$_god_menu_choice
  fi
  return 0
}

_god_maintenance_download() {
  local url target

  url=$1
  target=$2
  printf 'Downloading %s\n' "${url##*/}"
  curl --fail --show-error --location --retry 3 \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 120 \
    -o "$target" "$url"
}

_god_maintenance_install_update() {
  local version release_url archive archive_checksum installer installer_checksum dependency

  version=$1
  for dependency in curl tar mktemp awk tr chmod rm; do
    command -v "$dependency" >/dev/null 2>&1 || \
      _god_maintenance_die "$dependency is required to update BASH_GOD"
  done
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || \
    _god_maintenance_die 'sha256sum or shasum is required to update BASH_GOD'

  _god_maintenance_download_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-update.XXXXXX")" || \
    _god_maintenance_die 'could not create a private update directory'
  chmod 0700 "$_god_maintenance_download_dir"
  release_url="https://github.com/${_god_maintenance_repository}/releases/download/v${version}"
  archive="$_god_maintenance_download_dir/bash-god-${version}.tar.gz"
  archive_checksum="${archive}.sha256"
  installer="$_god_maintenance_download_dir/install-runtime.sh"
  installer_checksum="${installer}.sha256"

  _god_maintenance_download "$release_url/bash-god-${version}.tar.gz" "$archive"
  _god_maintenance_download "$release_url/bash-god-${version}.tar.gz.sha256" "$archive_checksum"
  _god_maintenance_download "$release_url/install-runtime.sh" "$installer"
  _god_maintenance_download "$release_url/install-runtime.sh.sha256" "$installer_checksum"
  _god_maintenance_verify "$installer" "$installer_checksum"
  _god_maintenance_verify "$archive" "$archive_checksum"
  printf 'Checksums verified.\n'
  chmod 0700 "$installer"
  "$installer" --replace --prefix "$_god_maintenance_prefix" "$archive" "$archive_checksum"
}

_god_maintenance_check() {
  local current latest relation

  current=$1
  [ "${GOD_NO_UPDATE_CHECK:-0}" != 1 ] || return 0
  _god_maintenance_is_managed "$current" || return 0
  _god_maintenance_cache_is_fresh && return 0
  if ! latest="$(_god_maintenance_fetch_latest_version)"; then
    _god_maintenance_defer_check 3600
    return 0
  fi
  relation="$(_god_maintenance_compare_versions "$current" "$latest")"
  if [ "$relation" != -1 ]; then
    _god_maintenance_defer_check "$(_god_maintenance_cache_ttl)"
    return 0
  fi

  _god_maintenance_banner 'UPDATE AVAILABLE' \
    "$(printf 'BASH_GOD %s is available; you have %s.' "$latest" "$current")"
  _god_maintenance_menu \
    "Update to $latest" 'Download, verify checksums, and replace the runtime' \
    'Not now' "Keep $current and ask again later" 0
  if [ "$_god_maintenance_menu_choice" -ne 0 ]; then
    _god_maintenance_defer_check "$(_god_maintenance_cache_ttl)"
    return 0
  fi
  _god_maintenance_install_update "$latest"
  _god_maintenance_defer_check "$(_god_maintenance_cache_ttl)"
  printf '\n%sBASH_GOD was updated to %s.%s %sRun god again to load the new version.%s\n' \
    "$_god_style_bold" "$latest" "$_god_style_reset" "$_god_style_dim" "$_god_style_reset"
  return 10
}

_god_maintenance_safe_owned_dir() {
  case "$1" in
    /*/bash-god) return 0 ;;
    *) return 1 ;;
  esac
}

_god_maintenance_remove_dir() {
  local target

  target=$1
  [ -e "$target" ] || [ -L "$target" ] || return 0
  _god_maintenance_safe_owned_dir "$target" || \
    _god_maintenance_die "refusing unsafe purge target: $target"
  command rm -rf -- "$target"
}

_god_maintenance_remove_backups() {
  local backup

  [ -d "$_god_maintenance_prefix/lib" ] || return 0
  while IFS= read -r backup; do
    [ -n "$backup" ] || continue
    case "$backup" in
      "$_god_maintenance_prefix"/lib/bash-god.backup-*) command rm -rf -- "$backup" ;;
      *) _god_maintenance_die "refusing unsafe backup purge target: $backup" ;;
    esac
  done <<EOF
$(command find "$_god_maintenance_prefix/lib" -mindepth 1 -maxdepth 1 -type d -name 'bash-god.backup-*' -print 2>/dev/null)
EOF
}

_god_maintenance_uninstall() {
  local current

  current=$1
  if ! _god_maintenance_is_managed "$current"; then
    printf 'BASH_GOD: this is not a managed GitHub Release installation.\n' >&2
    printf 'Use the owning package manager, or remove a sourced development checkout manually.\n' >&2
    return 2
  fi

  _god_maintenance_banner "$(printf 'REMOVE BASH_GOD %s' "$current")" \
    'Permanently deletes the launcher, runtime, and every path below.'
  _god_maintenance_section 'PATHS TO REMOVE'
  _god_maintenance_path_row "$_god_maintenance_launcher"
  _god_maintenance_path_row "$_god_maintenance_runtime"
  _god_maintenance_path_row "$_god_maintenance_prefix/lib/bash-god.backup-*"
  _god_maintenance_path_row "$_god_maintenance_license_dir"
  _god_maintenance_path_row "$_god_maintenance_metadata_dir"
  _god_maintenance_path_row "$_god_maintenance_config_dir"
  _god_maintenance_path_row "$_god_maintenance_cache_dir"
  _god_maintenance_path_row "$_god_maintenance_state_dir"
  if [ "$_god_maintenance_data_dir" != "$_god_maintenance_metadata_dir" ]; then
    _god_maintenance_path_row "$_god_maintenance_data_dir"
  fi

  _god_maintenance_menu \
    'Cancel' 'Leave this installation exactly as it is' \
    'Uninstall everything' 'Delete every path listed above' 0 1
  if [ "$_god_maintenance_menu_choice" -ne 1 ]; then
    printf '%sUninstall cancelled. Nothing was changed.%s\n' "$_god_style_dim" "$_god_style_reset"
    return 0
  fi

  _god_maintenance_remove_dir "$_god_maintenance_config_dir"
  _god_maintenance_remove_dir "$_god_maintenance_cache_dir"
  _god_maintenance_remove_dir "$_god_maintenance_state_dir"
  if [ "$_god_maintenance_data_dir" != "$_god_maintenance_metadata_dir" ]; then
    _god_maintenance_remove_dir "$_god_maintenance_data_dir"
  fi
  _god_maintenance_remove_backups
  _god_maintenance_remove_dir "$_god_maintenance_license_dir"
  _god_maintenance_remove_dir "$_god_maintenance_metadata_dir"
  command rm -f -- "$_god_maintenance_launcher"
  _god_maintenance_remove_dir "$_god_maintenance_runtime"

  rmdir "$_god_maintenance_prefix/share/licenses" 2>/dev/null || true
  rmdir "$_god_maintenance_prefix/share" 2>/dev/null || true
  rmdir "$_god_maintenance_prefix/bin" 2>/dev/null || true
  rmdir "$_god_maintenance_prefix/lib" 2>/dev/null || true
  rmdir "$_god_maintenance_prefix" 2>/dev/null || true
  printf '\n%sBASH_GOD was completely removed.%s\n' "$_god_style_bold" "$_god_style_reset"
}

_god_maintenance_main() {
  local action current status

  action=${1:-}
  current=${2:-}
  _god_maintenance_version_is_valid "$current" || _god_maintenance_die 'current version is invalid'
  _god_maintenance_init_paths
  _god_maintenance_style_init
  trap '_god_maintenance_cleanup' EXIT
  trap 'exit 130' HUP INT TERM
  case "$action" in
    check)
      _god_maintenance_check "$current"
      status=$?
      return "$status"
      ;;
    uninstall) _god_maintenance_uninstall "$current" ;;
    *) _god_maintenance_die 'internal usage: maintenance.sh check|uninstall VERSION' ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _god_maintenance_main "$@"
fi
