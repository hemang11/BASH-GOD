#!/usr/bin/env bash

# BASH_GOD service discovery. Resolves a service's @discover block against
# the local machine, caches the result, and answers the one cheap check the
# run-time path needs. This file never evaluates catalog @run values.
#
# Resolution order matches the plan: the catalog's declared root candidate
# first, then PATH, then a bounded scan. The engine here knows only
# probe/root/scan/version as mechanisms; no service name is special-cased.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_god_discover_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || \
  _god_discover_dir=''
if [ -n "$_god_discover_dir" ] && [ -z "$(type -t _god_catalog_has_discover 2>/dev/null)" ] && \
   [ -r "$_god_discover_dir/catalog.sh" ]; then
  # shellcheck source=catalog.sh
  . "$_god_discover_dir/catalog.sh" || exit 1
fi

# ---------------------------------------------------------------------------
# Cache: one flat KEY=VALUE file under the state directory that
# `god --uninstall` already purges wholesale.
# ---------------------------------------------------------------------------

_god_discover_state_dir() {
  case "${XDG_STATE_HOME:-}" in
    /) return 1 ;;
    /*) printf '%s/bash-god\n' "${XDG_STATE_HOME%/}" ;;
    *)
      [ -n "${HOME:-}" ] || return 1
      printf '%s/.local/state/bash-god\n' "$HOME"
      ;;
  esac
}

_god_discover_cache_file() {
  local dir

  dir="$(_god_discover_state_dir)" || return 1
  printf '%s/execution-paths\n' "$dir"
}

_god_discover_cache_get() {
  local key file

  key=$1
  file="$(_god_discover_cache_file)" || return 1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  LC_ALL=C awk -v k="$key" '
    index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }
  ' "$file"
}

_god_discover_cache_set() {
  local key value file dir temp existing

  key=$1
  value=$2
  file="$(_god_discover_cache_file)" || return 1
  dir="${file%/*}"
  [ -L "$dir" ] && return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  existing=''
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    existing="$(command cat "$file" 2>/dev/null)"
  fi
  temp="$(mktemp "$dir/.execution-paths.XXXXXX" 2>/dev/null)" || return 1
  {
    if [ -n "$existing" ]; then
      printf '%s\n' "$existing" | LC_ALL=C awk -v k="$key" 'index($0, k "=") != 1'
    fi
    printf '%s=%s\n' "$key" "$value"
  } > "$temp"
  chmod 0600 "$temp" 2>/dev/null || true
  mv -f "$temp" "$file" 2>/dev/null || { command rm -f -- "$temp"; return 1; }
}

_god_discover_path() {
  _god_discover_cache_get "$1.path"
}

_god_discover_version() {
  _god_discover_cache_get "$1.version"
}

# The selected member of an ordered catalog probe family. Old caches do not
# have this key; callers treat that as a prompt to use the catalog primary or
# refresh once, never as a failure.
_god_discover_tool() {
  _god_discover_cache_get "$1.tool"
}

# ---------------------------------------------------------------------------
# User override: an installed native tool that sits outside the catalog's
# root/PATH/scan reach (a custom directory, an old extracted tarball) needs
# one explicit line, not a wider scan. `~/.config/bash-god/<service>.conf`'s
# `path=` key, checked before root/PATH/scan, exists for exactly that case.
# ---------------------------------------------------------------------------

_god_discover_config_file() {
  local service

  service=$1
  case "${XDG_CONFIG_HOME:-}" in
    /*) printf '%s/bash-god/%s.conf\n' "${XDG_CONFIG_HOME%/}" "$service" ;;
    *)
      [ -n "${HOME:-}" ] || return 1
      printf '%s/.config/bash-god/%s.conf\n' "$HOME" "$service"
      ;;
  esac
}

# _god_discover_user_path SERVICE
#
# Prints the `path=` value from that service's config file, if one is set.
_god_discover_user_path() {
  local service file

  service=$1
  file="$(_god_discover_config_file "$service")" || return 1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  LC_ALL=C awk -F= '
    /^[[:space:]]*path[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=/, "", value)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Resolution mechanisms. Each takes plain values pulled from the catalog, not
# a service name, so the same code serves kafka today and mongo tomorrow.
# ---------------------------------------------------------------------------

_god_discover_probe_at() {
  [ -n "$1" ] && [ -x "$1/$2" ]
}

# _god_discover_find_in_dir DIRECTORY PROBES
#
# PROBES is a newline-separated, catalog-declared tool family. Prints the
# selected directory and tool as DIRECTORY<TAB>TOOL, choosing the first tool
# that actually exists in the directory.
_god_discover_find_in_dir() {
  local directory probes probe

  directory=$1
  probes=$2
  [ -n "$directory" ] || return 1
  while IFS= read -r probe; do
    [ -n "$probe" ] || continue
    if _god_discover_probe_at "$directory" "$probe"; then
      printf '%s\t%s\n' "$directory" "$probe"
      return 0
    fi
  done <<< "$probes"
  return 1
}

_god_discover_find_via_path() {
  local probes probe hit

  probes=$1
  while IFS= read -r probe; do
    [ -n "$probe" ] || continue
    hit="$(command -v -- "$probe" 2>/dev/null)" || continue
    case "$hit" in
      */*)
        printf '%s\t%s\n' "${hit%/*}" "$probe"
        return 0
        ;;
    esac
  done <<< "$probes"
  return 1
}

