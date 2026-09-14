#!/usr/bin/env bash

# Knowledge-rendering regression checks. No catalog command is executed.

test_file="${BASH_SOURCE[0]}"
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
project_dir="$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd -P)" || exit 1
god_cli="$project_dir/god"
expected_version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$project_dir/src/core.sh")"
aws_catalog="$project_dir/catalog/aws/service.god"
kafka_catalog="$project_dir/catalog/kafka/service.god"
general_catalog="$project_dir/catalog/general/service.god"
elasticsearch_catalog="$project_dir/catalog/elasticsearch/service.god"
k8s_catalog="$project_dir/catalog/k8s/service.god"
mongo_catalog="$project_dir/catalog/mongo/service.god"
network_catalog="$project_dir/catalog/network/service.god"
catalog_module="$project_dir/src/catalog.sh"
render_module="$project_dir/src/ui/render.sh"
art_module="$project_dir/src/ui/art.sh"
search_module="$project_dir/src/search.sh"
interaction_module="$project_dir/src/interaction.sh"
resolve_module="$project_dir/src/resolve.sh"
execute_module="$project_dir/src/execute.sh"
eligibility_module="$project_dir/src/eligibility.sh"
input_module="$project_dir/src/ui/input.sh"
tui_module="$project_dir/src/ui/tui.sh"
tree_module="$project_dir/src/ui/tree.sh"
license_file="$project_dir/LICENSE"
[ -f "$license_file" ] || license_file="$project_dir/LICENSE"

# Isolated from the real machine's discover cache and per-service config
# overrides (~/.local/state/bash-god, ~/.config/bash-god): a service resolved
# for real on the developer's own machine must not silently flip these
# fixtures from the unresolved-service assertions they're written against.
smoke_home="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-smoke.XXXXXX" 2>/dev/null)" || exit 1
# The aggregate suite isolates HOME so discovery/config fixtures cannot see a
# developer's real state. Capture Go's module cache first, though: helper PTY
# builds use the approved dependency graph and must not trigger a cold module
# or toolchain download into the disposable fixture HOME midway through the
# same smoke run.
smoke_go_mod_cache="${GOMODCACHE:-}"
if [ -z "$smoke_go_mod_cache" ] && command -v go >/dev/null 2>&1; then
  smoke_go_mod_cache="$(go env GOMODCACHE 2>/dev/null || :)"
fi
# Go can create read-only cache directories beneath the temporary fixture
# home. Restore owner write permission before teardown so a successful
# PTY/package run never leaves fixture data behind.
trap 'chmod -R u+w "$smoke_home" 2>/dev/null || true; rm -rf -- "$smoke_home"' EXIT
export HOME="$smoke_home"
if [ -n "$smoke_go_mod_cache" ]; then
  export GOMODCACHE="$smoke_go_mod_cache"
fi
unset XDG_STATE_HOME XDG_CONFIG_HOME

# The artwork and rich-picker assertions below intentionally verify UTF-8
# rendering. GitHub's minimal runner shell can start without a locale, which
# correctly makes the product choose its ASCII fallback but makes these
# Unicode-specific assertions host-dependent. Keep the normal test locale
# explicit; individual ASCII checks use LC_ALL=C below.
unset LC_ALL LC_CTYPE
export LANG='en_US.UTF-8'

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

# Keep this as the one stable smoke entrypoint.  The focused suites own their
# temporary catalogs and fake executables, while this runner makes each of
# them a required part of the repository's normal smoke contract.
run_focused_suite() {
  local suite status

  suite=$1
  bash "$test_dir/$suite"
  status=$?
  if [ "$status" -eq 0 ]; then
    pass "$suite passes"
  else
    fail "$suite passes"
  fi
}

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

not_contains() {
  ! contains "$1" "$2"
}

has_exact_line() {
  printf '%s\n' "$1" | LC_ALL=C grep -Fqx "$2"
}

has_single_leading_newline() {
  local newline

  newline='
'
  case "$1" in
    "$newline$newline"*) return 1 ;;
    "$newline"*) return 0 ;;
    *) return 1 ;;
  esac
}

catalog_group_count() {
  LC_ALL=C awk '/^@group[[:space:]]+/ { count++ } END { print count + 0 }' "$1"
}

catalog_command_count() {
  LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$1"
}

catalog_group_command_count() {
  LC_ALL=C awk -v wanted="$2" '
    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      selected = tolower(current) == tolower(wanted)
      next
    }
    selected && /^@command[[:space:]]+/ { count++ }
    END { print count + 0 }
  ' "$1"
}

