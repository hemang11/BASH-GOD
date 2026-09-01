#!/usr/bin/env bash

# Knowledge-rendering regression checks. No catalog command is executed.

test_file="${BASH_SOURCE[0]}"
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
project_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
god_cli="$project_dir/god"
expected_version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$project_dir/bash_god/core.sh")"
aws_catalog="$project_dir/bash_god/catalog/aws/service.god"
kafka_catalog="$project_dir/bash_god/catalog/kafka/service.god"
general_catalog="$project_dir/bash_god/catalog/general/service.god"
elasticsearch_catalog="$project_dir/bash_god/catalog/elasticsearch/service.god"
k8s_catalog="$project_dir/bash_god/catalog/k8s/service.god"
mongo_catalog="$project_dir/bash_god/catalog/mongo/service.god"
network_catalog="$project_dir/bash_god/catalog/network/service.god"
catalog_module="$project_dir/bash_god/catalog.sh"
render_module="$project_dir/bash_god/render.sh"
art_module="$project_dir/bash_god/art.sh"
search_module="$project_dir/bash_god/search.sh"
tree_module="$project_dir/bash_god/tree.sh"
license_file="$project_dir/LICENSE"
[ -f "$license_file" ] || license_file="$project_dir/bash_god/LICENSE"

# Isolated from the real machine's discover cache and per-service config
# overrides (~/.local/state/bash-god, ~/.config/bash-god): a service resolved
# for real on the developer's own machine must not silently flip these
# fixtures from the unresolved-service assertions they're written against.
smoke_home="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-smoke.XXXXXX" 2>/dev/null)" || exit 1
trap 'rm -rf -- "$smoke_home"' EXIT
export HOME="$smoke_home"
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
display_only_catalog="$smoke_home/display-only.god"
printf '%s\n' \
  '@title Executable fixture' \
  '@description' \
  'Validator fixture.' \
  '@discover' \
  'probe | fixture.sh | Fixture probe' \
  'root | /tmp | Fixture root' \
  '@group demo' \
  '@command Missing compatibility floor' \
  '@mode LOCAL' \
  '@description' \
  'Deliberately omits the required floor.' \
  '@run' \
  'printf fixture' \
  '@end' > "$missing_since_catalog"
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
display_only_status=0
bash -c '. "$1"; _god_validate_catalog "$2"' _ "$catalog_module" "$display_only_catalog" >/dev/null 2>&1 || display_only_status=$?
if [ "$kafka_since_count" -eq "$kafka_command_count" ] && [ "$missing_since_status" -ne 0 ] && \
   contains "$missing_since_output" 'has no @since; every command in an executable catalog must declare its compatibility floor' && \
   [ "$display_only_status" -eq 0 ]; then
  pass 'every executable-service command requires an explicit compatibility floor'
else
  fail 'every executable-service command requires an explicit compatibility floor'
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
   contains "$paths_output" 'Executable services BASH_GOD can detect and the directories they use.' && \
   not_contains "$paths_output" '@discover'; then
  pass 'resolved-path view uses operator language instead of catalog grammar'
else
  fail 'resolved-path view uses operator language instead of catalog grammar'
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
if contains "$access_details_output" 'NOTE' && contains "$access_details_output" 'approved internal hop'; then
  pass 'details retains command notes'
else
  fail 'details retains command notes'
fi

if not_contains "$access_output" '$ hostname' && not_contains "$access_output" 'LOCAL' && contains "$general_host_output" '$ hostname'; then
  pass 'generic hostname knowledge is outside Kafka'
else
  fail 'generic hostname knowledge is outside Kafka'
fi

if [ "$access_command_count" -eq 1 ] && contains "$access_output" '$ ssh ontic-preprod-us-west1-db'; then
  pass 'Kafka access contains only an explicit SSH destination'
else
  fail 'Kafka access contains only an explicit SSH destination'
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

# A resolved service gets one rich, title-first picker on an interactive
# terminal. A redirected/no-TTY invocation must remain the old static table;
# it must never suppress the rows and leave only a banner behind.
# This block stubs TTY presence. Pair it with a capable TERM so CI's default
# TERM=dumb does not correctly disable the exact picker being exercised.
export TERM='xterm-256color'
rich_fixture="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-rich.XXXXXX" 2>/dev/null)" || exit 1
rich_bin="$rich_fixture/kafka/bin"
mkdir -p "$rich_bin" "$rich_fixture/.local/state/bash-god"
printf '#!/usr/bin/env bash\nprintf "kafka-topics 3.9.0\\n"\n' > "$rich_bin/kafka-topics.sh"
chmod 0755 "$rich_bin/kafka-topics.sh"
for rich_tool in kafka-consumer-groups.sh kafka-console-consumer.sh kafka-broker-api-versions.sh; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$rich_bin/$rich_tool"
  chmod 0755 "$rich_bin/$rich_tool"
