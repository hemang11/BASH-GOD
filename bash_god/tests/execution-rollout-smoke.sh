#!/usr/bin/env bash

# Cross-service execution rollout regression checks. Every apparent native
# executable in this file is a fixture under a temporary directory. The
# picker is stubbed before selection, so this suite cannot contact a cluster,
# cloud account, MongoDB deployment, HTTP endpoint, host utility, or network.

set -u
set -o pipefail

test_file="${BASH_SOURCE[0]}"
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
project_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1

k8s_catalog="$project_dir/bash_god/catalog/k8s/service.god"
aws_catalog="$project_dir/bash_god/catalog/aws/service.god"
mongo_catalog="$project_dir/bash_god/catalog/mongo/service.god"
elasticsearch_catalog="$project_dir/bash_god/catalog/elasticsearch/service.god"
general_catalog="$project_dir/bash_god/catalog/general/service.god"
network_catalog="$project_dir/bash_god/catalog/network/service.god"

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-execution-rollout.XXXXXX" 2>/dev/null)" || exit 1
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
  printf 'not ok %02d - %s\n' "$checks" "$1" >&2
}

has_exact_line() {
  printf '%s\n' "$1" | LC_ALL=C grep -Fqx "$2"
}

export_field() {
  local exported wanted

  exported=$1
  wanted=$2
  printf '%s\n' "$exported" | LC_ALL=C awk -F "$(printf '\t')" -v wanted="$wanted" '
    $1 == wanted { print $2; exit }
  '
}

# Returns GROUP<TAB>ENTRY for the first native @run whose leading command is
# PROBE. This keeps the fixture focused on a copyable catalog spelling rather
# than a particular row number.
location_for_leading_probe() {
  LC_ALL=C awk -v probe="$2" '
    /^@group[[:space:]]+/ {
      group = $0
      sub(/^@group[[:space:]]+/, "", group)
      entry = 0
      next
    }
    /^@command[[:space:]]+/ { entry++; field = ""; run = ""; next }
    /^@run$/ { field = "run"; next }
    /^@end$/ {
      if (run ~ ("^" probe "([[:space:]]|$)")) {
        print group "\t" entry
        exit
      }
      field = ""
      next
    }
    /^@/ { field = ""; next }
    field == "run" && /[^[:space:]]/ { run = $0; field = ""; next }
  ' "$1"
}

location_for_title() {
  LC_ALL=C awk -v wanted="$2" '
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
      if (title == wanted) {
        print group "\t" entry
        exit
      }
    }
  ' "$1"
}

mkdir -p \
  "$fixture_root/home" \
  "$fixture_root/config/bash-god" \
  "$fixture_root/state" \
  "$fixture_root/fake/k8s" \
  "$fixture_root/fake/aws" \
  "$fixture_root/fake/mongo" \
  "$fixture_root/fake/path" || exit 1

native_log="$fixture_root/native.log"
discovery_log="$fixture_root/discovery.log"
fake_tty="$fixture_root/fake-tty"
: > "$native_log"
: > "$discovery_log"
: > "$fake_tty"

# Each discoverable-service fixture permits only its declared version probe.
# Any selected catalog command would be recorded and fail the assertions below.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "kubectl|%s\\n" "$*" >> "$BASH_GOD_EXECUTION_ROLLOUT_NATIVE_LOG"' \
  'if [ "$1" = version ] && [ "$2" = --client ]; then' \
  '  printf "Client Version: v1.28.7\\n"' \
  '  exit 0' \
  'fi' \
  'exit 97' > "$fixture_root/fake/k8s/kubectl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "aws|%s\\n" "$*" >> "$BASH_GOD_EXECUTION_ROLLOUT_NATIVE_LOG"' \
  'if [ "$1" = --version ]; then' \
  '  printf "aws-cli/2.36.34 fixture\\n" >&2' \
  '  exit 0' \
  'fi' \
  'exit 97' > "$fixture_root/fake/aws/aws"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "mongosh|%s\\n" "$*" >> "$BASH_GOD_EXECUTION_ROLLOUT_NATIVE_LOG"' \
  'if [ "$1" = --version ]; then' \
  '  printf "mongosh 2.4.1 fixture\\n"' \
  '  exit 0' \
  'fi' \
  'exit 97' > "$fixture_root/fake/mongo/mongosh"