catalog_entry_number() {
  LC_ALL=C awk -v wanted_group="$2" -v wanted_title="$3" '
    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      selected = tolower(current) == tolower(wanted_group)
      position = 0
      next
    }
    selected && /^@command[[:space:]]+/ {
      position++
      title = $0
      sub(/^@command[[:space:]]+/, "", title)
      if (tolower(title) == tolower(wanted_title)) {
        print position
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "$1"
}

kafka_group_count="$(catalog_group_count "$kafka_catalog")"
kafka_command_count="$(catalog_command_count "$kafka_catalog")"
kafka_since_count="$(LC_ALL=C awk '/^@since[[:space:]]+/ { count++ } END { print count + 0 }' "$kafka_catalog")"
offset_command_count="$(catalog_group_command_count "$kafka_catalog" offset)"
native_command_count="$(catalog_group_command_count "$kafka_catalog" native)"
access_command_count="$(catalog_group_command_count "$kafka_catalog" access)"
k8s_list_pods_number="$(catalog_entry_number "$k8s_catalog" pods 'List pods in a namespace')"
consume_exact_number="$(catalog_entry_number "$kafka_catalog" consume 'Read from an exact partition offset')"
consume_exact_label="$(printf '%02d' "$consume_exact_number")"
offset_lag_number="$(catalog_entry_number "$kafka_catalog" offset 'Show consumer-group offsets and lag')"
group_members_number="$(catalog_entry_number "$kafka_catalog" groups 'Show active members of a consumer group')"
group_list_number="$(catalog_entry_number "$kafka_catalog" groups 'List consumer groups')"
health_unavailable_number="$(catalog_entry_number "$kafka_catalog" health 'Find partitions without an available leader')"
health_unavailable_label="$(printf '%02d' "$health_unavailable_number")"
setup_version_number="$(catalog_entry_number "$kafka_catalog" setup 'Show the installed Kafka version')"
setup_tools_number="$(catalog_entry_number "$kafka_catalog" setup 'List installed Kafka command-line tools')"

missing_since_catalog="$smoke_home/missing-since.god"
missing_synced_catalog="$smoke_home/missing-synced.god"
display_only_catalog="$smoke_home/display-only.god"
printf '%s\n' \
  '@title Executable fixture' \
  '@description' \
  'Validator fixture.' \
  '@discover' \
  'probe | fixture.sh | Fixture probe' \
  'root | /tmp | Fixture root' \
  '@connection NONE' \
  '@synced 1.0' \
  '@group demo' \
  '@command Missing compatibility floor' \
  '@mode LOCAL' \
  '@description' \
  'Deliberately omits the required floor.' \
  '@run' \
  'printf fixture' \
  '@end' > "$missing_since_catalog"
printf '%s\n' \
  '@title Executable fixture' \
  '@description' \
  'Validator fixture.' \
  '@discover' \
  'probe | fixture.sh | Fixture probe' \
  'root | /tmp | Fixture root' \
  '@connection NONE' \
  '@group demo' \
  '@command Reviewed fixture' \
  '@mode LOCAL' \
  '@since 0.0' \
  '@description' \
  'Deliberately omits the required service review marker.' \
  '@run' \
  'printf fixture' \
  '@end' > "$missing_synced_catalog"
printf '%s\n' \
  '@title Display-only fixture' \
  '@description' \
  'Validator fixture.' \
  '@group demo' \
  '@command Display-only command' \
  '@mode LOCAL' \
  '@description' \
  'A display-only catalog has no detected service version.' \
  '@run' \
  'printf fixture' \
  '@end' > "$display_only_catalog"
missing_since_status=0
missing_since_output="$(bash -c '. "$1"; _god_validate_catalog "$2"' _ "$catalog_module" "$missing_since_catalog" 2>&1)" || missing_since_status=$?
missing_synced_status=0
missing_synced_output="$(bash -c '. "$1"; _god_validate_catalog "$2"' _ "$catalog_module" "$missing_synced_catalog" 2>&1)" || missing_synced_status=$?
display_only_status=0
bash -c '. "$1"; _god_validate_catalog "$2"' _ "$catalog_module" "$display_only_catalog" >/dev/null 2>&1 || display_only_status=$?
if [ "$kafka_since_count" -eq "$kafka_command_count" ] && [ "$missing_since_status" -ne 0 ] && \
   contains "$missing_since_output" 'has no @since; every command in an executable catalog must declare its compatibility floor' && \
   [ "$display_only_status" -eq 0 ]; then
  pass 'every executable-service command requires an explicit compatibility floor'
else
  fail 'every executable-service command requires an explicit compatibility floor'
fi

if [ "$missing_synced_status" -ne 0 ] && \
   contains "$missing_synced_output" 'discovery catalog is missing @synced'; then
  pass 'every discovery catalog requires an explicit review version'
else
  fail 'every discovery catalog requires an explicit review version'
fi

connection_contract_output="$(bash -c '
  . "$1"
  shift
  for catalog in "$@"; do
    printf "%s\\t%s\\t%s\\n" "${catalog##*/catalog/}" "$(_god_catalog_connection_kind "$catalog")" "$(_god_catalog_connection_port "$catalog")"
  done
' _ "$catalog_module" "$kafka_catalog" "$mongo_catalog" "$k8s_catalog" "$aws_catalog" "$elasticsearch_catalog" "$general_catalog" "$network_catalog")"
connection_contract_output="$(printf '%s\n' "$connection_contract_output" | LC_ALL=C sed 's|/service.god||')"
expected_connection_contract=$'kafka\tENDPOINT\t9092\nmongo\tENDPOINT\t27017\nk8s\tCONTEXT\t\naws\tCONTEXT\t\nelasticsearch\tENDPOINT\t9200\ngeneral\tNONE\t\nnetwork\tNONE\t'
if [ "$connection_contract_output" = "$expected_connection_contract" ]; then
  pass 'every executable catalog declares an explicit connection context'
else
  fail 'every executable catalog declares an explicit connection context'
fi

private_catalog_examples="$(LC_ALL=C grep -R -E -i '(ontic|hshrimali|sync_asset|preprod-us-west1|ec2-user)' "$project_dir/catalog" 2>/dev/null || true)"
if [ -z "$private_catalog_examples" ]; then
  pass 'public catalog examples contain no project-specific identifiers'
else
  fail 'public catalog examples contain no project-specific identifiers'
fi

output="$(GOD_COLOR=never "$god_cli")"
paths_output="$(GOD_COLOR=never "$god_cli" --paths)"
home_identity="BASH_GOD  v$expected_version  •  MIT License"
home_identity_ascii="BASH_GOD  v$expected_version  -  MIT License"
home_slogan='Your DevOps command memory: searchable, copy-ready native commands.'
home_philosophy='Native CLIs remain the source of truth.'
logo_first='██████╗  █████╗ ███████╗██╗  ██╗    ██████╗  ██████╗ ██████╗'
logo_last='╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝'
services_table_start="$(printf 'SERVICES\n  SERVICE')"
quick_start_first_row="$(printf 'QUICK START\n  god kafka')"
quick_start_semantic_row="$(printf '  %-44s %s' 'god kafka q "Get all consumers in a broker"' 'Search Kafka by remembered intent')"
view_keys_first_row="$(printf 'VIEW KEYS\n  <number>')"
if contains "$output" "$services_table_start" && contains "$output" 'god aws' && contains "$output" "$quick_start_first_row" && has_exact_line "$output" "$quick_start_semantic_row" && contains "$output" "$view_keys_first_row" && contains "$output" 'god kafka health <number>' && contains "$output" "god q --regex 'offset|lag'" && contains "$output" '--quiet' && contains "$output" 'On a TTY, search can offer a reviewed command' && contains "$output" 'god --keys' && contains "$output" 'god --uninstall' && not_contains "$output" "$logo_first" && not_contains "$output" "$home_identity" && not_contains "$output" "$home_slogan"; then
  pass 'non-interactive root dashboard stays decoration-free'
else
  fail 'non-interactive root dashboard stays decoration-free'
fi

if contains "$paths_output" 'DISCOVERED PATHS' && \
   contains "$paths_output" 'Resolved clients and service targets.' && \
   not_contains "$paths_output" '@discover'; then
  pass 'resolved-path view uses operator language instead of catalog grammar'
else
  fail 'resolved-path view uses operator language instead of catalog grammar'
fi

paths_metadata_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  fixture_catalog_file=$2
  _god_catalog_files() { printf "%s\n" "$fixture_catalog_file"; }
  _god_discover_path() { printf "/fixtures/kafka\n"; }
  _god_discover_version() { printf "3.9.2\n"; }
  _god_discover_target() { printf "10.24.12.7:9092\n"; }
  _god_discover_is_stale() { return 1; }
  _god_print_discovered_paths
' _ "$project_dir" "$kafka_catalog")"
if contains "$paths_metadata_output" 'kafka            /fixtures/kafka' && \
   contains "$paths_metadata_output" 'v3.9.2 · reviewed 3.9 · Target: 10.24.12.7:9092' && \
   not_contains "$paths_metadata_output" 'not verified on'; then
  pass 'paths owns catalog review and resolved endpoint context'
else
  fail 'paths owns catalog review and resolved endpoint context'
fi

target_fixture_bin="$smoke_home/target-fixture/bin"
target_fixture_catalog="$smoke_home/target-fixture.god"
mkdir -p "$target_fixture_bin" || exit 1
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "$1" = --version ] && [ "$2" = --bootstrap-server ] && [ "$3" = 10.24.12.7:9092 ]; then' \
  '  printf "fixture 1.0\n"' \
  '  exit 0' \
  'fi' \
  'exit 97' > "$target_fixture_bin/fixture.sh"
chmod 0755 "$target_fixture_bin/fixture.sh"
printf '%s\n' \
  '@title Target fixture' \
  '@description' \
  'Fixture for generic endpoint resolution.' \
  '@discover' \
  'probe | fixture.sh | Fixture client' \
  "root | $target_fixture_bin | Fixture client directory" \
  'version | fixture.sh --version --bootstrap-server localhost:9092 | Reads the endpoint through the selected fixture client' \
  '@connection ENDPOINT 9092' \
  '@synced 1.0' \
  '@group demo' \
  '@command List through the default endpoint' \
  '@mode MODERN' \
  '@since 1.0' \
  '@description' \
  'Uses the catalog default authority.' \
  '@run' \
  'fixture.sh --bootstrap-server localhost:9092 --list' \
  '@end' \
  '@command Connect through explicit host and port slots' \
  '@mode MODERN' \
  '@since 1.0' \
  '@description' \
  'Uses explicit endpoint flags without repeating them in parameter metadata.' \
  '@run' \
  'fixture.sh --host <host> --port 9092 --status' \
  '@end' > "$target_fixture_catalog"