# Bounded so a missing install never turns into a full-disk crawl.
_god_discover_scan_depth=6

_god_discover_find_via_scan() {
  local scan probes probe hit

  scan=$1
  probes=$2
  [ -n "$scan" ] && [ -d "$scan" ] || return 1
  while IFS= read -r probe; do
    [ -n "$probe" ] || continue
    hit="$(command find "$scan" -maxdepth "$_god_discover_scan_depth" \
      -type f -name "$probe" -perm -u+x 2>/dev/null | LC_ALL=C sort | head -n 1)"
    [ -n "$hit" ] || continue
    printf '%s\t%s\n' "${hit%/*}" "$probe"
    return 0
  done <<< "$probes"
  return 1
}

_god_discover_extract_version() {
  LC_ALL=C grep -Eo '[0-9]+(\.[0-9]+)+' <<< "$1" | head -n 1
}

# Runs the catalog's declared version command inside the resolved directory.
# The command line is maintainer-authored catalog text, the same trust level
# as an @run value, and is never built from anything a user typed.
_god_discover_detect_version() {
  local root command_line output version

  root=$1
  command_line=$2
  [ -n "$command_line" ] || { printf 'unknown\n'; return 0; }
  # Native version commands are inconsistent: several CLIs write --version to
  # stderr even on success. Capture both streams privately so discovery noise
  # never leaks into the picker, then extract only a dotted numeric token.
  output="$( (CDPATH= cd "$root" 2>/dev/null && eval "./$command_line") 2>&1 )"
  version="$(_god_discover_extract_version "$output")"
  printf '%s\n' "${version:-unknown}"
}

# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

# _god_discover_resolve SERVICE CATALOG_FILE
#
# Returns:
#   0  found; SERVICE.path and SERVICE.version are cached
#   1  catalog declares no @discover block (display-only service)
#   2  probe was not found anywhere
_god_discover_resolve() {
  local service catalog probes root scan version_command candidate path tool version user_path

  service=$1
  catalog=$2

  _god_catalog_has_discover "$catalog" || return 1

  probes="$(_god_catalog_discover_probes "$catalog")"
  root="$(_god_catalog_discover_value "$catalog" root)"
  scan="$(_god_catalog_discover_value "$catalog" scan)"
  version_command="$(_god_catalog_discover_value "$catalog" version)"
  [ -n "$probes" ] || return 1

  candidate=''
  user_path="$(_god_discover_user_path "$service")"
  if [ -n "$user_path" ] && candidate="$(_god_discover_find_in_dir "$user_path" "$probes")"; then
    :
  elif [ -n "$root" ] && candidate="$(_god_discover_find_in_dir "$root" "$probes")"; then
    :
  elif candidate="$(_god_discover_find_via_path "$probes")"; then
    :
  else
    candidate="$(_god_discover_find_via_scan "$scan" "$probes")" || candidate=''
  fi
  [ -n "$candidate" ] || return 2
  IFS="$(printf '\t')" read -r path tool <<< "$candidate"
  [ -n "$path" ] && [ -n "$tool" ] || return 2

  version_command="${version_command//<probe>/$tool}"
  version="$(_god_discover_detect_version "$path" "$version_command")"

  _god_discover_cache_set "${service}.path" "$path" || return 2
  _god_discover_cache_set "${service}.version" "$version" || return 2
  _god_discover_cache_set "${service}.tool" "$tool" || return 2
  return 0
}

# _god_discover_is_stale SERVICE CATALOG_FILE
#
# The one cheap check the run-time path is allowed to make: no crawl, just
# confirming the cached probe still exists where it was found. 0 means stale
# or never resolved; 1 means the cache is still good.
_god_discover_is_stale() {
  local service catalog path tool probe probes declared

  service=$1
  catalog=$2
  path="$(_god_discover_path "$service")"
  [ -n "$path" ] || return 0
  tool="$(_god_discover_tool "$service")"
  # Releases before probe-family caching stored only path/version. Their
  # primary probe remains a safe fallback until the next explicit resync.
  [ -n "$tool" ] || tool="$(_god_catalog_discover_value "$catalog" probe)"
  probes="$(_god_catalog_discover_probes "$catalog")"
  declared=1
  while IFS= read -r probe; do
    if [ "$probe" = "$tool" ]; then
      declared=0
      break
    fi
  done <<< "$probes"
  [ "$declared" -eq 0 ] || return 0
  _god_discover_probe_at "$path" "$tool" && return 1
  return 0
}