done
printf 'kafka.path=%s\nkafka.version=3.9.0\n' "$rich_bin" > "$rich_fixture/.local/state/bash-god/execution-paths"

rich_fallback_output="$(HOME="$rich_fixture" GOD_COLOR=never "$god_cli" kafka q 'Get all consumers in a broker')"
rich_picker_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_menu_select_rich() {
    "$4" 1 || return $?
    first_detail=$_god_menu_provider_detail
    "$4" 2 || return $?
    printf "RICH PICKER ROWS\\n%s\\nRICH PICKER DETAILS\\n%s\\nSECOND RICH PICKER DETAILS\\n%s\\n" \
      "$1" "$first_detail" "$_god_menu_provider_detail"
    [ "$first_detail" != "$_god_menu_provider_detail" ] || printf "DETAILS DID NOT CHANGE\\n"
    _god_menu_choice=-1
    return 0
  }
  god kafka q "Get all consumers in a broker"
' _ "$project_dir")"
rich_enter_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_menu_select_rich() {
    _god_menu_choice=0
    _god_menu_edited_command=""
    return 0
  }
  _god_execute_resolved() {
    printf "FAST RESOLVED EXECUTION|%s|%s|%s|%s\\n" "$1" "$2" "$3" "$4"
  }
  _god_execute_command() { printf "UNEXPECTED SLOW EXECUTION\\n"; }
  god kafka q "Get all consumers in a broker"
' _ "$project_dir")"
rich_edit_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_menu_select_rich() {
    _god_menu_choice=0
    _god_menu_edited_command="printf edited-command"
    return 0
  }
  _god_execute_edited() {
    printf "EDITED COMMAND|%s|%s|%s\\n" "$1" "$2" "$3"
  }
  _god_execute_resolved() { printf "UNEXPECTED PREPARED EXECUTION\\n"; }
  god kafka q "Get all consumers in a broker"
' _ "$project_dir")"
rich_pending_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_menu_select_rich() {
    _god_menu_choice=0
    _god_menu_edited_command=""
    return 0
  }
  _god_execute_command() {
    printf "PENDING EXECUTION|%s|%s|%s\\n" "$3" "$4" "$7"
  }
  _god_execute_resolved() { printf "UNEXPECTED PREPARED EXECUTION\\n"; }
  god kafka consume q "Read a topic from beginning"
' _ "$project_dir")"
rich_unmapped_placeholder_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_resolve_prompt_value() {
    printf "PLACEHOLDER PROMPT|%s|%s\\n" "$1" "$2" >&2
    printf "ontic-app\\n"
  }
  _god_resolve_command_interactive k8s "$2" pods "$3" /resolved/kubectl "get all pods"
' _ "$project_dir" "$k8s_catalog" "$k8s_list_pods_number" 2>&1)"
rich_unresolved_placeholder_guard_output="$(bash -c '
  . "$1/BASH_GOD.sh"
  _god_execute_resolved "kubectl get pods -n <namespace>" "kubectl get pods -n <namespace>" "" 1
  printf "UNRESOLVED STATUS:%s\\n" "$?"
' _ "$project_dir" 2>&1)"
rich_failure_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_discover_version() { printf "1.1.0\n"; }
  _god_menu_select_rich() {
    _god_menu_choice=0
    _god_menu_edited_command=""
    return 0
  }
  _god_execute_resolved() {
    printf "VISIBLE CHILD ERROR\n" >&2
    return 47
  }
  god kafka q "broker API compatibility"
  printf "RICH FAILURE STATUS:%s\n" "$?"