target_resolution_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  ss() { printf "%s\n" "LISTEN 0 50 [::ffff:10.24.12.7]:9092 *:*"; }
  _god_discover_resolve fixture "$2" || exit $?
  printf "TARGET:%s\n" "$(_god_discover_target fixture)"
  printf "VERSION:%s\n" "$(_god_discover_version fixture)"
  _god_resolve_command fixture "$2" demo 1 "$3" ""
  _god_resolve_command fixture "$2" demo 2 "$3" ""
' _ "$project_dir" "$target_fixture_catalog" "$target_fixture_bin")"
if contains "$target_resolution_output" 'TARGET:10.24.12.7:9092' && contains "$target_resolution_output" 'VERSION:1.0' && \
   contains "$target_resolution_output" $'DISPLAY\t'"$target_fixture_bin/fixture.sh --bootstrap-server 10.24.12.7:9092 --list" && \
   contains "$target_resolution_output" $'DISPLAY\t'"$target_fixture_bin/fixture.sh --host 10.24.12.7 --port 9092 --status" && \
   contains "$target_resolution_output" $'TEMPLATE\t'"$target_fixture_bin/fixture.sh --host \"\${1}\" --port \"\${2}\" --status" && \
   not_contains "$target_resolution_output" 'localhost:9092'; then
  pass 'resync caches a local endpoint candidate and binds every reviewed endpoint form'
else
  fail 'resync caches a local endpoint candidate and rewrites only the reviewed runtime command'
fi

mkdir -p "$smoke_home/.config/bash-god" || exit 1
printf 'target=broker.internal:19092\n' > "$smoke_home/.config/bash-god/override.conf"
target_override_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  ss() { printf "%s\n" "LISTEN 0 50 10.24.12.7:9092 *:*"; }
  _god_discover_resolve override "$2" || exit $?
  printf "TARGET:%s\n" "$(_god_discover_target override)"
  _god_resolve_command override "$2" demo 1 "$3" ""
  _god_resolve_command override "$2" demo 2 "$3" ""
' _ "$project_dir" "$target_fixture_catalog" "$target_fixture_bin")"
if contains "$target_override_output" 'TARGET:broker.internal:19092' && \
   contains "$target_override_output" $'DISPLAY\t'"$target_fixture_bin/fixture.sh --bootstrap-server broker.internal:19092 --list" && \
   contains "$target_override_output" $'DISPLAY\t'"$target_fixture_bin/fixture.sh --host broker.internal --port 19092 --status" && \
   not_contains "$target_override_output" '10.24.12.7:9092'; then
  pass 'configured endpoint target overrides a discovered local listener'
else
  fail 'configured endpoint target overrides a discovered local listener'
fi

missing_client_service_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_discover_path() { return 1; }
  _god_discover_resolution() { printf "missing\n"; }
  god mongo
' _ "$project_dir")"
if contains "$missing_client_service_output" '43 commands across 8 groups - curated, searchable, never executed.' && \
   contains "$missing_client_service_output" 'mongo client not found on this machine · run god mongo --resync' && \
   not_contains "$missing_client_service_output" 'Target: unresolved'; then
  pass 'service dashboard explains an explicitly missing client without inventing a target'
else
  fail 'service dashboard explains an explicitly missing client without inventing a target'
fi

synced_search_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_discover_version() { printf "3.9.2\n"; }
  god kafka q "list topics"
' _ "$project_dir")"
if contains "$synced_search_output" 'List topics through a broker' && \
   not_contains "$synced_search_output" 'not verified on v3.9.2'; then
  pass 'catalog review state never becomes a per-command compatibility warning'
else
  fail 'catalog review state never becomes a per-command compatibility warning'
fi

root_resync_log="$smoke_home/root-resync.log"
: > "$root_resync_log"
root_resync_output="$(ROOT_RESYNC_LOG="$root_resync_log" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_discover_resolve() {
    printf "%s\\n" "$1" >> "$ROOT_RESYNC_LOG"
    case "$1" in
      elasticsearch|kafka|mongo) return 0 ;;
      *) return 2 ;;
    esac
  }
  _god_discover_path() {
    case "$1" in
      elasticsearch) printf "/fixtures/elasticsearch\\n" ;;
      kafka) printf "/fixtures/kafka\\n" ;;
      mongo) printf "/fixtures/mongo\\n" ;;
    esac
  }
  _god_discover_tool() {
    case "$1" in
      elasticsearch) printf "curl\\n" ;;
    esac
  }
  _god_discover_version() {
    case "$1" in
      elasticsearch) printf "8.15.2\\n" ;;
      kafka) printf "1.1.0\\n" ;;
      mongo) printf "2.4.1\\n" ;;
    esac
  }
  god --resync
' _ "$project_dir" "$root_resync_log")"
root_resync_calls="$(command cat "$root_resync_log")"
root_resync_usage_status=0
GOD_COLOR=never "$god_cli" --resync unexpected >/dev/null 2>&1 || root_resync_usage_status=$?
expected_root_resync_calls="$(printf 'aws\nelasticsearch\nk8s\nkafka\nmongo')"
if contains "$root_resync_output" 'BASH_GOD / RESYNC' && \
   contains "$root_resync_output" '/fixtures/elasticsearch (via curl · v8.15.2)' && \
   contains "$root_resync_output" '/fixtures/kafka (version 1.1.0)' && \
   contains "$root_resync_output" '/fixtures/mongo (version 2.4.1)' && \
   contains "$root_resync_output" 'aws              not found (aws)' && \
   contains "$root_resync_output" '3 of 5 detectable services refreshed.' && \
   not_contains "$root_resync_output" 'network' && \
   [ "$root_resync_calls" = "$expected_root_resync_calls" ] && \
   [ "$root_resync_usage_status" -eq 2 ]; then
  pass 'root --resync refreshes every discoverable service, including Elasticsearch'
else
  fail 'root --resync refreshes every discoverable service, including Elasticsearch'
fi

maintenance_bare_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; _god_run_maintenance() { printf "maintenance:%s\n" "$1"; }; GOD_COLOR=never god' _ "$project_dir")"
maintenance_help_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; _god_run_maintenance() { printf "maintenance:%s\n" "$1"; }; GOD_COLOR=never god help' _ "$project_dir")"
maintenance_quiet_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; _god_run_maintenance() { printf "maintenance:%s\n" "$1"; }; GOD_COLOR=never god --quiet' _ "$project_dir")"
if contains "$maintenance_bare_output" 'maintenance:check' && \
   not_contains "$maintenance_help_output" 'maintenance:' && \
   not_contains "$maintenance_quiet_output" 'maintenance:'; then
  pass 'automatic update checks run only for bare non-quiet interactive god'
else
  fail 'automatic update checks run only for bare non-quiet interactive god'
fi

uninstall_route_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_validate_all_catalogs() { return 2; }; _god_run_maintenance() { printf "maintenance:%s\n" "$1"; }; GOD_COLOR=invalid god --uninstall' _ "$project_dir")"
if [ "$uninstall_route_output" = 'maintenance:uninstall' ]; then
  pass 'god --uninstall delegates only to maintenance even when catalogs or styles are broken'
else
  fail 'god --uninstall delegates only to maintenance even when catalogs or styles are broken'
fi

help_output="$(GOD_COLOR=never "$god_cli" help)"
if [ "$output" = "$help_output" ]; then
  pass 'non-interactive god and god help are equivalent'
else
  fail 'non-interactive god and god help are equivalent'
