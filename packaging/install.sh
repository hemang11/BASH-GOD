#!/usr/bin/env bash

# Public BASH_GOD bootstrap. It installs the latest verified GitHub Release;
# future updates and complete removal are owned by the installed `god` command.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  printf 'BASH_GOD install: execute install.sh with Bash; do not source it.\n' >&2
  return 1
fi

set -o errexit
set -o nounset
set -o pipefail

_bash_god_bootstrap_repository='hemang11/BASH-GOD'
_bash_god_bootstrap_download_dir=''

_bash_god_bootstrap_die() {
  printf 'BASH_GOD install: %s\n' "$1" >&2
  exit 1
}

_bash_god_bootstrap_usage() {
  printf 'Usage: %s [--prefix PREFIX]\n' "$0"
  printf '\nInstalls the latest BASH_GOD GitHub Release.\n'
  printf 'The default managed prefix is $HOME/.local.\n'
  printf 'After installation, bare `god` checks periodically for updates and\n'
  printf '`god --uninstall` completely removes a managed installation.\n'
}

_bash_god_bootstrap_cleanup() {
  if [ -n "$_bash_god_bootstrap_download_dir" ] && [ -d "$_bash_god_bootstrap_download_dir" ]; then
    command rm -rf -- "$_bash_god_bootstrap_download_dir"
  fi
}

_bash_god_bootstrap_version_is_valid() {
  case "$1" in
    ''|.*|*.|*..*|*[!0-9.]*) return 1 ;;
    *) return 0 ;;
  esac
}