' _ "$project_dir" 2>&1)"
rich_version_resolution_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_resolve_command kafka "$2" setup "$3" "$4" "find version"
' _ "$project_dir" "$kafka_catalog" "$setup_version_number" "$rich_bin")"
rich_tools_resolution_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_resolve_command kafka "$2" setup "$3" "$4" "list installed tools"
' _ "$project_dir" "$kafka_catalog" "$setup_tools_number" "$rich_bin")"
rich_compatibility_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_discover_version() { printf "1.1.0\n"; }
  _god_menu_select_rich() {
    selected="$(printf "%s\n" "$1" | LC_ALL=C awk -F "\t" "\$1 == \"Show the installed Kafka version\" { print NR; exit }")"
    printf "COMPATIBILITY HEADER:%s\nCOMPATIBILITY ROWS:\n%s\n" "$5" "$1"
    [ -n "$selected" ] || return 1
    "$4" "$selected" || return $?
    printf "COMPATIBILITY DETAIL:%s\n" "$_god_menu_provider_detail"
    _god_menu_choice=-1
    return 0
  }
  god kafka q "find version"
' _ "$project_dir")"
rich_all_versions_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_discover_version() { printf "1.1.0\n"; }
  _god_menu_select_rich() {
    printf "ALL-VERSION ROWS:\n%s\n" "$1"
    _god_menu_choice=-1
    return 0
  }
  god kafka q "find version" --all-versions
' _ "$project_dir")"
rich_offset_compatibility_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_discover_version() { printf "1.1.0\n"; }
  _god_menu_select_rich() {
    printf "OFFSET COMPATIBILITY ROWS:\n%s\n" "$1"
    _god_menu_choice=-1
    return 0
  }
  god kafka q "find offset"
' _ "$project_dir")"
rich_missing_tool_output="$(HOME="$rich_fixture" GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_stdout_is_terminal() { return 0; }
  _god_menu_rich_available() { return 0; }
  _god_discover_version() { printf "3.9.0\n"; }
  _god_menu_select_rich() {
    printf "MISSING TOOL ROWS:\n%s\n" "$1"
    _god_menu_choice=-1
    return 0
  }
  god kafka q "get offsets"
' _ "$project_dir")"
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
wrapped_command="$rich_bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config $rich_bin/../config/consumer.properties --list"
wrapped_preview="$(bash -c '. "$1/bash_god/menu.sh"; _god_menu_wrap "$2" 50 0' _ "$project_dir" "$wrapped_command")"
rich_render_output="$(LANG=en_US.UTF-8 GOD_COLOR=never bash -c '
  . "$1/bash_god/menu.sh"
  _god_menu_style_init
  _god_menu_rich_el="$(printf "\\033[K")"
  exec 3>&1
  rows=$'"'"'List consumer groups\t\t\t1\nShow Kafka features\tneeds v2.7+ (have v1.1.0)\t\t0'"'"'
  _god_menu_draw_rich_static "$rows" 2 2 90 "KAFKA SEARCH RESULTS" "Smart search: consumers"
  _god_menu_draw_rich_detail "$rows" 2 "/resolved/kafka-features.sh --help" 90 1
' _ "$project_dir")"
rich_render_first_line="$(printf '%s\n' "$rich_render_output" | LC_ALL=C awk 'NR == 1 { print; exit }')"
rich_compatibility_adjacency_count="$(printf '%s\n' "$rich_render_output" | LC_ALL=C grep -Fc 'Show Kafka features [needs v2.7+ (have v1.1.0)]')"
rich_cursor_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  exec 3>&1
  tput() {
    case "$1" in
      sc) printf "SC" ;;
      rc) printf "RC" ;;
      el) printf "EL" ;;
      cuu1) printf "UP" ;;
      civis) printf "HIDE" ;;
      cnorm) printf "SHOW" ;;
    esac
  }
  stty() {
    [ "$1" = -g ] && { printf "saved-tty-state"; return 0; }
    return 0
  }
  _god_menu_rich_cursor_start
  _god_menu_rich_cursor_finish
' _ "$project_dir")"
rich_interrupt_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  _god_menu_open_tty() { exec 3<>/dev/null; _god_menu_tty_fd=3; }
  _god_menu_close_tty() { exec 3<&-; exec 3>&-; _god_menu_tty_fd=""; }
  _god_menu_width() { printf "90\n"; }
  _god_menu_rich_cursor_start() { _god_menu_rich_anchor=0; }
  _god_menu_rich_cursor_finish() { :; }
  _god_menu_draw_rich_static() { :; }
  _god_menu_rich_render_current() { :; }
  _god_menu_rich_read_key() {
    kill -INT "$$"
    printf "INTERRUPT DID NOT BREAK KEY READ\n"
    _god_menu_rich_key=unknown
  }
  _god_menu_select_rich $'"'"'Only row\t\t\t1'"'"' "only command" 1
  interrupt_status=$?
  printf "INTERRUPT STATUS:%s\n" "$interrupt_status"
