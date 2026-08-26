#!/usr/bin/env bash

# BASH_GOD self-maintenance. This file is executed in a dedicated Bash process;
# catalog command records remain inert and are never evaluated here.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_god_maintenance_repository='hemang11/BASH-GOD'
_god_maintenance_download_dir=''

_god_maintenance_die() {
  printf 'BASH_GOD maintenance: %s\n' "$1" >&2
  exit 1
}

_god_maintenance_cleanup() {
  if [ -n "$_god_maintenance_download_dir" ] && [ -d "$_god_maintenance_download_dir" ]; then
    command rm -rf -- "$_god_maintenance_download_dir"
  fi
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

_god_maintenance_menu() {
  local first second selected marker key rest

  first=$1
  second=$2
  selected=${3:-0}
  marker='>'
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*UTF8*) marker='❯' ;;
  esac

  if ! _god_maintenance_has_tty; then
    printf 'An interactive terminal is required; nothing was changed.\n' >&2
    _god_maintenance_menu_choice=0
    return 0
  fi

  if [ "${TERM:-}" = dumb ]; then
    if [ "$selected" -eq 0 ]; then
      printf '%s [Y/n] ' "$first"
      IFS= read -r key || key=n
      case "$key" in ''|y|Y|yes|YES|Yes) _god_maintenance_menu_choice=0 ;; *) _god_maintenance_menu_choice=1 ;; esac
    else
      printf '%s [y/N] ' "$second"
      IFS= read -r key || key=n
      case "$key" in y|Y|yes|YES|Yes) _god_maintenance_menu_choice=1 ;; *) _god_maintenance_menu_choice=0 ;; esac
    fi
    return 0
  fi

  printf '\n'
  while :; do
    if [ "$selected" -eq 0 ]; then
      printf '\r\033[2K  %s %s\n\r\033[2K    %s\n' "$marker" "$first" "$second"
    else
      printf '\r\033[2K    %s\n\r\033[2K  %s %s\n' "$first" "$marker" "$second"
    fi
    IFS= read -r -s -n 1 key || {
      _god_maintenance_menu_choice=0
      printf '\n'
      return 0
    }
    case "$key" in
      '')
        _god_maintenance_menu_choice=$selected
        printf '\n'
        return 0
        ;;
      k|K) selected=0 ;;
      j|J) selected=1 ;;
      "$(printf '\033')")
        IFS= read -r -s -n 2 rest || rest=''
        case "$rest" in
          '[A') selected=0 ;;
          '[B') selected=1 ;;
        esac
        ;;
      *) continue ;;
    esac
    printf '\033[2A'
  done
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

  printf '\nBASH_GOD %s is available; you have %s.\n' "$latest" "$current"
  _god_maintenance_menu "Update to $latest" 'Not now' 0
  if [ "$_god_maintenance_menu_choice" -ne 0 ]; then
    _god_maintenance_defer_check "$(_god_maintenance_cache_ttl)"
    return 0
  fi
  _god_maintenance_install_update "$latest"
  _god_maintenance_defer_check "$(_god_maintenance_cache_ttl)"
  printf '\nBASH_GOD was updated to %s. Run god again to load the new version.\n' "$latest"
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

  printf '\nThis permanently removes BASH_GOD %s and all BASH_GOD-owned data.\n\n' "$current"
  printf '  %s\n' "$_god_maintenance_launcher"
  printf '  %s\n' "$_god_maintenance_runtime"
  printf '  %s\n' "$_god_maintenance_prefix/lib/bash-god.backup-*"
  printf '  %s\n' "$_god_maintenance_license_dir"
  printf '  %s\n' "$_god_maintenance_metadata_dir"
  printf '  %s\n' "$_god_maintenance_config_dir"
  printf '  %s\n' "$_god_maintenance_cache_dir"
  printf '  %s\n' "$_god_maintenance_state_dir"
  if [ "$_god_maintenance_data_dir" != "$_god_maintenance_metadata_dir" ]; then
    printf '  %s\n' "$_god_maintenance_data_dir"
  fi

  _god_maintenance_menu 'Cancel' 'Uninstall everything' 0
  if [ "$_god_maintenance_menu_choice" -ne 1 ]; then
    printf 'Uninstall cancelled. Nothing was changed.\n'
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
  printf '\nBASH_GOD was completely removed.\n'
}

_god_maintenance_main() {
  local action current status

  action=${1:-}
  current=${2:-}
  _god_maintenance_version_is_valid "$current" || _god_maintenance_die 'current version is invalid'
  _god_maintenance_init_paths
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
