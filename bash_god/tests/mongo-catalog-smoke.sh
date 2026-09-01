#!/usr/bin/env bash
# Metadata-only regression checks for the MongoDB catalog. This test never
# invokes mongosh, MongoDB Database Tools, or a MongoDB server.

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
  local actual expected label

  actual=$1
  expected=$2
  label=$3
  [ "$actual" = "$expected" ] || fail "$label (expected $expected; got ${actual:-<empty>})"
}

if ! bash -c '. "$1"; _god_validate_catalog "$2"' _ "$catalog_module" "$catalog"; then
  fail 'MongoDB catalog validates'
fi

# shellcheck source=../catalog.sh
. "$catalog_module"

expect_eq "$(_god_catalog_execution_mode "$catalog")" 'DISCOVER' 'MongoDB execution mode'
expect_eq "$(_god_catalog_discover_value "$catalog" probe)" 'mongosh' 'MongoDB discovery probe'
expect_eq "$(_god_catalog_discover_value "$catalog" root)" '/usr/local/bin' 'MongoDB discovery root'
expect_eq "$(_god_catalog_discover_value "$catalog" scan)" '/opt' 'MongoDB discovery scan'
expect_eq "$(_god_catalog_discover_value "$catalog" version)" 'mongosh --version' 'MongoDB version probe'

# Exercise this catalog's discovery metadata only against a temporary fake
# mongosh. Its sole accepted invocation is `--version`, so this cannot open a
# database connection or reach a real installation on the machine.
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-mongo-catalog.XXXXXX" 2>/dev/null)" || exit 1
trap 'rm -rf -- "$fixture_root"' EXIT
fixture_bin="$fixture_root/bin"
fixture_state="$fixture_root/state"
fixture_config="$fixture_root/config"
mkdir -p "$fixture_bin" "$fixture_state/bash-god" "$fixture_config/bash-god"
printf '%s\n' '#!/bin/sh' \
  '[ "$#" -eq 1 ] && [ "$1" = "--version" ] || exit 99' \
  "printf '%s\\n' 'mongosh 2.4.1'" > "$fixture_bin/mongosh"
chmod +x "$fixture_bin/mongosh"
printf 'path=%s\n' "$fixture_bin" > "$fixture_config/bash-god/mongo.conf"

# shellcheck source=../discover.sh
. "$project_dir/bash_god/discover.sh"
XDG_STATE_HOME="$fixture_state"
XDG_CONFIG_HOME="$fixture_config"
export XDG_STATE_HOME XDG_CONFIG_HOME
if _god_discover_resolve mongo "$catalog"; then
  expect_eq "$(_god_discover_path mongo)" "$fixture_bin" 'MongoDB discovery uses the configured fake mongosh root'
  expect_eq "$(_god_discover_version mongo)" '2.4.1' 'MongoDB discovery captures the fake mongosh version'
else
  fail 'MongoDB discovery resolves the configured fake mongosh root'
fi