' _ "$project_dir" 2>&1)"
rich_key_input="$rich_fixture/escape-input"
printf '\033' > "$rich_key_input"
rich_key_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  _god_menu_rich_read_sequence() { printf "1b5b42"; }
  _god_menu_rich_read_key
  printf "KEY:%s\\n" "$_god_menu_rich_key"
' _ "$project_dir")"
rich_unknown_key_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  _god_menu_rich_read_sequence() { printf "1b3f"; }
  _god_menu_rich_read_key
  printf "KEY:%s\\n" "$_god_menu_rich_key"
' _ "$project_dir")"
rich_reader_dependency_output="$(LC_ALL=C grep -En 'Time::HiRes|Fcntl=' "$project_dir/bash_god/menu.sh" || true)"
# A terminal can expose ESC before the rest of an arrow sequence on a busy
# remote host. Feed the full sequence to the one reader after the old 60ms
# window; it must still report down rather than leak literal "[B" to the
# caller prompt.
rich_delayed_tail_fifo="$rich_fixture/delayed-escape-tail"
mkfifo "$rich_delayed_tail_fifo" || exit 1
(
  exec 4> "$rich_delayed_tail_fifo"
  printf '\033' >&4
  sleep 0.12
  printf '[B' >&4
) &
rich_delayed_tail_writer=$!
rich_delayed_tail_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  exec 3< "$2"
  _god_menu_rich_read_key
  printf "DELAYED KEY:%s\\n" "$_god_menu_rich_key"
' _ "$project_dir" "$rich_delayed_tail_fifo")"
wait "$rich_delayed_tail_writer" || :
# A regular file is not a raw terminal: Bash is allowed to buffer its queued
# bytes before the Perl escape-tail reader sees them. Exercise the rapid
# navigation loop with deterministic normalized keys instead; the key parser
# itself is covered immediately above.
rich_rapid_arrow_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  _god_menu_open_tty() { exec 3<>/dev/null; _god_menu_tty_fd=3; }
  _god_menu_close_tty() { exec 3<&-; exec 3>&-; _god_menu_tty_fd=""; }
  _god_menu_width() { printf "90\\n"; }
  _god_menu_rich_cursor_start() { _god_menu_rich_anchor=0; }
  _god_menu_rich_install_traps() { _god_menu_rich_interrupted=0; }
  _god_menu_rich_cleanup() { :; }
  _god_menu_draw_rich_static() { :; }
  _god_menu_rich_render_current() { :; }
  _god_menu_rich_redraw_selection() { :; }
  _god_menu_rich_read_key() {
    key_reads=$(( ${key_reads:-0} + 1 ))
    case "$key_reads" in
      1|2) _god_menu_rich_key=down ;;
      *) _god_menu_rich_key=enter ;;
    esac
  }
  rows=$'"'"'First\t\t\t1\nSecond\t\t\t1'"'"'
  details=$'"'"'first command\nsecond command'"'"'
  _god_menu_select_rich "$rows" "$details" 1 "" "KAFKA SEARCH RESULTS" "Smart search: consumers"
  printf "RAPID:%s|%s\\n" "$_god_menu_choice" "$_god_menu_edited_command"
' _ "$project_dir")"
rich_blocked_enter_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  _god_menu_open_tty() { exec 3<>/dev/null; _god_menu_tty_fd=3; }
  _god_menu_close_tty() { exec 3<&-; exec 3>&-; _god_menu_tty_fd=""; }
  _god_menu_width() { printf "90\n"; }
  _god_menu_rich_cursor_start() { _god_menu_rich_anchor=0; }
  _god_menu_rich_install_traps() { _god_menu_rich_interrupted=0; }
  _god_menu_rich_cleanup() { :; }
  _god_menu_draw_rich_static() { :; }
  _god_menu_rich_render_current() { :; }
  _god_menu_rich_read_key() {
    key_reads=$((${key_reads:-0} + 1))
    [ "$key_reads" -eq 1 ] && _god_menu_rich_key=enter || _god_menu_rich_key=escape
  }
  _god_menu_select_rich $'"'"'Unavailable\tneeds v2.7+ (have v1.1.0)\t\t0'"'"' "incompatible command" 1
  printf "BLOCKED ENTER:%s\n" "$_god_menu_choice"