fi

interactive_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god' _ "$project_dir")"
interactive_help_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god help' _ "$project_dir")"
interactive_long_help_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god --help' _ "$project_dir")"
interactive_quiet_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god --quiet' _ "$project_dir")"
if contains "$interactive_output" "$logo_first" && contains "$interactive_output" "$logo_last" && contains "$interactive_output" "$home_identity" && contains "$interactive_output" "$home_slogan" && contains "$interactive_output" "$home_philosophy" && not_contains "$interactive_help_output" "$logo_first" && not_contains "$interactive_long_help_output" "$logo_first" && [ "$interactive_quiet_output" = "$interactive_help_output" ]; then
  pass 'pre-rendered logo is limited to bare interactive god'
else
  fail 'pre-rendered logo is limited to bare interactive god'
fi

interactive_service_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god kafka' _ "$project_dir")"
interactive_tree_alias_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god tree kafka' _ "$project_dir")"
interactive_version_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god --version' _ "$project_dir")"
interactive_error_output="$(bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=invalid god help' _ "$project_dir" 2>&1)"
if has_single_leading_newline "$interactive_output" && has_single_leading_newline "$interactive_help_output" && has_single_leading_newline "$interactive_service_output" && has_single_leading_newline "$interactive_tree_alias_output" && has_single_leading_newline "$interactive_version_output" && has_single_leading_newline "$interactive_error_output" && ! has_single_leading_newline "$output"; then
  pass 'every top-level interactive command leaves one leading line without padding pipes'
else
  fail 'every top-level interactive command leaves one leading line without padding pipes'
fi

version_output="$(GOD_COLOR=never "$god_cli" --version)"
short_version_output="$(GOD_COLOR=never "$god_cli" -v)"
license_text="$(command cat "$license_file")"
if [ "$version_output" = "$short_version_output" ] && contains "$version_output" "BASH_GOD $expected_version" && contains "$version_output" 'License: MIT' && not_contains "$version_output" 'GNU bash' && contains "$license_text" 'MIT License'; then
  pass 'version flags report only BASH_GOD version and MIT license'
else
  fail 'version flags report only BASH_GOD version and MIT license'
fi

service_output="$(GOD_COLOR=never "$god_cli" kafka)"
service_help_output="$(GOD_COLOR=never "$god_cli" KAFKA --HELP)"
if [ "$service_output" = "$service_help_output" ] && contains "$service_output" 'GROUP MAP' && contains "$service_output" "$kafka_command_count commands across $kafka_group_count groups" && contains "$service_output" 'god kafka native' && contains "$service_output" '[LEGACY]' && contains "$service_output" 'unmarked = normal' && not_contains "$service_output" "$home_slogan"; then
  pass 'service map is compact and case-insensitive'
else
  fail 'service map is compact and case-insensitive'
fi

quiet_prefix_service_output="$(GOD_COLOR=never "$god_cli" --quiet kafka)"
quiet_suffix_service_output="$(GOD_COLOR=never "$god_cli" kafka --quiet)"
quiet_group_output="$(GOD_COLOR=never "$god_cli" kafka offset --quiet)"
normal_quiet_group_output="$(GOD_COLOR=never "$god_cli" kafka offset)"
quiet_search_output="$(GOD_COLOR=never "$god_cli" kafka q lag --tree --full --quiet)"
normal_quiet_search_output="$(GOD_COLOR=never "$god_cli" kafka q lag --tree --full)"
if [ "$quiet_prefix_service_output" = "$service_output" ] && [ "$quiet_suffix_service_output" = "$service_output" ] && [ "$quiet_group_output" = "$normal_quiet_group_output" ] && [ "$quiet_search_output" = "$normal_quiet_search_output" ]; then
  pass 'global --quiet is accepted at root, service, group, and search scopes'
else
  fail 'global --quiet is accepted at root, service, group, and search scopes'
fi

group_output="$(GOD_COLOR=never "$god_cli" kafka consume)"
if contains "$group_output" '$ ./kafka-console-consumer.sh --bootstrap-server localhost:9092' && contains "$group_output" 'EXPLAIN  god kafka consume <number>' && not_contains "$group_output" 'PARAMETER' && not_contains "$group_output" 'production consumer group' && not_contains "$group_output" "$home_slogan"; then
  pass 'group view is a concise one-line command index'
else
  fail 'group view is a concise one-line command index'
fi

group_help_output="$(GOD_COLOR=never "$god_cli" kafka consume --help)"
if contains "$group_help_output" 'OPERATIONS' && not_contains "$group_help_output" '$ ./kafka-console-consumer.sh'; then
  pass 'group help is an operation index'
else
  fail 'group help is an operation index'
fi

entry_output="$(GOD_COLOR=never "$god_cli" kafka consume "$consume_exact_number")"
if contains "$entry_output" "KAFKA / CONSUME / $consume_exact_label" && contains "$entry_output" 'PARAMETER' && contains "$entry_output" '--partition' && contains "$entry_output" '--max-messages' && contains "$entry_output" '--timeout-ms'; then
  pass 'numbered entry explains command parameters'
else
  fail 'numbered entry explains command parameters'
fi

details_output="$(GOD_COLOR=never "$god_cli" kafka consume --details)"
if contains "$details_output" 'KAFKA / CONSUME / DETAILS' && contains "$details_output" 'FULL DETAILS' && contains "$details_output" 'Starts a console consumer at one explicit topic partition and offset.' && contains "$details_output" 'PARAMETER' && contains "$details_output" '--max-messages' && contains "$details_output" 'Print record keys, headers, and timestamps'; then
  pass 'details expands every command in one group'
else
  fail 'details expands every command in one group'
fi

service_details_status=0
service_details_output="$(GOD_COLOR=never "$god_cli" kafka --details 2>&1)" || service_details_status=$?
root_details_status=0
root_details_output="$(GOD_COLOR=never "$god_cli" --details 2>&1)" || root_details_status=$?
if [ "$service_details_status" -eq 0 ] && contains "$service_details_output" 'KAFKA / DETAILS' && contains "$service_details_output" 'KAFKA / ACCESS' && contains "$service_details_output" 'KAFKA / NATIVE' && [ "$root_details_status" -eq 0 ] && contains "$root_details_output" 'BASH_GOD / DETAILS' && contains "$root_details_output" 'GENERAL / HOST' && contains "$root_details_output" 'KAFKA / OFFSET'; then
  pass 'details expands root, service, and group scopes'
else
  fail 'details expands root, service, and group scopes'
fi

access_output="$(GOD_COLOR=never "$god_cli" kafka access)"
access_details_output="$(GOD_COLOR=never "$god_cli" kafka access --details)"
general_host_output="$(GOD_COLOR=never "$god_cli" general host)"
if contains "$access_details_output" 'NOTE' && contains "$access_details_output" 'approved access path'; then
  pass 'details retains command notes'
else
  fail 'details retains command notes'
fi

if not_contains "$access_output" '$ hostname' && not_contains "$access_output" 'LOCAL' && contains "$general_host_output" '$ hostname'; then
  pass 'generic hostname knowledge is outside Kafka'
else
  fail 'generic hostname knowledge is outside Kafka'
fi

if [ "$access_command_count" -eq 1 ] && contains "$access_output" '$ ssh <kafka_host>'; then
  pass 'Kafka access exposes a portable SSH destination placeholder'
else
  fail 'Kafka access exposes a portable SSH destination placeholder'
fi