_bash_god_bootstrap_compare_versions() {
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
    while [ "${left_component#0}" != "$left_component" ]; do left_component=${left_component#0}; done
    while [ "${right_component#0}" != "$right_component" ]; do right_component=${right_component#0}; done
    left_component=${left_component:-0}
    right_component=${right_component:-0}
    if [ "${#left_component}" -lt "${#right_component}" ]; then printf '%s\n' -1; return 0; fi
    if [ "${#left_component}" -gt "${#right_component}" ]; then printf '%s\n' 1; return 0; fi
    if [[ "$left_component" < "$right_component" ]]; then printf '%s\n' -1; return 0; fi
    if [[ "$left_component" > "$right_component" ]]; then printf '%s\n' 1; return 0; fi
  done
  printf '%s\n' 0
}

_bash_god_bootstrap_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  else
    _bash_god_bootstrap_die 'sha256sum or shasum is required to verify release assets'
  fi
}

_bash_god_bootstrap_verify() {
  local file checksum name expected actual

  file=$1
  checksum=$2
  name=${file##*/}
  if ! expected="$(LC_ALL=C awk -v file="$name" '
    $2 == file || $2 == "*" file { count++; hash = $1; fields = NF }
    END { if (count == 1 && fields == 2) print hash; else exit 1 }
  ' "$checksum")"; then
    _bash_god_bootstrap_die "invalid checksum file for $name"
  fi
  case "$expected" in
    ''|*[!0-9A-Fa-f]*) _bash_god_bootstrap_die "invalid SHA-256 value for $name" ;;
  esac
  [ "${#expected}" -eq 64 ] || _bash_god_bootstrap_die "invalid SHA-256 length for $name"
  actual="$(_bash_god_bootstrap_sha256 "$file")"
  expected="$(printf '%s' "$expected" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  actual="$(printf '%s' "$actual" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [ "$expected" = "$actual" ] || _bash_god_bootstrap_die "SHA-256 verification failed for $name"
}

_bash_god_bootstrap_fetch_latest_version() {
  local effective tag version

  effective="$(curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 20 \
    -o /dev/null -w '%{url_effective}' \
    "https://github.com/${_bash_god_bootstrap_repository}/releases/latest" 2>/dev/null)" || return 1
  effective=${effective%/}
  tag=${effective##*/}
  case "$tag" in
    v[0-9]*) version=${tag#v} ;;
    *) return 1 ;;
  esac
  _bash_god_bootstrap_version_is_valid "$version" || return 1
  [ "$effective" = "https://github.com/${_bash_god_bootstrap_repository}/releases/tag/$tag" ] || return 1
  printf '%s\n' "$version"
}

_bash_god_bootstrap_installed_version() {
  local line candidate value

  value=''
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "_BASH_GOD_VERSION='"*"'")
        candidate=${line#"_BASH_GOD_VERSION='"}
        candidate=${candidate%"'"}
        _bash_god_bootstrap_version_is_valid "$candidate" || return 1
        [ -z "$value" ] || return 1
        value=$candidate
        ;;
    esac
  done < "$_bash_god_bootstrap_runtime/bash_god/core.sh"
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

_bash_god_bootstrap_is_managed() {
  [ ! -L "$_bash_god_bootstrap_launcher" ] &&
    [ -f "$_bash_god_bootstrap_launcher" ] &&
    [ -x "$_bash_god_bootstrap_launcher" ] &&
    LC_ALL=C grep -Fqx '# Real-file launcher installed at PREFIX/bin/god by the runtime package.' \
      "$_bash_god_bootstrap_launcher" &&
    [ ! -L "$_bash_god_bootstrap_runtime" ] &&
    [ -d "$_bash_god_bootstrap_runtime" ] &&
    [ -x "$_bash_god_bootstrap_runtime/god" ] &&
    [ -r "$_bash_god_bootstrap_runtime/bash_god/core.sh" ]
}

_bash_god_bootstrap_state() {
  local path_command

  _bash_god_bootstrap_state_value=''
  _bash_god_bootstrap_current_version=''
  if _bash_god_bootstrap_is_managed; then
    _bash_god_bootstrap_current_version="$(_bash_god_bootstrap_installed_version)" || \
      _bash_god_bootstrap_die 'managed installation version metadata is unreadable'
    _bash_god_bootstrap_state_value=managed
    return 0
  fi
  if [ -e "$_bash_god_bootstrap_launcher" ] || [ -L "$_bash_god_bootstrap_launcher" ] || \
     [ -e "$_bash_god_bootstrap_runtime" ] || [ -L "$_bash_god_bootstrap_runtime" ]; then
    _bash_god_bootstrap_state_value=partial
    return 0
  fi
  path_command="$(command -v god 2>/dev/null || true)"
  if [ -n "$path_command" ]; then
    _bash_god_bootstrap_path_command=$path_command
    _bash_god_bootstrap_state_value=unmanaged-command
  else
    _bash_god_bootstrap_state_value=absent
  fi
}

_bash_god_bootstrap_download() {
  local url target

  url=$1
  target=$2
  printf 'Downloading %s\n' "${url##*/}"
  curl --fail --show-error --location --retry 3 \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 120 \
    -o "$target" "$url"
}

_bash_god_bootstrap_seed_update_cache() {
  local cache_base cache_dir temporary now ttl

  cache_base=${XDG_CACHE_HOME:-}
  case "$cache_base" in
    /*) ;;
    *) cache_base="$HOME/.cache" ;;
  esac
  cache_dir="$cache_base/bash-god"
  [ ! -L "$cache_dir" ] || return 0
  mkdir -p "$cache_dir" 2>/dev/null || return 0
  temporary="$(mktemp "$cache_dir/.next-update-check.XXXXXX" 2>/dev/null)" || return 0
  now=$(date +%s) || { command rm -f -- "$temporary"; return 0; }
  ttl=${GOD_UPDATE_CHECK_TTL:-86400}
  case "$ttl" in ''|*[!0-9]*) ttl=86400 ;; esac
  printf '%s\n' "$((now + ttl))" > "$temporary"
  chmod 0600 "$temporary" 2>/dev/null || true
  mv -f "$temporary" "$cache_dir/next-update-check" 2>/dev/null || command rm -f -- "$temporary"
}

_bash_god_bootstrap_main() {
  local latest state relation replace release_url archive archive_checksum installer installer_checksum

  if [ -n "${BASH_GOD_PREFIX:-}" ]; then
    _bash_god_bootstrap_prefix=$BASH_GOD_PREFIX
  elif [ -n "${HOME:-}" ]; then
    _bash_god_bootstrap_prefix="$HOME/.local"
  else
    _bash_god_bootstrap_die 'HOME is unavailable; pass --prefix with an absolute path'
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --prefix)
        [ "$#" -ge 2 ] || _bash_god_bootstrap_die '--prefix requires a directory'
        _bash_god_bootstrap_prefix=$2
        shift 2
        ;;
      --help|-h) _bash_god_bootstrap_usage; return 0 ;;
      *) _bash_god_bootstrap_usage >&2; return 2 ;;
    esac
  done
  case "$_bash_god_bootstrap_prefix" in
    /*) ;;
    *) _bash_god_bootstrap_die 'PREFIX must be an absolute path' ;;
  esac

  for _bash_god_bootstrap_dependency in curl tar mktemp awk tr chmod rm; do
    command -v "$_bash_god_bootstrap_dependency" >/dev/null 2>&1 || \
      _bash_god_bootstrap_die "$_bash_god_bootstrap_dependency is required to install BASH_GOD"
  done
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || \
    _bash_god_bootstrap_die 'sha256sum or shasum is required to install BASH_GOD'

  _bash_god_bootstrap_launcher="$_bash_god_bootstrap_prefix/bin/god"
  _bash_god_bootstrap_runtime="$_bash_god_bootstrap_prefix/lib/bash-god"
  _bash_god_bootstrap_path_command=''
  _bash_god_bootstrap_state
  state=$_bash_god_bootstrap_state_value
  case "$state" in
    partial) _bash_god_bootstrap_die "unmanaged or partial files already exist under $_bash_god_bootstrap_prefix" ;;
    unmanaged-command) _bash_god_bootstrap_die "an unmanaged god command already exists at $_bash_god_bootstrap_path_command" ;;
    absent|managed) ;;
    *) _bash_god_bootstrap_die 'could not determine installation state' ;;
  esac

  latest="$(_bash_god_bootstrap_fetch_latest_version)" || \
    _bash_god_bootstrap_die "could not determine GitHub's latest published release"
  replace=0
  if [ "$state" = managed ]; then
    relation="$(_bash_god_bootstrap_compare_versions "$_bash_god_bootstrap_current_version" "$latest")"
    case "$relation" in
      -1) replace=1 ;;
      0) printf 'BASH_GOD %s is already installed and current.\n' "$latest"; return 0 ;;
      1) printf 'Installed BASH_GOD %s is newer than release %s; no downgrade was performed.\n' \
           "$_bash_god_bootstrap_current_version" "$latest"; return 0 ;;
      *) _bash_god_bootstrap_die 'could not compare installed and published versions' ;;
    esac
  fi

  _bash_god_bootstrap_download_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-install.XXXXXX")" || \
    _bash_god_bootstrap_die 'could not create a private download directory'
  chmod 0700 "$_bash_god_bootstrap_download_dir"
  release_url="https://github.com/${_bash_god_bootstrap_repository}/releases/download/v${latest}"
  archive="$_bash_god_bootstrap_download_dir/bash-god-${latest}.tar.gz"
  archive_checksum="${archive}.sha256"
  installer="$_bash_god_bootstrap_download_dir/install-runtime.sh"
  installer_checksum="${installer}.sha256"

  _bash_god_bootstrap_download "$release_url/bash-god-${latest}.tar.gz" "$archive"
  _bash_god_bootstrap_download "$release_url/bash-god-${latest}.tar.gz.sha256" "$archive_checksum"
  _bash_god_bootstrap_download "$release_url/install-runtime.sh" "$installer"
  _bash_god_bootstrap_download "$release_url/install-runtime.sh.sha256" "$installer_checksum"
  _bash_god_bootstrap_verify "$installer" "$installer_checksum"
  _bash_god_bootstrap_verify "$archive" "$archive_checksum"
  printf 'Checksums verified.\n'
  chmod 0700 "$installer"

  _bash_god_bootstrap_state
  state=$_bash_god_bootstrap_state_value
  if [ "$replace" -eq 1 ]; then
    [ "$state" = managed ] || _bash_god_bootstrap_die 'installation changed during download'
    [ "$(_bash_god_bootstrap_compare_versions "$_bash_god_bootstrap_current_version" "$latest")" = -1 ] || \
      _bash_god_bootstrap_die 'installed version is no longer older than the selected release'
    "$installer" --replace --prefix "$_bash_god_bootstrap_prefix" "$archive" "$archive_checksum"
  else
    [ "$state" = absent ] || _bash_god_bootstrap_die 'installation destination changed during download'
    "$installer" --prefix "$_bash_god_bootstrap_prefix" "$archive" "$archive_checksum"
  fi

  _bash_god_bootstrap_seed_update_cache
  printf '\nGet ready for the GOD...\n'
}

trap '_bash_god_bootstrap_cleanup' EXIT
trap 'exit 130' HUP INT TERM
_bash_god_bootstrap_main "$@"