' _ "$project_dir")"
rich_editor_input="$rich_fixture/editor-input"
printf 'e' > "$rich_editor_input"
rich_editor_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  input_file=$2
  _god_menu_open_tty() { exec 3<> "$input_file"; _god_menu_tty_fd=3; }
  _god_menu_close_tty() { exec 3<&-; exec 3>&-; _god_menu_tty_fd=""; }
  _god_menu_width() { printf "90\\n"; }
  _god_menu_rich_cursor_start() { _god_menu_rich_anchor=0; }
  _god_menu_rich_install_traps() { _god_menu_rich_interrupted=0; }
  _god_menu_rich_cleanup() { :; }
  _god_menu_draw_rich_static() { :; }
  _god_menu_rich_render_current() { :; }
  _god_menu_rich_redraw_selection() { :; }
  _god_menu_readline_edit() {
    printf "READLINE|%s\\n" "$1"
    _god_menu_edited_command="$1 --extra"
    return 0
  }
  demo_provider() { _god_menu_provider_detail="/resolved/kafka-consumer-groups.sh --list"; }
  _god_menu_select_rich $'"'"'List consumer groups\t\t\t1'"'"' "" 1 demo_provider "KAFKA SEARCH RESULTS" "Smart search: consumers"
  printf "INLINE EDIT|%s|%s\\n" "$_god_menu_choice" "$_god_menu_edited_command"
' _ "$project_dir" "$rich_editor_input")"
rich_editor_cancel_input="$rich_fixture/editor-cancel-input"
printf 'e' > "$rich_editor_cancel_input"
rich_editor_cancel_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  input_file=$2
  _god_menu_open_tty() { exec 3<> "$input_file"; _god_menu_tty_fd=3; }
  _god_menu_close_tty() { exec 3<&-; exec 3>&-; _god_menu_tty_fd=""; }
  _god_menu_width() { printf "90\\n"; }
  _god_menu_rich_cursor_start() { _god_menu_rich_anchor=0; }
  _god_menu_rich_install_traps() { _god_menu_rich_interrupted=0; }
  _god_menu_rich_cleanup() { :; }
  _god_menu_draw_rich_static() { :; }
  _god_menu_rich_render_current() { :; }
  _god_menu_rich_redraw_selection() { :; }
  _god_menu_readline_edit() { return 130; }
  demo_provider() { _god_menu_provider_detail="/resolved/kafka-consumer-groups.sh --list"; }
  _god_menu_select_rich $'"'"'List consumer groups\t\t\t1'"'"' "" 1 demo_provider "KAFKA SEARCH RESULTS" "Smart search: consumers"
  status=$?
  printf "EDIT CANCEL|%s|%s|%s\\n" "$status" "$_god_menu_choice" "$_god_menu_edited_command"
' _ "$project_dir" "$rich_editor_cancel_input")"
rich_result_read_bin="$rich_fixture/result-read-bin"
rich_result_read_fd="$rich_fixture/result-read-fd"
mkdir -p "$rich_result_read_bin"
printf '#!/usr/bin/env bash\nprintf "%%s --edited" "$BASH_GOD_EDIT_INITIAL" > "$BASH_GOD_EDIT_RESULT"\n' > "$rich_result_read_bin/zsh"
chmod 0755 "$rich_result_read_bin/zsh"
: > "$rich_result_read_fd"
rich_result_read_output="$(PATH="$rich_result_read_bin:$PATH" bash -c '
  . "$1/bash_god/menu.sh"
  exec 3<> "$2"
  _god_menu_readline_edit "seed command"
  printf "RESULT READ|%s\\n" "$_god_menu_edited_command"
