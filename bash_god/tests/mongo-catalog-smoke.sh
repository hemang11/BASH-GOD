#!/usr/bin/env bash
# Metadata-only regression checks for the MongoDB catalog. This test never
# invokes a MongoDB server or database tool.

set -u
set -o pipefail

project_dir="$(CDPATH= cd "$(dirname "$0")/../.." && pwd -P)"
catalog="$project_dir/bash_god/catalog/mongo/service.god"
catalog_module="$project_dir/bash_god/catalog.sh"
failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

expect_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected $2; got ${1:-<empty>})"
}

has_exact_line() {
  printf '%s\n' "$1" | LC_ALL=C grep -Fqx "$2"
}

if ! bash -c '. "$1"; _god_validate_catalog "$2"' _ "$catalog_module" "$catalog"; then
  fail 'MongoDB catalog validates'
fi

# shellcheck source=../catalog.sh
. "$catalog_module"
expect_eq "$(_god_catalog_execution_mode "$catalog")" DISCOVER 'MongoDB execution mode'
expect_eq "$(_god_catalog_discover_value "$catalog" probe)" mongosh 'MongoDB primary discovery probe'
expect_eq "$(_god_catalog_discover_probes "$catalog")" "$(printf 'mongosh\nmongo')" 'MongoDB ordered client family'
expect_eq "$(_god_catalog_discover_value "$catalog" version)" '<probe> --version' 'MongoDB selected-client version command'

# The fake clients accept only --version. Discovery is therefore exercised
# without connecting to a server or opening a shell.
fixture_root="$(mktemp -d /tmp/bash-god-mongo-catalog.XXXXXX)" || exit 1
trap 'rm -rf -- "$fixture_root"' EXIT
fixture_bin="$fixture_root/bin"
fixture_state="$fixture_root/state"
fixture_config="$fixture_root/config"
mkdir -p "$fixture_bin" "$fixture_state/bash-god" "$fixture_config/bash-god"
printf '%s\n' '#!/bin/sh' '[ "$#" -eq 1 ] && [ "$1" = "--version" ] || exit 99' "printf '%s\\n' 'mongosh 2.4.1'" > "$fixture_bin/mongosh"
printf '%s\n' '#!/bin/sh' '[ "$#" -eq 1 ] && [ "$1" = "--version" ] || exit 99' "printf '%s\\n' 'MongoDB shell version v4.2.22'" > "$fixture_bin/mongo"
chmod +x "$fixture_bin/mongosh" "$fixture_bin/mongo"
printf 'path=%s\n' "$fixture_bin" > "$fixture_config/bash-god/mongo.conf"

# shellcheck source=../discover.sh
. "$project_dir/bash_god/discover.sh"
XDG_STATE_HOME="$fixture_state"
XDG_CONFIG_HOME="$fixture_config"
export XDG_STATE_HOME XDG_CONFIG_HOME
_god_discover_local_listener_target() { return 1; }
if _god_discover_resolve mongo "$catalog"; then
  expect_eq "$(_god_discover_path mongo)" "$fixture_bin" 'MongoDB discovery uses the configured fake root'
  expect_eq "$(_god_discover_version mongo)" 2.4.1 'MongoDB discovery reads modern client version'
  expect_eq "$(_god_discover_tool mongo)" mongosh 'MongoDB discovery prefers mongosh'
else
  fail 'MongoDB discovery resolves the configured modern client'
fi

command rm -f -- "$fixture_bin/mongosh"
if _god_discover_resolve mongo "$catalog"; then
  expect_eq "$(_god_discover_tool mongo)" mongo 'MongoDB discovery falls back to legacy mongo'
  expect_eq "$(_god_discover_version mongo)" 4.2.22 'MongoDB discovery reads legacy client version'
else
  fail 'MongoDB discovery resolves the declared legacy fallback'
fi

# shellcheck source=../resolve.sh
. "$project_dir/bash_god/resolve.sh"
# shellcheck source=../search.sh
. "$project_dir/bash_god/search.sh"
connect_model="$(_god_resolve_command mongo "$catalog" connect 1 "$fixture_bin" '')"
query_model="$(_god_resolve_command mongo "$catalog" query 2 "$fixture_bin" '')"
missing_preferred="$(_god_search_discovered_tool_missing "$fixture_bin" 'mongosh --host <host> --port 27017 --quiet --eval '\''db.stats()'\''' "$(_god_catalog_discover_probes "$catalog")" mongo)" || true
if printf '%s\n' "$connect_model" | LC_ALL=C grep -Fq "$fixture_bin/mongo \"mongodb://" && \
   printf '%s\n' "$query_model" | LC_ALL=C grep -Fq "$fixture_bin/mongo --host <host> --port 27017 --quiet --eval" && \
   [ -z "$missing_preferred" ]; then
  :
