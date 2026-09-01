#!/usr/bin/env bash

# PATH-execution catalog regression checks.  The rich-picker fixture below
# never accepts a row, and every native command that could plausibly be named
# by the selected rows is a temporary logging stub.  This test therefore
# proves only metadata and offer-path behavior; it never reaches a host,
# service, DNS resolver, HTTP endpoint, curl, or SSH server.

set -u
set -o pipefail

test_dir="$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || exit 1
project_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
catalog_module="$project_dir/bash_god/catalog.sh"

elasticsearch_catalog="$project_dir/bash_god/catalog/elasticsearch/service.god"
general_catalog="$project_dir/bash_god/catalog/general/service.god"
network_catalog="$project_dir/bash_god/catalog/network/service.god"

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-path-services.XXXXXX" 2>/dev/null)" || exit 1
trap 'rm -rf -- "$fixture_root"' EXIT

failures=0
checks=0

pass() {
  checks=$((checks + 1))
  printf 'ok %02d - %s\n' "$checks" "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'not ok %02d - %s\n' "$checks" "$1"
}

has_exact_line() {
  printf '%s\n' "$1" | LC_ALL=C grep -Fqx "$2"
}

# Print GROUP<TAB>ENTRY for every record, retaining the catalog's positional
# numbering so it can be fed back to _god_catalog_command_export.
catalog_locations() {
  LC_ALL=C awk '
    /^@group[[:space:]]+/ {
      group = $0
      sub(/^@group[[:space:]]+/, "", group)
      entry = 0
      next
    }
    /^@command[[:space:]]+/ { entry++; print group "\t" entry }
  ' "$1"
}

# Print GROUP<TAB>ENTRY<TAB>TITLE<TAB>RUN for lightweight policy checks.
catalog_records() {
  LC_ALL=C awk '
    /^@group[[:space:]]+/ {
      group = $0
      sub(/^@group[[:space:]]+/, "", group)
      entry = 0
      next
    }
    /^@command[[:space:]]+/ {
      entry++
      title = $0
      sub(/^@command[[:space:]]+/, "", title)
      run = ""
      field = ""
      next
    }
    /^@end$/ { print group "\t" entry "\t" title "\t" run; field = ""; next }
    /^@run$/ { field = "run"; next }
    /^@/ { field = ""; next }
    field == "run" && /[^[:space:]]/ {
      run = $0
      field = ""
      next
    }
  ' "$1"
}

# shellcheck source=../catalog.sh
. "$catalog_module" || exit 1

catalogs=("$elasticsearch_catalog" "$general_catalog" "$network_catalog")
services=(elasticsearch general network)

index=0
while [ "$index" -lt "${#catalogs[@]}" ]; do
  catalog="${catalogs[$index]}"
  service="${services[$index]}"

  if _god_validate_catalog "$catalog" >/dev/null 2>&1; then
    pass "$service PATH-execution catalog validates"
  else
    fail "$service PATH-execution catalog validates"
  fi

  if [ "$(_god_catalog_execution_mode "$catalog")" = PATH ] && \
     _god_catalog_has_execution "$catalog" && \
     ! _god_catalog_has_discover "$catalog"; then
    pass "$service exports PATH execution without discovery metadata"
  else
    fail "$service exports PATH execution without discovery metadata"
  fi

  runnable_count=0
  runnable_failures=0
  while IFS=$'\t' read -r group entry; do
    [ -n "$group" ] || continue
    runnable_count=$((runnable_count + 1))
    exported="$(_god_catalog_command_export "$catalog" "$group" "$entry")"
    has_exact_line "$exported" $'RUNNABLE\t1' || runnable_failures=$((runnable_failures + 1))
  done < <(catalog_locations "$catalog")
  if [ "$runnable_count" -gt 0 ] && [ "$runnable_failures" -eq 0 ]; then
    pass "$service PATH rows default to runnable exports"
  else
    fail "$service PATH rows default to runnable exports"
  fi

  index=$((index + 1))
done

# A `sudo` command opens another local privilege context, so every such
# General row must communicate its risk in the exported picker model.
general_sudo_count=0
general_sudo_failures=0
while IFS=$'\t' read -r group entry title run; do
  case "$run" in
    sudo\ *)
      general_sudo_count=$((general_sudo_count + 1))
      exported="$(_god_catalog_command_export "$general_catalog" "$group" "$entry")"
      has_exact_line "$exported" $'RISK\tWARN' || general_sudo_failures=$((general_sudo_failures + 1))
      ;;
  esac
done < <(catalog_records "$general_catalog")
if [ "$general_sudo_count" -gt 0 ] && [ "$general_sudo_failures" -eq 0 ]; then
  pass 'General sudo commands export WARN risk'
else
  fail 'General sudo commands export WARN risk'
fi

# `ssh -G` only prints local effective configuration.  Every other SSH row
# can create a remote connection and must carry WARN in the picker model.
network_ssh_count=0
network_ssh_failures=0
while IFS=$'\t' read -r group entry title run; do
  case "$run" in
    ssh\ -G\ *) ;;
    ssh\ *)
      network_ssh_count=$((network_ssh_count + 1))
      exported="$(_god_catalog_command_export "$network_catalog" "$group" "$entry")"
      has_exact_line "$exported" $'RISK\tWARN' || network_ssh_failures=$((network_ssh_failures + 1))
      ;;
  esac