' _ "$project_dir" "$rich_result_read_fd")"
theme_brand="$(printf '\033[1;35m')"
theme_accent="$(printf '\033[1;36m')"
theme_command="$(printf '\033[32m')"
rich_theme_output="$(env -u NO_COLOR GOD_COLOR=always LANG=en_US.UTF-8 bash -c '
  . "$1/bash_god/menu.sh"
  _god_menu_style_init
  _god_menu_rich_el="$(printf "\\033[K")"
  exec 3>&1
  rows=$'"'"'List consumer groups\t\t\t1'"'"'
  _god_menu_draw_rich_static "$rows" 1 1 90 "KAFKA SEARCH RESULTS" "Smart search: consumers"
  _god_menu_draw_rich_detail "$rows" 1 "echo list-groups" 90 1 view 0
' _ "$project_dir")"
rich_transition_input="$rich_fixture/transition-input"
printf 'j\n' > "$rich_transition_input"
rich_transition_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  input_file=$2
  _god_menu_open_tty() { exec 3<> "$input_file"; _god_menu_tty_fd=3; }
  _god_menu_close_tty() { exec 3<&-; exec 3>&-; _god_menu_tty_fd=""; }
  _god_menu_width() { printf "90\\n"; }
  _god_menu_rich_cursor_start() { _god_menu_rich_anchor=0; }
  _god_menu_rich_install_traps() { _god_menu_rich_interrupted=0; }
  _god_menu_rich_cleanup() { :; }
  _god_menu_draw_rich_static() { :; }
  _god_menu_rich_render_current() { trace="${trace:+$trace|}render:${_god_menu_rich_detail}"; }
  _god_menu_rich_redraw_selection() { trace="${trace:+$trace|}rows:$1:$2"; }
  demo_provider() { trace="${trace:+$trace|}provider:$1"; _god_menu_provider_detail="/resolved/command-$1"; }
  _god_menu_select_rich $'"'"'First\t\t\t1\nSecond\t\t\t1'"'"' "" 1 demo_provider "KAFKA SEARCH RESULTS" "Smart search: consumers"
  printf "TRANSITION:%s\\n" "$trace"
' _ "$project_dir" "$rich_transition_input")"
rich_cached_transition_input="$rich_fixture/cached-transition-input"
printf 'jkj\n' > "$rich_cached_transition_input"
rich_cached_transition_output="$(bash -c '
  . "$1/bash_god/menu.sh"
  input_file=$2
  _god_menu_open_tty() { exec 3<> "$input_file"; _god_menu_tty_fd=3; }
  _god_menu_close_tty() { exec 3<&-; exec 3>&-; _god_menu_tty_fd=""; }
  _god_menu_width() { printf "90\\n"; }
  _god_menu_rich_cursor_start() { _god_menu_rich_anchor=0; }
  _god_menu_rich_install_traps() { _god_menu_rich_interrupted=0; }
  _god_menu_rich_cleanup() { :; }
  _god_menu_draw_rich_static() { :; }
  _god_menu_rich_render_current() { trace="${trace:+$trace|}render:${_god_menu_rich_detail}"; }
  _god_menu_rich_redraw_selection() { trace="${trace:+$trace|}rows:$1:$2"; }
  demo_provider() {
    trace="${trace:+$trace|}provider:$1"
    case "$1" in
      1) cached_one=1 ;;
      2) cached_two=1 ;;
    esac
    _god_menu_provider_detail="/resolved/command-$1"
  }
  demo_cached() {
    case "$1" in
      1) [ "${cached_one:-}" = 1 ] ;;
      2) [ "${cached_two:-}" = 1 ] ;;
    esac
  }
  _god_menu_select_rich $'"'"'First\t\t\t1\nSecond\t\t\t1'"'"' "" 1 demo_provider "KAFKA SEARCH RESULTS" "Smart search: consumers" demo_cached
  printf "CACHED TRANSITION:%s\\n" "$trace"
' _ "$project_dir" "$rich_cached_transition_input")"
rm -rf "$rich_fixture"