produce_output="$(GOD_COLOR=never "$god_cli" kafka produce)"
produce_query_output="$(GOD_COLOR=never "$god_cli" kafka q 'Create a topic and publish message' --tree --full)"
publish_message_query_output="$(GOD_COLOR=never "$god_cli" kafka q 'publish message' --tree --full)"
if contains "$produce_output" "$ echo '<message>' | ./kafka-console-producer.sh --bootstrap-server localhost:9092 --topic <topic_name>" && contains "$produce_query_output" 'results (1 matching operations)' && contains "$produce_query_output" 'Publish one message' && not_contains "$produce_query_output" 'Publish a keyed message' && contains "$publish_message_query_output" "echo '<message>' | ./kafka-console-producer.sh" && contains "$publish_message_query_output" "echo '<key>:<value>' | ./kafka-console-producer.sh" && contains "$publish_message_query_output" '< messages.txt' && not_contains "$produce_output" 'printf ' && not_contains "$produce_query_output" 'printf ' && not_contains "$publish_message_query_output" 'printf '; then
  pass 'producer knowledge makes each message source visible'
else
  fail 'producer knowledge makes each message source visible'
fi

delete_output="$(GOD_COLOR=never "$god_cli" q --any delete --tree)"
warn_output="$(GOD_COLOR=never "$god_cli" q --all offset reset --tree)"
invalid_risk_count="$(LC_ALL=C awk '/^@risk / && $2 !~ /^(WRITE|WARN|DELETE)$/ { count++ } END { print count + 0 }' "$kafka_catalog")"
if contains "$delete_output" '[DELETE]' && contains "$warn_output" '[WARN]' && [ "$invalid_risk_count" -eq 0 ]; then
  pass 'risk labels use specific WRITE, WARN, and DELETE vocabulary'
else
  fail 'risk labels use specific WRITE, WARN, and DELETE vocabulary'
fi

health_output="$(GOD_COLOR=never "$god_cli" kafka health)"
zookeeper_output="$(GOD_COLOR=never "$god_cli" kafka zookeeper)"
if not_contains "$health_output" 'MODERN' && contains "$zookeeper_output" '[LEGACY]' && not_contains "$zookeeper_output" 'LEGACY-ZK'; then
  pass 'normal modes stay silent while legacy syntax is highlighted'
else
  fail 'normal modes stay silent while legacy syntax is highlighted'
fi

search_output="$(GOD_COLOR=never "$god_cli" q consumer lag)"
if contains "$search_output" 'MATCHING OPERATIONS' && contains "$search_output" "god kafka offset $offset_lag_number" && not_contains "$search_output" './kafka-consumer-groups.sh' && not_contains "$search_output" "$home_slogan"; then
  pass 'smart search returns compact ranked routes'
else
  fail 'smart search returns compact ranked routes'
fi

remembered_query_output="$(GOD_COLOR=never "$god_cli" -q 'Get all consumers from a group')"
if contains "$remembered_query_output" 'Smart search: Get all consumers from a group' && contains "$remembered_query_output" "god kafka groups $group_members_number" && contains "$remembered_query_output" 'Show active members of a consumer group'; then
  pass 'conversational remembered wording finds the associated command'
else
  fail 'conversational remembered wording finds the associated command'
fi

broker_query_output="$(GOD_COLOR=never "$god_cli" kafka q "Get all consumers in a broker")"
broker_query_first_result="$(printf '%s\n' "$broker_query_output" | LC_ALL=C awk '/^  god / { print; exit }')"
broker_query_expected_first="$(printf '  %-32s %s' "god kafka groups $group_list_number" 'List consumer groups')"
if contains "$broker_query_output" 'Smart search: Get all consumers in a broker' && [ "$broker_query_first_result" = "$broker_query_expected_first" ]; then
  pass 'scoped remembered intent ranks list consumer groups first'
else
  fail 'scoped remembered intent ranks list consumer groups first'
fi

# R09 owns all helper-picker lifecycle assertions in its focused suite.
# The aggregate smoke suite keeps only non-presentation contracts here.
reviewed_execute_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_execute_confirm() { printf "UNEXPECTED CONFIRM\\n"; return 1; }
  _god_execute_run() { printf "REVIEWED RUN|%s|%s\\n" "$1" "$2"; }
  _god_execute_resolved "displayed command" "safe-template" "" 1 "safe-value"
' _ "$project_dir" 2>&1)"
execution_stream_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_execute_run "printf stdout-visible; printf stderr-visible >&2"
' _ "$project_dir" 2>&1)"
placeholder_resolution_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_resolve_prompt_value() {
    printf "PLACEHOLDER PROMPT|%s|%s\\n" "$1" "$2" >&2
    printf "example-namespace\\n"
  }
  _god_resolve_command_interactive k8s "$2" pods "$3" /resolved/kubectl "get all pods"
' _ "$project_dir" "$k8s_catalog" "$k8s_list_pods_number" 2>&1)"
unresolved_placeholder_guard_output="$(bash -c '
  . "$1/BASH_GOD.sh"
  _god_execute_resolved "kubectl get pods -n <namespace>" "kubectl get pods -n <namespace>" "" 1
  printf "UNRESOLVED STATUS:%s\\n" "$?"
' _ "$project_dir" 2>&1)"
readline_fixture="$smoke_home/native-editor-fallback"
readline_bin="$readline_fixture/bin"
readline_fd="$readline_fixture/tty"
mkdir -p "$readline_bin"
printf '#!/usr/bin/env bash\nprintf "%%s --edited" "$BASH_GOD_EDIT_INITIAL" > "$BASH_GOD_EDIT_RESULT"\n' > "$readline_bin/zsh"
chmod 0755 "$readline_bin/zsh"
: > "$readline_fd"
readline_fallback_output="$(PATH="$readline_bin:$PATH" bash -c '
  . "$1/src/ui/input.sh"
  help() { return 1; }
  exec 3<> "$2"
  _god_menu_readline_edit "seed command"
  printf "RESULT READ|%s\\n" "$_god_menu_edited_command"
' _ "$project_dir" "$readline_fd")"

# In ordinary CI this nested command has no controlling terminal, so its
# stdout/stderr must be captured by the fallback path below. When a maintainer
# runs the aggregate suite from a PTY, the reviewed executor correctly hands
# those streams straight to /dev/tty instead; tui-pty-smoke.sh owns that live
# stream assertion later in this same suite.
execution_stream_contract=0
if contains "$execution_stream_output" 'stdout-visible' && \
   contains "$execution_stream_output" 'stderr-visible'; then
  execution_stream_contract=1
elif [ -t 1 ]; then
  execution_stream_contract=1
fi

if contains "$reviewed_execute_output" 'REVIEWED RUN|safe-template|safe-value' && \
   not_contains "$reviewed_execute_output" 'UNEXPECTED CONFIRM' && \
   [ "$execution_stream_contract" -eq 1 ]; then
  pass 'reviewed execution uses its prepared safe template and preserves child output'
else
  fail 'reviewed execution uses its prepared safe template and preserves child output'
fi

if contains "$placeholder_resolution_output" 'PLACEHOLDER PROMPT|Namespace containing the pods|<namespace>' && \
   contains "$placeholder_resolution_output" 'DISPLAY	kubectl get pods -n example-namespace' && \
   contains "$placeholder_resolution_output" 'TEMPLATE	kubectl get pods -n "${1}"' && \
   contains "$placeholder_resolution_output" 'VALUE	example-namespace' && \
   contains "$unresolved_placeholder_guard_output" 'unresolved placeholder and was not run' && \
   contains "$unresolved_placeholder_guard_output" 'UNRESOLVED STATUS:2'; then
  pass 'interactive placeholder resolution is explicit and unresolved placeholders never execute'