chmod 0700 \
  "$fixture_root/fake/k8s/kubectl" \
  "$fixture_root/fake/aws/aws" \
  "$fixture_root/fake/mongo/mongosh" || exit 1

# PATH-service stubs must never be invoked merely to offer the rich picker.
for tool in curl hostname ssh; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s|%s\\n" "$0" "$*" >> "$BASH_GOD_EXECUTION_ROLLOUT_NATIVE_LOG"' \
    'exit 97' > "$fixture_root/fake/path/$tool"
  chmod 0700 "$fixture_root/fake/path/$tool" || exit 1
done

printf 'path=%s\n' "$fixture_root/fake/k8s" > "$fixture_root/config/bash-god/k8s.conf"
printf 'path=%s\n' "$fixture_root/fake/aws" > "$fixture_root/config/bash-god/aws.conf"
printf 'path=%s\n' "$fixture_root/fake/mongo" > "$fixture_root/config/bash-god/mongo.conf"

export HOME="$fixture_root/home"
export XDG_CONFIG_HOME="$fixture_root/config"
export XDG_STATE_HOME="$fixture_root/state"
export BASH_GOD_EXECUTION_ROLLOUT_NATIVE_LOG="$native_log"

# Source the real public modules once. No `god` route is invoked directly;
# every behavior below is driven through public parser/discovery/resolver/
# picker functions with the real catalogs.
# shellcheck source=../../BASH_GOD.sh
. "$project_dir/BASH_GOD.sh" || exit 1

if _god_validate_catalog "$k8s_catalog" >/dev/null 2>&1 && \
   _god_validate_catalog "$aws_catalog" >/dev/null 2>&1 && \
   _god_validate_catalog "$mongo_catalog" >/dev/null 2>&1 && \
   _god_validate_catalog "$elasticsearch_catalog" >/dev/null 2>&1 && \
   _god_validate_catalog "$general_catalog" >/dev/null 2>&1 && \
   _god_validate_catalog "$network_catalog" >/dev/null 2>&1; then
  pass 'all non-Kafka rollout catalogs validate before execution tests'
else
  fail 'all non-Kafka rollout catalogs validate before execution tests'
fi

# Discovery and resolution contract: the source catalog stays copyable while
# the rich execution model gets exactly one absolute rewrite of its declared
# leading probe. No arbitrary later/bare word may be rewritten.
services=(k8s aws mongo)
catalogs=("$k8s_catalog" "$aws_catalog" "$mongo_catalog")
probes=(kubectl aws mongosh)
fake_dirs=("$fixture_root/fake/k8s" "$fixture_root/fake/aws" "$fixture_root/fake/mongo")
versions=(1.28.7 2.36.34 2.4.1)

index=0
while [ "$index" -lt "${#services[@]}" ]; do
  service="${services[$index]}"
  catalog="${catalogs[$index]}"
  probe="${probes[$index]}"
  fake_dir="${fake_dirs[$index]}"
  expected_version="${versions[$index]}"

  if _god_discover_resolve "$service" "$catalog" && \
     [ "$(_god_discover_path "$service")" = "$fake_dir" ] && \
     [ "$(_god_discover_version "$service")" = "$expected_version" ]; then
    pass "$service discovery uses its configured fake tool path"
  else
    fail "$service discovery uses its configured fake tool path"
  fi

  location="$(location_for_leading_probe "$catalog" "$probe")"
  IFS="$(printf '\t')" read -r group entry <<< "$location"
  exported=''
  [ -n "${group:-}" ] && [ -n "${entry:-}" ] && exported="$(_god_catalog_command_export "$catalog" "$group" "$entry")"
  static_run="$(export_field "$exported" RUN)"
  model=''
  [ -n "$static_run" ] && model="$(_god_resolve_command "$service" "$catalog" "$group" "$entry" "$fake_dir" '')"
  display="$(export_field "$model" DISPLAY)"

  case "$static_run" in
    "$probe"|"$probe "*) static_copyable=1 ;;
    *) static_copyable=0 ;;
  esac
  case "$display" in
    "$fake_dir/$probe"|"$fake_dir/$probe "*) resolved_leading=1 ;;
    *) resolved_leading=0 ;;
  esac
  if [ "$static_copyable" = 1 ] && [ "$resolved_leading" = 1 ]; then
    pass "$service keeps the catalog command bare and rewrites its rich preview"
  else
    fail "$service keeps the catalog command bare and rewrites its rich preview"
  fi

  leading="$(_god_resolve_rewrite_paths "$probe inspect" "$fake_dir" "$probe")"
  later="$(_god_resolve_rewrite_paths "echo $probe; $probe inspect" "$fake_dir" "$probe")"
  if [ "$leading" = "$fake_dir/$probe inspect" ] && [ "$later" = "echo $probe; $probe inspect" ]; then
    pass "$service rewrites only the declared leading probe"
  else
    fail "$service rewrites only the declared leading probe"
  fi

  index=$((index + 1))