if contains "$rich_fallback_output" 'MATCHING OPERATIONS' && contains "$rich_fallback_output" "god kafka groups $group_list_number" && \
   contains "$rich_picker_output" 'RICH PICKER ROWS' && contains "$rich_picker_output" 'List consumer groups' && \
   contains "$rich_picker_output" "$rich_bin/kafka-consumer-groups.sh" && not_contains "$rich_picker_output" 'MATCHING OPERATIONS' && \
   contains "$rich_picker_output" 'SECOND RICH PICKER DETAILS' && not_contains "$rich_picker_output" 'DETAILS DID NOT CHANGE' && \
   not_contains "$rich_picker_output" 'Pick a row to run it' && contains "$rich_enter_output" 'FAST RESOLVED EXECUTION' && \
   not_contains "$rich_enter_output" 'UNEXPECTED SLOW EXECUTION' && contains "$wrapped_preview" 'kafka-consumer-groups.sh' && \
   contains "$rich_edit_output" 'EDITED COMMAND|printf edited-command||1' && \
   not_contains "$rich_edit_output" 'UNEXPECTED PREPARED EXECUTION' && contains "$reviewed_execute_output" 'REVIEWED RUN|safe-template|safe-value' && \
   contains "$rich_failure_output" 'VISIBLE CHILD ERROR' && contains "$rich_failure_output" 'RICH FAILURE STATUS:47' && \
   not_contains "$rich_failure_output" 'hidden as incompatible' && \
   not_contains "$reviewed_execute_output" 'UNEXPECTED CONFIRM' && \
   contains "$execution_stream_output" 'stdout-visible' && contains "$execution_stream_output" 'stderr-visible' && \
   contains "$rich_pending_output" 'PENDING EXECUTION|consume|2|1' && not_contains "$rich_pending_output" 'UNEXPECTED PREPARED EXECUTION' && \
   contains "$rich_unmapped_placeholder_output" 'PLACEHOLDER PROMPT|Value for namespace|<namespace>' && \
   contains "$rich_unmapped_placeholder_output" 'DISPLAY	kubectl get pods -n ontic-app' && \
   contains "$rich_unmapped_placeholder_output" 'TEMPLATE	kubectl get pods -n "${1}"' && \
   contains "$rich_unmapped_placeholder_output" 'VALUE	ontic-app' && \
   contains "$rich_unresolved_placeholder_guard_output" 'unresolved placeholder and was not run' && \
   contains "$rich_unresolved_placeholder_guard_output" 'UNRESOLVED STATUS:2' && \
   contains "$rich_render_first_line" '╭' && contains "$rich_render_output" '│ KAFKA SEARCH RESULTS' && contains "$rich_render_output" 'Smart search: consumers' && \
   not_contains "$rich_render_output" 'incompatible commands hidden' && \
   contains "$rich_render_output" 'needs v2.7+ (have v1.1.0)' && \
   contains "$rich_render_output" 'unavailable for detected version' && \
   contains "$rich_render_output" '$ /resolved/kafka-features.sh' && \
   not_contains "$rich_render_output" 'COMMAND' && not_contains "$rich_render_output" 'replace' && \
   contains "$rich_cursor_output" 'HIDESHOW' && contains "$rich_interrupt_output" 'INTERRUPT STATUS:130' && \
   not_contains "$rich_interrupt_output" 'INTERRUPT DID NOT BREAK KEY READ' && contains "$rich_key_output" 'KEY:down' && \
   contains "$rich_unknown_key_output" 'KEY:unknown' && [ -z "$rich_reader_dependency_output" ] && \
   contains "$rich_delayed_tail_output" 'DELAYED KEY:down' && \
   contains "$rich_rapid_arrow_output" 'RAPID:1|second command' && \
   contains "$rich_blocked_enter_output" 'BLOCKED ENTER:-1' && \
   contains "$rich_editor_output" 'READLINE|/resolved/kafka-consumer-groups.sh --list' && \
   contains "$rich_editor_output" 'INLINE EDIT|0|/resolved/kafka-consumer-groups.sh --list --extra' && \
   contains "$rich_editor_cancel_output" 'EDIT CANCEL|130|-1|' && \
   contains "$rich_result_read_output" 'RESULT READ|seed command --edited' && \
   contains "$rich_theme_output" "$theme_brand" && contains "$rich_theme_output" "$theme_accent" && \
   contains "$rich_theme_output" "$theme_command" && \
   contains "$rich_transition_output" 'rows:1:2|provider:2|render:/resolved/command-2' && \
   not_contains "$rich_transition_output" 'Resolving…' && \
   contains "$rich_cached_transition_output" 'rows:2:1|provider:1|render:/resolved/command-1' && \
   not_contains "$rich_cached_transition_output" 'rows:2:1|render:Resolving…' && \
   contains "$rich_cached_transition_output" 'rows:2:1|provider:1|render:/resolved/command-1|rows:1:2|provider:2|render:/resolved/command-2' && \
   contains "$wrapped_preview" 'consumer.properties' && \
   contains "$rich_version_resolution_output" "DISPLAY${tab:-$(printf '\t')}basename $rich_bin/../libs/kafka_*.jar .jar | cut -d- -f2-" && \
   not_contains "$rich_version_resolution_output" '2>/dev/null' && \
   contains "$rich_tools_resolution_output" "DISPLAY${tab:-$(printf '\t')}find $rich_bin/" && \
   contains "$rich_compatibility_output" 'COMPATIBILITY HEADER:KAFKA SEARCH RESULTS' && \
   not_contains "$rich_compatibility_output" 'COMPATIBILITY NOTICE:' && \
   not_contains "$rich_compatibility_output" 'incompatible commands hidden' && \
   contains "$rich_compatibility_output" "COMPATIBILITY DETAIL:basename $rich_bin/../libs/kafka_*.jar .jar | cut -d- -f2-" && \
   contains "$rich_compatibility_output" $'Show kafka-broker-api-versions native help\tneeds v2.2+ (have v1.1.0)\t\t0' && \
   contains "$rich_compatibility_output" $'Show kafka-features native help\tneeds v2.7+ (have v1.1.0)\t\t0' && \
   contains "$rich_compatibility_output" $'Show the installed Kafka version\t\t\t1' && \
   contains "$rich_all_versions_output" 'ALL-VERSION ROWS:' && \
   contains "$rich_all_versions_output" $'Show kafka-features native help\tneeds v2.7+ (have v1.1.0)\t\t0' && \
   contains "$rich_offset_compatibility_output" $'Show kafka-get-offsets native help\tneeds v3.0+ (have v1.1.0)\t\t0' && \
   contains "$rich_missing_tool_output" $'Show kafka-get-offsets native help\tkafka-get-offsets.sh is not installed\t\t0' && \
   [ "$(printf '%s\n' "$wrapped_preview" | LC_ALL=C awk 'END { print NR + 0 }')" -gt 1 ]; then
  pass 'resolved search uses one inline editable picker and Enter reuses its prepared command'