else
  fail 'interactive placeholder resolution is explicit and unresolved placeholders never execute'
fi

if contains "$readline_fallback_output" 'RESULT READ|seed command --edited'; then
  pass 'native readline editor retains its deterministic zsh fallback'
else
  fail 'native readline editor retains its deterministic zsh fallback'
fi

service_query_output="$(GOD_COLOR=never "$god_cli" kafka q 'describe topic')"
service_query_tree_output="$(GOD_COLOR=never "$god_cli" kafka -q 'describe topic' --tree)"
service_query_details_output="$(GOD_COLOR=never "$god_cli" kafka q 'unavailable leader' --details)"
group_query_full_output="$(GOD_COLOR=never "$god_cli" kafka topics q 'describe topic' --tree --full)"
group_query_details_output="$(GOD_COLOR=never "$god_cli" kafka topics -q 'describe topic' --details)"
group_query_help_output="$(GOD_COLOR=never "$god_cli" kafka topics q --help)"
if contains "$service_query_output" 'KAFKA SEARCH RESULTS' && not_contains "$service_query_output" 'god general ' && contains "$service_query_tree_output" 'KAFKA SEARCH TREE' && contains "$service_query_details_output" 'KAFKA SEARCH DETAILS' && contains "$group_query_full_output" 'KAFKA / TOPICS SEARCH TREE' && contains "$group_query_full_output" '$ ./kafka-topics.sh' && not_contains "$group_query_full_output" 'config (' && contains "$group_query_details_output" 'KAFKA / TOPICS SEARCH DETAILS' && contains "$group_query_details_output" 'PARAMETER' && contains "$group_query_help_output" 'god kafka topics q WORDS'; then
  pass 'q and -q search from service and group scope with every search view'
else
  fail 'q and -q search from service and group scope with every search view'
fi

remembered_tree_output="$(GOD_COLOR=never "$god_cli" q 'Get all consumers from a group' --tree)"
remembered_full_tree_output="$(GOD_COLOR=never "$god_cli" q 'Get all consumers from a group' --tree --full)"
remembered_details_output="$(GOD_COLOR=never "$god_cli" q unavailable leader --details)"
remembered_keys_output="$(GOD_COLOR=never "$god_cli" q unavailable leader --keys)"
remembered_help_output="$(GOD_COLOR=never "$god_cli" q unavailable leader --help)"
if contains "$remembered_tree_output" 'SEARCH TREE' && contains "$remembered_tree_output" 'groups (5)' && not_contains "$remembered_tree_output" '$ ./kafka-consumer-groups.sh' && not_contains "$remembered_tree_output" 'group --tree' && contains "$remembered_full_tree_output" '$ ./kafka-consumer-groups.sh' && contains "$remembered_details_output" 'SEARCH DETAILS' && contains "$remembered_details_output" 'PARAMETER' && contains "$remembered_keys_output" 'SEARCH VIEWS' && contains "$remembered_help_output" 'SEARCH MODES'; then
  pass 'every trailing search view key is parsed instead of becoming query text'
else
  fail 'every trailing search view key is parsed instead of becoming query text'
fi

all_query_output="$(GOD_COLOR=never "$god_cli" q --all consumer group)"
any_query_output="$(GOD_COLOR=never "$god_cli" q --any consumer group)"
exact_query_output="$(GOD_COLOR=never "$god_cli" q --exact 'active members')"
search_help_output="$(GOD_COLOR=never "$god_cli" q --help)"
if contains "$all_query_output" 'Every word: consumer group' && contains "$any_query_output" 'Any word: consumer group' && contains "$all_query_output" "god kafka groups $group_members_number" && contains "$exact_query_output" 'Exact phrase: active members' && contains "$exact_query_output" "god kafka groups $group_members_number" && contains "$search_help_output" 'native commands, parameters, optional flags, notes, modes, and risk labels'; then
  pass 'any-word, all-word, exact-phrase, and search-help modes'
else
  fail 'any-word, all-word, exact-phrase, and search-help modes'
fi

short_query_output="$(GOD_COLOR=never "$god_cli" -q unavailable leader)"
if contains "$short_query_output" 'MATCHING OPERATIONS' && contains "$short_query_output" "god kafka health $health_unavailable_number"; then
  pass 'short query flag returns the exact numbered route'
else
  fail 'short query flag returns the exact numbered route'
fi

legacy_query_status=0
GOD_COLOR=never "$god_cli" query offset >/dev/null 2>&1 || legacy_query_status=$?
if [ "$legacy_query_status" -eq 2 ]; then
  pass 'semantic lookup is limited to q and -q'
else
  fail 'semantic lookup is limited to q and -q'
fi

regex_output="$(GOD_COLOR=never "$god_cli" q --regex -- 'offset|lag')"
if contains "$regex_output" 'Regex: offset|lag' && contains "$regex_output" "god kafka offset $offset_lag_number"; then
  pass 'explicit regex search'
else
  fail 'explicit regex search'
fi

tree_output="$(GOD_COLOR=never "$god_cli" kafka --tree)"
tree_lines="$(printf '%s\n' "$tree_output" | LC_ALL=C awk 'END { print NR }')"
root_tree_output="$(GOD_COLOR=never "$god_cli" --tree)"
group_tree_output="$(GOD_COLOR=never "$god_cli" kafka health --tree)"
full_tree_output="$(GOD_COLOR=never "$god_cli" kafka --tree --full)"
group_full_tree_output="$(GOD_COLOR=never "$god_cli" kafka native --tree --full)"
tree_alias_output="$(GOD_COLOR=never "$god_cli" tree kafka native --full)"
if contains "$root_tree_output" 'BASH_GOD (' && contains "$tree_output" "offset ($offset_command_count)" && contains "$tree_output" "native ($native_command_count)" && not_contains "$tree_output" 'Show consumer-group offsets and lag' && [ "$tree_lines" -le 24 ] && contains "$group_tree_output" "$health_unavailable_label Find partitions without an available leader" && not_contains "$group_tree_output" '$ ' && contains "$full_tree_output" 'Show kafka-metadata-quorum native help' && contains "$full_tree_output" '$ ./kafka-consumer-groups.sh --help' && contains "$group_full_tree_output" '$ ./kafka-topics.sh --help' && [ "$group_full_tree_output" = "$tree_alias_output" ]; then
  pass 'progressive tree stays compact and reveals detail by path'
else
  fail 'progressive tree stays compact and reveals detail by path'
fi

root_keys_output="$(GOD_COLOR=never "$god_cli" --keys)"
service_keys_output="$(GOD_COLOR=never "$god_cli" kafka --keys)"
group_keys_output="$(GOD_COLOR=never "$god_cli" kafka native --keys)"
service_search_keys_output="$(GOD_COLOR=never "$god_cli" kafka q unavailable --keys)"
group_search_keys_output="$(GOD_COLOR=never "$god_cli" kafka health q unavailable --keys)"
if contains "$root_keys_output" 'VIEW KEYS' && contains "$root_keys_output" 'god --details' && contains "$root_keys_output" 'god q --help' && contains "$service_keys_output" 'god kafka --details' && contains "$service_keys_output" 'god kafka --tree --full' && contains "$group_keys_output" 'god kafka native --details' && contains "$group_keys_output" 'god kafka native --tree --full' && contains "$service_search_keys_output" 'god kafka q WORDS --tree --full' && contains "$group_search_keys_output" 'god kafka health q WORDS --details'; then
  pass 'view keys are available at root, service, group, and search scope'
else
  fail 'view keys are available at root, service, group, and search scope'
fi