done

if has_exact_line "$(command cat "$native_log")" 'kubectl|version --client' && \
   has_exact_line "$(command cat "$native_log")" 'aws|--version' && \
   has_exact_line "$(command cat "$native_log")" 'mongosh|--version' && \
   [ "$(LC_ALL=C wc -l < "$native_log" | tr -d '[:space:]')" = 3 ]; then
  pass 'discoverable-service fixtures received version probes only'
else
  fail 'discoverable-service fixtures received version probes only'
fi

native_log_before_path_offer="$(command cat "$native_log")"

# A fake TTY/picker makes the normal rich-search route observable without
# selecting any command. PATH catalogs must carry an empty execution path and
# must not consult discovery or launch a native stub while producing a preview.
path_offer_output="$(
  PATH="$fixture_root/fake/path:$PATH" \
  BASH_GOD_EXECUTION_ROLLOUT_NATIVE_LOG="$native_log" \
  BASH_GOD_EXECUTION_ROLLOUT_DISCOVERY_LOG="$discovery_log" \
  GOD_COLOR=never TERM=xterm-256color \
  bash -c '
    . "$1/BASH_GOD.sh" || exit 1

    _god_stdout_is_terminal() { return 0; }
    _god_menu_rich_available() { return 0; }
    _god_discover_is_stale() {
      printf "stale:%s\\n" "$1" >> "$BASH_GOD_EXECUTION_ROLLOUT_DISCOVERY_LOG"
      return 1
    }
    _god_discover_path() {
      printf "path:%s\\n" "$1" >> "$BASH_GOD_EXECUTION_ROLLOUT_DISCOVERY_LOG"
      return 1
    }
    _god_discover_resolve() {
      printf "resolve:%s\\n" "$1" >> "$BASH_GOD_EXECUTION_ROLLOUT_DISCOVERY_LOG"
      return 2
    }
    _god_menu_select_rich() {
      local rows provider label

      rows=$1
      provider=$4
      "$provider" 1 || return 1
      label="$(_god_menu_field "$rows" 1 1)"
      printf "RICH|%s|path=%s|%s|%s\\n" "$5" "${rich_execution_paths[0]:-}" "$label" "$_god_menu_provider_detail"
      _god_menu_choice=-1
      return 0
    }

    _god_search "cluster health" smart list elasticsearch "" 0 || exit $?
    _god_search "current hostname" smart list general "" 0 || exit $?
    _god_search "HTTP response headers" smart list network "" 0
  ' _ "$project_dir"
)"

if printf '%s\n' "$path_offer_output" | LC_ALL=C grep -Fq 'RICH|ELASTICSEARCH SEARCH RESULTS|path=|Show cluster health|curl -sS' && \
   printf '%s\n' "$path_offer_output" | LC_ALL=C grep -Fq 'RICH|GENERAL SEARCH RESULTS|path=|Show the current hostname|hostname' && \
   printf '%s\n' "$path_offer_output" | LC_ALL=C grep -Fq 'RICH|NETWORK SEARCH RESULTS|path=|Show HTTP response headers|curl -sS -I <url>' && \
   [ ! -s "$discovery_log" ] && \
   [ "$(command cat "$native_log")" = "$native_log_before_path_offer" ]; then
  pass 'PATH services offer rich previews without discovery or native execution'
else
  fail 'PATH services offer rich previews without discovery or native execution'