else
  fail 'resolved search uses one inline editable picker and Enter reuses its prepared command'
fi

if [ "$rich_compatibility_adjacency_count" -eq 2 ]; then
  pass 'rich picker keeps compatibility beside list and detail titles'
else
  fail 'rich picker keeps compatibility beside list and detail titles'
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
bash -c '. "$1/bash_god/core.sh"; _god_catalog_files() { return 7; }; GOD_COLOR=never god help >/dev/null' _ "$project_dir" 2>/dev/null || enumeration_status=$?
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

if [ "$kafka_group_count" -ge 15 ] && [ "$kafka_command_count" -ge 79 ]; then
  pass 'expanded Kafka catalog coverage'
else
  fail 'expanded Kafka catalog coverage'
fi

mongo_service_output="$(GOD_COLOR=never "$god_cli" mongo service)"
mongo_backup_output="$(GOD_COLOR=never "$god_cli" mongo backup)"
mongo_replica_output="$(GOD_COLOR=never "$god_cli" mongo replica)"
if contains "$mongo_service_output" '$ systemctl status mongod' && contains "$mongo_backup_output" '$ mongodump ' && contains "$mongo_backup_output" '$ mongorestore ' && contains "$mongo_backup_output" '[WRITE]' && contains "$mongo_replica_output" "\$ mongosh --quiet --eval 'rs.status()'"; then
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

if [ -f "$aws_catalog" ] && [ -f "$kafka_catalog" ] && [ -f "$general_catalog" ] && [ -f "$elasticsearch_catalog" ] && [ -f "$k8s_catalog" ] && [ -f "$mongo_catalog" ] && [ -f "$network_catalog" ] && [ ! -e "$project_dir/bash_god/catalog/kafka.god" ] && [ ! -e "$project_dir/bash_god/catalog/general.god" ]; then
  pass 'each service owns catalog SERVICE/service.god'
else
  fail 'each service owns catalog SERVICE/service.god'
fi

if [ -f "$catalog_module" ] && [ -f "$render_module" ] && [ -f "$art_module" ] && [ -f "$search_module" ] && [ -f "$tree_module" ] && ! LC_ALL=C awk '/^_god_(validate_catalog|print_root_help|print_home_art|search_catalog|render_tree_groups)\(\)/ { found = 1 } END { exit(found ? 0 : 1) }' "$project_dir/bash_god/core.sh"; then
  pass 'catalog, artwork, rendering, search, and tree concerns are separate sourced modules'
else
  fail 'catalog, artwork, rendering, search, and tree concerns are separate sourced modules'
fi

empty_catalog_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-empty.XXXXXX")" || exit 1
bash -O failglob -c '. "$1/bash_god/core.sh"; _BASH_GOD_CATALOG_DIR="$2"; GOD_COLOR=never god help >/dev/null' _ "$project_dir" "$empty_catalog_dir"
bash_empty_status=$?
zsh -c 'setopt nomatch; . "$1/bash_god/core.sh"; _BASH_GOD_CATALOG_DIR="$2"; GOD_COLOR=never god help >/dev/null' _ "$project_dir" "$empty_catalog_dir"
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

if [ "$failures" -eq 0 ]; then
  printf '\n%d checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d checks failed.\n' "$failures" "$checks" >&2
exit 1