GOD_COLOR=never "$god_cli" q zzzxxyyqqq >/dev/null 2>&1
query_status=$?
GOD_COLOR=never "$god_cli" no-such-service >/dev/null 2>&1
route_status=$?
GOD_COLOR=never "$god_cli" q --regex offset lag >/dev/null 2>&1
regex_status=$?
GOD_COLOR=never "$god_cli" q '' >/dev/null 2>&1
empty_status=$?
GOD_COLOR=never "$god_cli" kafka consume 99 >/dev/null 2>&1
entry_status=$?
if [ "$query_status" -eq 1 ] && [ "$route_status" -eq 2 ] && [ "$regex_status" -eq 2 ] && [ "$empty_status" -eq 2 ] && [ "$entry_status" -eq 2 ]; then
  pass 'search and usage exit statuses'
else
  fail 'search and usage exit statuses'
fi

root_full_error="$(GOD_COLOR=never "$god_cli" --full 2>&1)"
root_full_status=$?
service_full_error="$(GOD_COLOR=never "$god_cli" kafka --full 2>&1)"
service_full_status=$?
group_full_error="$(GOD_COLOR=never "$god_cli" kafka offset --full 2>&1)"
group_full_status=$?
if [ "$root_full_status" -eq 2 ] && [ "$service_full_status" -eq 2 ] && [ "$group_full_status" -eq 2 ] && contains "$root_full_error" '--full must follow --tree' && contains "$service_full_error" '--full must follow --tree' && contains "$group_full_error" '--full must follow --tree'; then
  pass 'misplaced --full is recognized consistently at every scope'
else
  fail 'misplaced --full is recognized consistently at every scope'
fi

control_character="$(printf '\033')"
unsafe_output="$(GOD_COLOR="invalid${control_character}" "$god_cli" help 2>&1)"
unsafe_color_status=$?
unsafe_route_output="$(GOD_COLOR=never "$god_cli" "bad${control_character}route" 2>&1)"
unsafe_route_status=$?
if [ "$unsafe_color_status" -eq 2 ] && [ "$unsafe_route_status" -eq 2 ] && not_contains "$unsafe_output" "$control_character" && not_contains "$unsafe_route_output" "$control_character"; then
  pass 'invalid input cannot inject terminal controls'
else
  fail 'invalid input cannot inject terminal controls'
fi

arithmetic_marker='ARITHMETIC_INJECTION'
unsafe_depth_output="$(env '_GOD_CALL_DEPTH=x[$(printf ARITHMETIC_INJECTION >&2)]' GOD_COLOR=never "$god_cli" --version 2>&1)"
unsafe_depth_status=$?
if [ "$unsafe_depth_status" -eq 0 ] && contains "$unsafe_depth_output" "BASH_GOD $expected_version" && not_contains "$unsafe_depth_output" "$arithmetic_marker"; then
  pass 'untrusted call-depth state remains inert'
else
  fail 'untrusted call-depth state remains inert'
fi

enumeration_status=0
bash -c '. "$1/src/core.sh"; _god_catalog_files() { return 7; }; GOD_COLOR=never god help >/dev/null' _ "$project_dir" 2>/dev/null || enumeration_status=$?
if [ "$enumeration_status" -eq 2 ]; then
  pass 'catalog enumeration failures propagate'
else
  fail 'catalog enumeration failures propagate'
fi

bash_source_output="$(bash -c '. "$1/BASH_GOD.sh"' _ "$project_dir" 2>&1)"
bash_source_status=$?
zsh_source_output="$(zsh -c '. "$1/BASH_GOD.sh"' _ "$project_dir" 2>&1)"
zsh_source_status=$?
if [ "$bash_source_status" -eq 0 ] && [ "$zsh_source_status" -eq 0 ] && [ -z "$bash_source_output" ] && [ -z "$zsh_source_output" ]; then
  pass 'sourcing is silent in Bash and zsh'
else
  fail 'sourcing is silent in Bash and zsh'
fi

zsh_search_status=0
zsh_search_output="$(zsh -f -c '. "$1/BASH_GOD.sh"; GOD_COLOR=never god q "Get all consumers from a group"' _ "$project_dir" 2>&1)" || zsh_search_status=$?
if [ "$zsh_search_status" -eq 0 ] && contains "$zsh_search_output" 'Show active members of a consumer group' && not_contains "$zsh_search_output" 'could not enumerate the catalog directory'; then
  pass 'search works from a sourced zsh without shadowing its special path array'
else
  fail 'search works from a sourced zsh without shadowing its special path array'
fi

plain_output="$(GOD_COLOR=never "$god_cli" kafka offset)"
color_output="$(unset NO_COLOR; GOD_COLOR=always "$god_cli" kafka offset)"
no_color_output="$(NO_COLOR=1 GOD_COLOR=always "$god_cli" kafka offset)"
escape_character="$(printf '\033')"
case "$plain_output" in
  *"$escape_character"*) plain_has_color=1 ;;
  *) plain_has_color=0 ;;
esac
case "$color_output" in
  *"$escape_character"*) color_has_color=1 ;;
  *) color_has_color=0 ;;
esac
case "$no_color_output" in
  *"$escape_character"*) no_color_has_color=1 ;;
  *) no_color_has_color=0 ;;
esac
if [ "$plain_has_color" -eq 0 ] && [ "$color_has_color" -eq 1 ] && [ "$no_color_has_color" -eq 0 ]; then
  pass 'color can be disabled, forced, or authoritatively suppressed by NO_COLOR'
else
  fail 'color can be disabled, forced, or authoritatively suppressed by NO_COLOR'
fi

color_logo_output="$(bash -c 'unset NO_COLOR; . "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=always god' _ "$project_dir")"
plain_logo_output="$(NO_COLOR=1 bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=always god' _ "$project_dir")"
ascii_logo_output="$(LC_ALL=C bash -c '. "$1/BASH_GOD.sh"; _god_stdout_is_terminal() { return 0; }; GOD_COLOR=never god' _ "$project_dir")"
ivory_row="$(printf '\033[1;38;5;255m')"
gold_row="$(printf '\033[1;38;5;220m')"
if contains "$color_logo_output" "$ivory_row$logo_first" && contains "$color_logo_output" "$gold_row$logo_last" && contains "$color_logo_output" "${gold_row}v${expected_version}" && contains "$plain_logo_output" "$logo_first" && contains "$plain_logo_output" "$home_identity" && contains "$ascii_logo_output" "$home_identity_ascii" && not_contains "$plain_logo_output" "$escape_character"; then
  pass 'home identity uses one ivory-to-gold gradient with plain and ASCII forms'
else
  fail 'home identity uses one ivory-to-gold gradient with plain and ASCII forms'
fi

ascii_output="$(LC_ALL=C GOD_COLOR=never "$god_cli" kafka offset)"
if contains "$ascii_output" '+------------------------------------------------------------------------+' && not_contains "$ascii_output" '╭'; then
  pass 'ASCII fallback'
else
  fail 'ASCII fallback'
fi

if ! printf '%s\n' "$group_output" | LC_ALL=C awk '/ \\$/ { found = 1 } END { exit(found ? 0 : 1) }'; then
  pass 'commands remain single physical lines without injected continuations'
else
  fail 'commands remain single physical lines without injected continuations'
fi

if [ "$kafka_group_count" -ge 15 ] && [ "$kafka_command_count" -ge 78 ]; then
  pass 'expanded Kafka catalog coverage'
else
  fail 'expanded Kafka catalog coverage'
fi