fi

# PATH services have no discovered version/path, but their rich model still
# needs to keep query-derived values out of shell syntax. This row embeds a
# placeholder inside single quotes, which is the easy case to regress into
# string interpolation rather than a positional bash -c argument.
es_location="$(location_for_title "$elasticsearch_catalog" 'Count documents in an index')"
IFS="$(printf '\t')" read -r es_group es_entry <<< "$es_location"
es_pending_model="$(_god_resolve_command elasticsearch "$elasticsearch_catalog" "$es_group" "$es_entry" '' '')"
es_bound_model="$(_god_resolve_command elasticsearch "$elasticsearch_catalog" "$es_group" "$es_entry" '' 'index "orders-v1"')"
es_path_ignored_model="$(_god_resolve_command elasticsearch "$elasticsearch_catalog" "$es_group" "$es_entry" '/must-not-rewrite' 'index "orders-v1"')"
es_expected_template=$'TEMPLATE\t'"curl -sS 'http://localhost:9200/'\"\${1}\"'/_count?pretty'"
if has_exact_line "$es_pending_model" $'PENDING\t<index_name>\t<index_name>\torders-v1\tIndex or alias whose documents should be counted' && \
   has_exact_line "$es_bound_model" "$es_expected_template" && \
   has_exact_line "$es_bound_model" $'VALUE\torders-v1' && \
   has_exact_line "$es_path_ignored_model" $'DISPLAY\tcurl -sS '\''http://localhost:9200/orders-v1/_count?pretty'\'''; then
  pass 'Elasticsearch PATH rich models keep values positional and ignore a supplied path'
else
  fail 'Elasticsearch PATH rich models keep values positional and ignore a supplied path'
fi

# A discovered service with no usable cached path must take the established
# static screen even when a fake TTY says the rich picker is available.
unresolved_log="$fixture_root/unresolved.log"
: > "$unresolved_log"
unresolved_output="$(
  PATH="$fixture_root/fake/path:$PATH" \
  BASH_GOD_EXECUTION_ROLLOUT_NATIVE_LOG="$native_log" \
  BASH_GOD_EXECUTION_ROLLOUT_UNRESOLVED_LOG="$unresolved_log" \
  GOD_COLOR=never TERM=xterm-256color \
  bash -c '
    . "$1/BASH_GOD.sh" || exit 1

    _god_stdout_is_terminal() { return 0; }
    _god_menu_rich_available() { return 0; }
    _god_discover_is_stale() {
      printf "stale:%s\\n" "$1" >> "$BASH_GOD_EXECUTION_ROLLOUT_UNRESOLVED_LOG"
      return 0
    }
    _god_discover_path() {
      printf "path:%s\\n" "$1" >> "$BASH_GOD_EXECUTION_ROLLOUT_UNRESOLVED_LOG"
      return 1
    }
    _god_menu_select_rich() {
      printf "picker\\n" >> "$BASH_GOD_EXECUTION_ROLLOUT_UNRESOLVED_LOG"
      return 99
    }

    _god_search "list pods" smart list k8s "" 0
  ' _ "$project_dir"
)"

if printf '%s\n' "$unresolved_output" | LC_ALL=C grep -Fq 'K8S SEARCH RESULTS' && \
   printf '%s\n' "$unresolved_output" | LC_ALL=C grep -Fq 'MATCHING OPERATIONS' && \
   has_exact_line "$(command cat "$unresolved_log")" 'stale:k8s' && \
   ! LC_ALL=C grep -Fq 'picker' "$unresolved_log" && \
   ! LC_ALL=C grep -Fq 'path:k8s' "$unresolved_log" && \
   [ "$(command cat "$native_log")" = "$native_log_before_path_offer" ]; then
  pass 'unresolved discovery stays on the static matching-operations screen'
else
  fail 'unresolved discovery stays on the static matching-operations screen'
fi

# Actual disabled catalog rows must refuse before resolver or child-shell work.
mongo_location="$(location_for_title "$mongo_catalog" 'Show replica-set status')"
aws_location="$(location_for_title "$aws_catalog" 'Ignore exported keys and fall back to the instance role')"
IFS="$(printf '\t')" read -r mongo_group mongo_entry <<< "$mongo_location"
IFS="$(printf '\t')" read -r aws_group aws_entry <<< "$aws_location"
mongo_export="$(_god_catalog_command_export "$mongo_catalog" "$mongo_group" "$mongo_entry")"
aws_export="$(_god_catalog_command_export "$aws_catalog" "$aws_group" "$aws_entry")"