done < <(catalog_records "$network_catalog")
if [ "$network_ssh_count" -gt 0 ] && [ "$network_ssh_failures" -eq 0 ]; then
  pass 'Network connection-capable SSH commands export WARN risk'
else
  fail 'Network connection-capable SSH commands export WARN risk'
fi

trace_location="$(LC_ALL=C awk '
  /^@group[[:space:]]+/ {
    group = $0
    sub(/^@group[[:space:]]+/, "", group)
    entry = 0
    next
  }
  /^@command[[:space:]]+/ {
    entry++
    title = $0
    sub(/^@command[[:space:]]+/, "", title)
    selected = title == "Save a complete curl trace"
    next
  }
  selected && /^@run$/ { getline; run = $0; next }
  /^@end$/ && selected { print group "\t" entry "\t" run; exit }
' "$network_catalog")"
IFS=$'\t' read -r trace_group trace_entry trace_run <<< "$trace_location"
trace_export=""
if [ -n "${trace_group:-}" ] && [ -n "${trace_entry:-}" ]; then
  trace_export="$(_god_catalog_command_export "$network_catalog" "$trace_group" "$trace_entry")"
fi
if [ "$trace_run" = 'curl --trace-ascii <trace_file> <url> -o /dev/null' ] && \
   has_exact_line "$trace_export" $'RISK\tWRITE'; then
  pass 'Network curl trace exports WRITE risk'
else
  fail 'Network curl trace exports WRITE risk'
fi

# The fake binaries are intentionally never called.  If a future change makes
# the offer path launch a native command, it writes a line here and this test
# fails without reaching the real network or local host utilities.
fake_path="$fixture_root/fake-path"
native_log="$fixture_root/native-command.log"
discovery_log="$fixture_root/discovery.log"
mkdir -p "$fake_path" || exit 1
for tool in curl hostname ssh; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s %s\\n" "$0" "$*" >> "$BASH_GOD_PATH_SERVICE_NATIVE_LOG"' \
    'exit 99' > "$fake_path/$tool"
  chmod 0700 "$fake_path/$tool" || exit 1
done

# _god_stdout_is_terminal and _god_menu_rich_available are deliberate TTY
# test doubles.  The menu stub resolves its first detail but leaves choice -1,
# proving each catalog reaches the rich offer without accepting or running it.
rich_output="$(
  PATH="$fake_path:$PATH" \
  BASH_GOD_PATH_SERVICE_NATIVE_LOG="$native_log" \
  BASH_GOD_PATH_SERVICE_DISCOVERY_LOG="$discovery_log" \
  GOD_COLOR=never \
  TERM=xterm-256color \
  bash -c '
    . "$1/BASH_GOD.sh"

    _god_stdout_is_terminal() { return 0; }
    _god_menu_rich_available() { return 0; }
    _god_discover_is_stale() {
      printf "is_stale\\n" >> "$BASH_GOD_PATH_SERVICE_DISCOVERY_LOG"
      return 1
    }
    _god_discover_path() {
      printf "path\\n" >> "$BASH_GOD_PATH_SERVICE_DISCOVERY_LOG"
      printf "/unexpected/discovery/path\\n"
    }
    _god_discover_resolve() {
      printf "resolve\\n" >> "$BASH_GOD_PATH_SERVICE_DISCOVERY_LOG"
      return 1
    }
    _god_menu_select_rich() {
      local rows provider first_row

      rows=$1
      provider=$4
      "$provider" 1 || return 1
      first_row="$(_god_menu_field "$rows" 1 1)"
      printf "OFFER|%s|%s\\n" "$first_row" "$_god_menu_provider_detail"
      _god_menu_choice=-1
      return 0
    }

    _god_search "cluster health" smart list elasticsearch "" 0 || exit $?
    _god_search "current hostname" smart list general "" 0 || exit $?
    _god_search "HTTP response headers" smart list network "" 0
  ' _ "$project_dir"
)"

if printf '%s\n' "$rich_output" | LC_ALL=C grep -Fq 'OFFER|Show cluster health|curl -sS' && \
   printf '%s\n' "$rich_output" | LC_ALL=C grep -Fq 'OFFER|Show the current hostname|hostname' && \
   printf '%s\n' "$rich_output" | LC_ALL=C grep -Fq 'OFFER|Show HTTP response headers|curl -sS -I <url>' && \
   [ ! -s "$native_log" ] && [ ! -s "$discovery_log" ]; then
  pass 'PATH catalogs reach a fake-TTY rich offer without discovery or native execution'
else
  fail 'PATH catalogs reach a fake-TTY rich offer without discovery or native execution'
fi

if [ "$failures" -ne 0 ]; then
  printf '%s of %s checks failed\n' "$failures" "$checks" >&2
  exit 1
fi

printf '%s checks passed\n' "$checks"