mongo_service_output="$(GOD_COLOR=never "$god_cli" mongo service)"
mongo_backup_output="$(GOD_COLOR=never "$god_cli" mongo backup)"
mongo_replica_output="$(GOD_COLOR=never "$god_cli" mongo replica)"
if contains "$mongo_service_output" '$ systemctl status mongod' && contains "$mongo_backup_output" '$ mongodump ' && contains "$mongo_backup_output" '$ mongorestore ' && contains "$mongo_backup_output" '[WRITE]' && contains "$mongo_replica_output" "\$ mongosh --host <host> --port 27017 --quiet --eval 'rs.status()'"; then
  pass 'MongoDB catalog covers executable service, replica-set, dump, and restore commands'
else
  fail 'MongoDB catalog covers executable service, replica-set, dump, and restore commands'
fi

k8s_logs_output="$(GOD_COLOR=never "$god_cli" k8s logs)"
k8s_configmaps_output="$(GOD_COLOR=never "$god_cli" k8s configmaps)"
k8s_events_output="$(GOD_COLOR=never "$god_cli" k8s events)"
if contains "$k8s_logs_output" '$ kubectl logs -f <pod_name> -n <namespace>' && contains "$k8s_configmaps_output" '$ kubectl get configmap <configmap_name> -n <namespace> -o yaml' && contains "$k8s_events_output" 'kubectl events'; then
  pass 'Kubernetes catalog covers logs, ConfigMaps, and events'
else
  fail 'Kubernetes catalog covers logs, ConfigMaps, and events'
fi

general_resources_output="$(GOD_COLOR=never "$god_cli" general resources)"
if contains "$general_resources_output" '$ free -h' && contains "$general_resources_output" '$ lscpu' && contains "$general_resources_output" '$ nvidia-smi' && contains "$general_resources_output" '$ df -h' && contains "$general_resources_output" '$ iostat -xz 1 3'; then
  pass 'general resources keeps CPU, memory, GPU, and storage together'
else
  fail 'general resources keeps CPU, memory, GPU, and storage together'
fi

network_ports_output="$(GOD_COLOR=never "$god_cli" network ports)"
network_dns_output="$(GOD_COLOR=never "$god_cli" network dns)"
network_help_output="$(GOD_COLOR=never "$god_cli" network)"
network_search_output="$(GOD_COLOR=never "$god_cli" network q 'check listening port')"
aws_identity_output="$(GOD_COLOR=never "$god_cli" aws identity)"
aws_route53_output="$(GOD_COLOR=never "$god_cli" aws route53)"
aws_native_output="$(GOD_COLOR=never "$god_cli" aws native)"
aws_search_output="$(GOD_COLOR=never "$god_cli" q 'private hosted zones')"
network_route53_status=0
GOD_COLOR=never "$god_cli" network route53 >/dev/null 2>&1 || network_route53_status=$?
if contains "$network_ports_output" '$ ss -tulnp' && contains "$network_ports_output" 'lsof -nP -iTCP:<port_number>' && contains "$network_dns_output" '$ dig +short <hostname> A' && not_contains "$network_help_output" 'route53' && [ "$network_route53_status" -eq 2 ] && contains "$network_search_output" 'Check which Linux process is listening on one TCP port' && contains "$aws_identity_output" '$ aws sts get-caller-identity' && contains "$aws_route53_output" 'list-hosted-zones' && contains "$aws_route53_output" 'list-resource-record-sets' && not_contains "$aws_route53_output" 'change-resource-record-sets' && contains "$aws_native_output" '$ aws route53 help' && contains "$aws_search_output" 'god aws route53'; then
  pass 'AWS owns Route 53 knowledge while network keeps generic DNS and ports'
else
  fail 'AWS owns Route 53 knowledge while network keeps generic DNS and ports'
fi

elasticsearch_service_output="$(GOD_COLOR=never "$god_cli" elasticsearch service)"
elasticsearch_shards_output="$(GOD_COLOR=never "$god_cli" elasticsearch shards)"
elasticsearch_search_output="$(GOD_COLOR=never "$god_cli" elasticsearch search)"
if contains "$elasticsearch_service_output" "curl -sS 'http://localhost:9200/'" && contains "$elasticsearch_shards_output" '/_cluster/allocation/explain?pretty' && contains "$elasticsearch_search_output" '/<index_name>/_search?pretty' && not_contains "$elasticsearch_search_output" '[WRITE]'; then
  pass 'Elasticsearch catalog covers service, shard, and bounded search inspection'
else
  fail 'Elasticsearch catalog covers service, shard, and bounded search inspection'
fi

if [ -f "$aws_catalog" ] && [ -f "$kafka_catalog" ] && [ -f "$general_catalog" ] && [ -f "$elasticsearch_catalog" ] && [ -f "$k8s_catalog" ] && [ -f "$mongo_catalog" ] && [ -f "$network_catalog" ] && [ ! -e "$project_dir/catalog/kafka.god" ] && [ ! -e "$project_dir/catalog/general.god" ]; then
  pass 'each service owns catalog SERVICE/service.god'
else
  fail 'each service owns catalog SERVICE/service.god'
fi

if [ -f "$catalog_module" ] && [ -f "$render_module" ] && [ -f "$art_module" ] && \
   [ -f "$search_module" ] && [ -f "$interaction_module" ] && [ -f "$resolve_module" ] && \
   [ -f "$execute_module" ] && [ -f "$eligibility_module" ] && [ -f "$input_module" ] && [ -f "$tree_module" ] && \
   [ -f "$tui_module" ] && \
   ! LC_ALL=C awk '/^_god_(validate_catalog|print_root_help|print_home_art|search_catalog|interaction_offer_search_results|resolve_reviewed_model|execute_reviewed_model|menu_rich_read_key|render_tree_groups)\(\)/ { found = 1 } END { exit(found ? 0 : 1) }' "$project_dir/src/core.sh"; then
  pass 'shared responsibilities are separate sourced modules'
else
  fail 'shared responsibilities are separate sourced modules'
fi

empty_catalog_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-empty.XXXXXX")" || exit 1
bash -O failglob -c '. "$1/src/core.sh"; _BASH_GOD_CATALOG_DIR="$2"; GOD_COLOR=never god help >/dev/null' _ "$project_dir" "$empty_catalog_dir"
bash_empty_status=$?
zsh -c 'setopt nomatch; . "$1/src/core.sh"; _BASH_GOD_CATALOG_DIR="$2"; GOD_COLOR=never god help >/dev/null' _ "$project_dir" "$empty_catalog_dir"
zsh_empty_status=$?
rmdir "$empty_catalog_dir" 2>/dev/null || true
if [ "$bash_empty_status" -eq 0 ] && [ "$zsh_empty_status" -eq 0 ]; then
  pass 'empty catalog works with failglob and zsh nomatch'
else
  fail 'empty catalog works with failglob and zsh nomatch'
fi

run_focused_suite k8s-aws-catalog-smoke.sh
run_focused_suite mongo-catalog-smoke.sh
run_focused_suite path-services-catalog-smoke.sh
run_focused_suite execution-rollout-smoke.sh
run_focused_suite refactor-boundaries-smoke.sh
run_focused_suite tui-adapter-smoke.sh
run_focused_suite tui-pty-smoke.sh
run_focused_suite ../docs/demo/capture-interactive-picker.sh
run_focused_suite r09-picker-retirement-smoke.sh
run_focused_suite eligibility-smoke.sh
run_focused_suite r12-eligibility-presentation-smoke.sh
run_focused_suite r13-catalog-requirements-smoke.sh
run_focused_suite ../packaging/tests/installed-tui-pty-smoke.sh

if [ "$failures" -eq 0 ]; then
  printf '\n%d checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d checks failed.\n' "$failures" "$checks" >&2
exit 1