disabled_execution_result="$(
  child_launches=0
  resolver_calls=0
  bash() {
    child_launches=$((child_launches + 1))
    return 97
  }
  _god_resolve_command_interactive() {
    resolver_calls=$((resolver_calls + 1))
    return 97
  }

  mongo_status=0
  aws_status=0
  _god_execute_command mongo "$mongo_catalog" "$mongo_group" "$mongo_entry" "$fixture_root/fake/mongo" '' 1 >/dev/null 2>&1 || mongo_status=$?
  _god_execute_command aws "$aws_catalog" "$aws_group" "$aws_entry" "$fixture_root/fake/aws" '' 1 >/dev/null 2>&1 || aws_status=$?
  printf '%s|%s|%s|%s\n' "$mongo_status" "$aws_status" "$resolver_calls" "$child_launches"
)"

if has_exact_line "$mongo_export" $'RUNNABLE\t0' && \
   has_exact_line "$aws_export" $'RUNNABLE\t0' && \
   [ "$disabled_execution_result" = '2|2|0|0' ]; then
  pass 'Mongo raw snippets and AWS unset rows refuse before resolver or child launch'
else
  fail 'Mongo raw snippets and AWS unset rows refuse before resolver or child launch'
fi

# Drive the actual rich-picker key loop with a local fake /dev/tty descriptor
# and deterministic key reader. `e` and Enter are both ignored for disabled
# rows; after moving to the second disabled row they remain ignored there too.
disabled_picker_result="$(
  BASH_GOD_EXECUTION_ROLLOUT_FAKE_TTY="$fake_tty" \
  bash -c '
    . "$1/BASH_GOD.sh" || exit 1

    _god_menu_open_tty() {
      exec 3<> "$BASH_GOD_EXECUTION_ROLLOUT_FAKE_TTY"
      _god_menu_tty_fd=3
    }
    _god_menu_close_tty() {
      exec 3<&- 2>/dev/null || :
      exec 3>&- 2>/dev/null || :
      _god_menu_tty_fd=""
    }
    _god_menu_width() { printf 100; }
    _god_menu_rich_install_traps() { :; }
    _god_menu_rich_cleanup() { :; }
    _god_menu_rich_cursor_start() { :; }
    _god_menu_draw_rich_static() { :; }
    _god_menu_rich_render_current() { :; }
    _god_menu_rich_redraw_selection() { :; }
    _god_menu_readline_edit() {
      editor_calls=$((editor_calls + 1))
      return 0
    }
    step=0
    _god_menu_rich_read_key() {
      case "$step" in
        0) _god_menu_rich_key=e ;;
        1) _god_menu_rich_key=enter ;;
        2) _god_menu_rich_key=down ;;
        3) _god_menu_rich_key=e ;;
        4) _god_menu_rich_key=enter ;;
        *) _god_menu_rich_key=escape ;;
      esac
      step=$((step + 1))
      return 0
    }

    editor_calls=0
    _god_menu_select_rich $'"'"'Mongo raw snippet\tcopy only\t\t0\tNeeds an existing mongosh session\nAWS unset\tcopy only\t\t0\tOnly changes the caller shell'"'"' $'"'"'rs.status()\nunset AWS_ACCESS_KEY_ID'"'"' 1
    status=$?
    printf "%s|%s|%s\\n" "$status" "$_god_menu_choice" "$editor_calls"
  ' _ "$project_dir"
)"

if [ "$disabled_picker_result" = '0|-1|0' ]; then
  pass 'copy-only Mongo and AWS rows ignore edit and Enter in the rich picker'
else
  fail 'copy-only Mongo and AWS rows ignore edit and Enter in the rich picker'
fi

if [ "$failures" -ne 0 ]; then
  printf '%s of %s execution-rollout checks failed\n' "$failures" "$checks" >&2
  exit 1
fi

printf '%s execution-rollout checks passed\n' "$checks"