else
  fail 'legacy fallback runs preferred MongoDB shell rows through the cached client'
fi

# A cached service Target must reach URI-shaped and --host/--port-shaped
# MongoDB commands alike. This uses only the fake selected client and state
# cache; it never opens a MongoDB connection.
_god_discover_cache_set mongo.target mongo.internal:29017
uri_target_model="$(_god_resolve_command mongo "$catalog" connect 1 "$fixture_bin" '')"
legacy_target_model="$(_god_resolve_command mongo "$catalog" connect 4 "$fixture_bin" '')"
replica_target_model="$(_god_resolve_command mongo "$catalog" replica 1 "$fixture_bin" '')"
if has_exact_line "$uri_target_model" $'DISPLAY\t'"$fixture_bin/mongo \"mongodb://mongo.internal:29017/<database>\"" && \
   has_exact_line "$legacy_target_model" $'DISPLAY\t'"$fixture_bin/mongo --host mongo.internal --port 29017 <database>" && \
   has_exact_line "$legacy_target_model" $'VALUE\tmongo.internal' && \
   has_exact_line "$legacy_target_model" $'VALUE\t29017' && \
   has_exact_line "$replica_target_model" $'DISPLAY\t'"$fixture_bin/mongo --host mongo.internal --port 29017 --quiet --eval 'rs.status()'" && \
   ! printf '%s\n' "$replica_target_model" | LC_ALL=C grep -Fq '<host>'; then
  :
else
  fail 'MongoDB Target binds URI and explicit host-port command forms'
fi

# No executable catalog may bring back a raw REPL line or the removed
# former non-executable marker. Select-a-database belongs in query because it is the
# first step before running a database query.
if ! LC_ALL=C awk '
  function fail(message) { print "FAIL: " message > "/dev/stderr"; errors++ }
  /^@group[[:space:]]+/ {
    group = $0
    sub(/^@group[[:space:]]+/, "", group)
    next
  }
  /^@command[[:space:]]+/ {
    title = $0
    sub(/^@command[[:space:]]+/, "", title)
    field = ""
    run = ""
    since = ""
    records++
    next
  }
  /^@runnable/ { fail(title " declares removed @runnable metadata"); next }
  /^@since[[:space:]]+/ {
    since = $0
    sub(/^@since[[:space:]]+/, "", since)
    field = ""
    next
  }
  /^@run$/ { field = "run"; next }
  /^@/ { field = "" }
  field == "run" && /[^[:space:]]/ {
    run = $0
    field = ""
    if (run ~ /^(show[[:space:]]|use[[:space:]]|help$|rs\.|db\.)/) fail(title " is still a raw in-shell snippet")
    if (run ~ /^mongosh[[:space:]]+--host[[:space:]]+<host>[[:space:]]+--port[[:space:]]+27017[[:space:]]+--quiet[[:space:]]+--eval[[:space:]]+/) wrapped++
    if (run ~ /^mongosh([[:space:]]|$)/ && since != "0.0") fail(title " must support the declared legacy fallback")
    next
  }
  /^@end$/ {
    if (title == "Select a database" && group != "query") fail("Select a database must be in query")
  }
  END {
    if (records != 43) fail("expected 43 records; got " records)
    if (wrapped != 23) fail("expected 23 executable shell expressions; got " wrapped)
    exit(errors ? 1 : 0)
  }
' "$catalog"; then
  failures=$((failures + 1))
fi

all_rows=0
while IFS=$'\t' read -r group entry; do
  [ -n "$group" ] || continue
  exported="$(_god_catalog_command_export "$catalog" "$group" "$entry")"
  has_exact_line "$exported" $'RUNNABLE\t1' || fail "$group/$entry is not runnable"
  all_rows=$((all_rows + 1))
done < <(LC_ALL=C awk '
  /^@group[[:space:]]+/ {
    group = $0
    sub(/^@group[[:space:]]+/, "", group)
    entry = 0
    next
  }
  /^@command[[:space:]]+/ { entry++; next }
  /^@end$/ { print group "\t" entry }
' "$catalog")
expect_eq "$all_rows" 43 'all MongoDB catalog rows export RUNNABLE 1'

if [ "$failures" -ne 0 ]; then
  printf '%s MongoDB catalog check(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'MongoDB catalog checks passed\n'