if ! LC_ALL=C awk '
  function fail(message) {
    print "FAIL: " message > "/dev/stderr"
    errors++
  }

  /^@command[[:space:]]+/ {
    title = $0
    sub(/^@command[[:space:]]+/, "", title)
    in_command = 1
    field = ""
    run = ""
    since = ""
    runnable = 1
    notes = 0
    risk = ""
    next
  }

  in_command && /^@since[[:space:]]+/ {
    since = $0
    sub(/^@since[[:space:]]+/, "", since)
    field = ""
    next
  }

  in_command && /^@runnable[[:space:]]+NO$/ {
    runnable = 0
    field = ""
    next
  }

  in_command && /^@risk[[:space:]]+/ {
    risk = $0
    sub(/^@risk[[:space:]]+/, "", risk)
    field = ""
    next
  }

  in_command && /^@run$/ { field = "run"; next }
  in_command && /^@notes$/ { field = "notes"; next }
  in_command && /^@/ { field = "" }

  in_command && field == "run" && /[^[:space:]]/ {
    run = $0
    field = ""
    next
  }

  in_command && field == "notes" && /[^[:space:]]/ { notes = 1 }

  /^@end$/ && in_command {
    records++
    if (since == "") fail(title " is missing @since")

    raw_shell = run ~ /^(show[[:space:]]|use[[:space:]]|help$|rs\.|db\.)/
    if (raw_shell) {
      raw++
      if (runnable) fail(title " is an in-shell snippet but remains runnable")
      if (!notes) fail(title " is copy-only without an explanatory note")
    } else if (!runnable) {
      fail(title " is an OS command but was made copy-only")
    }

    if (run ~ /^mongosh([[:space:]]|$)/) {
      direct_mongosh++
      if (since != "1.0") fail(title " must use mongosh client floor 1.0")
    } else if (since != "0.0") {
      fail(title " must not infer compatibility from the mongosh client version")
    }

    if (run ~ /^\.\/(mongo|mongodump|mongorestore)([[:space:]]|$)/) {
      fail(title " assumes a separate or legacy tool is co-located with mongosh")
    }

    if (run ~ /^mongodump[[:space:]]+--host/ && risk != "WRITE") {
      fail(title " writes local dump output but lacks @risk WRITE")
    }
    if (run ~ /^mongorestore[[:space:]]+--host/ && run !~ /--dryRun/ && risk != "WRITE") {
      fail(title " imports data but lacks @risk WRITE")
    }
    if (run ~ /^mongorestore[[:space:]]+--host/ && run ~ /--dryRun/ && risk != "") {
      fail(title " is a dry run but has a write risk")
    }

    in_command = 0
    next
  }

  END {
    if (records != 44) fail("expected 44 records; got " records)
    if (raw != 24) fail("expected 24 copy-only Mongo shell snippets; got " raw)
    if (direct_mongosh != 4) fail("expected four direct mongosh commands; got " direct_mongosh)
    exit(errors ? 1 : 0)
  }
' "$catalog"; then
  failures=$((failures + 1))
fi

disabled_export="$(_god_catalog_command_export "$catalog" replica 1)"
enabled_export="$(_god_catalog_command_export "$catalog" connect 1)"
case "$disabled_export" in
  *$'RUNNABLE\t0'*) ;;
  *) fail 'raw replica status exports RUNNABLE 0' ;;
esac
case "$enabled_export" in
  *$'RUNNABLE\t1'*) ;;
  *) fail 'direct mongosh connection exports RUNNABLE 1' ;;
esac

# The command-level marker must stop raw snippets before resolution or the
# eventual `bash -c` launch. Replace bash with a counter rather than creating
# a real executable; every selected raw record must return the copy-only code.
# shellcheck source=../execute.sh
. "$project_dir/bash_god/execute.sh"
bash_calls=0
bash() {
  bash_calls=$((bash_calls + 1))
  return 97
}

disabled_rows=0
while IFS=$'\t' read -r group entry; do
  status=0
  _god_execute_command mongo "$catalog" "$group" "$entry" '/not/a/real/mongosh/root' '' 1 >/dev/null 2>/dev/null || status=$?
  [ "$status" -eq 2 ] || fail "${group}/${entry} copy-only execution refusal (expected 2; got $status)"
  disabled_rows=$((disabled_rows + 1))
done < <(LC_ALL=C awk '
  /^@group[[:space:]]+/ {
    group = $0
    sub(/^@group[[:space:]]+/, "", group)
    entry = 0
    next
  }
  /^@command[[:space:]]+/ {
    entry++
    field = ""
    run = ""
    next
  }
  /^@run$/ { field = "run"; next }
  /^@/ { field = "" }
  field == "run" && /[^[:space:]]/ {
    run = $0
    field = ""
    next
  }
  /^@end$/ {
    if (run ~ /^(show[[:space:]]|use[[:space:]]|help$|rs\.|db\.)/) print group "\t" entry
  }
' "$catalog")
unset -f bash

expect_eq "$disabled_rows" '24' 'copy-only Mongo shell row count'
expect_eq "$bash_calls" '0' 'copy-only Mongo shell rows never reach bash -c'

if [ "$failures" -ne 0 ]; then
  printf '%s MongoDB catalog check(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'MongoDB catalog checks passed\n'
