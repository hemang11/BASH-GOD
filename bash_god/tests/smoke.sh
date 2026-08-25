#!/usr/bin/env bash

# Knowledge-rendering regression checks. No catalog command is executed.

test_file="${BASH_SOURCE[0]}"
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
project_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
god_cli="$project_dir/god"
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

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

not_contains() {
  ! contains "$1" "$2"
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
offset_command_count="$(catalog_group_command_count "$kafka_catalog" offset)"
native_command_count="$(catalog_group_command_count "$kafka_catalog" native)"
access_command_count="$(catalog_group_command_count "$kafka_catalog" access)"
consume_exact_number="$(catalog_entry_number "$kafka_catalog" consume 'Read from an exact partition offset')"
consume_exact_label="$(printf '%02d' "$consume_exact_number")"
offset_lag_number="$(catalog_entry_number "$kafka_catalog" offset 'Show consumer-group offsets and lag')"
group_members_number="$(catalog_entry_number "$kafka_catalog" groups 'Show active members of a consumer group')"
health_unavailable_number="$(catalog_entry_number "$kafka_catalog" health 'Find partitions without an available leader')"
health_unavailable_label="$(printf '%02d' "$health_unavailable_number")"

output="$(GOD_COLOR=never "$god_cli")"
home_slogan='Your DevOps command memory. Native commands, zero execution.'
logo_first='██████╗  █████╗ ███████╗██╗  ██╗    ██████╗  ██████╗ ██████╗'
logo_last='╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝'
services_table_start="$(printf 'SERVICES\n  SERVICE')"
quick_start_first_row="$(printf 'QUICK START\n  god kafka')"
view_keys_first_row="$(printf 'VIEW KEYS\n  <number>')"
if contains "$output" "$services_table_start" && contains "$output" 'god aws' && contains "$output" "$quick_start_first_row" && contains "$output" "$view_keys_first_row" && contains "$output" 'god kafka health <number>' && contains "$output" "god q --regex 'offset|lag'" && contains "$output" '--quiet' && contains "$output" 'Case-insensitive and display-only' && contains "$output" 'god --keys' && not_contains "$output" "$logo_first" && not_contains "$output" "$home_slogan"; then
  pass 'non-interactive root dashboard stays decoration-free'
else
  fail 'non-interactive root dashboard stays decoration-free'
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
if contains "$interactive_output" "$logo_first" && contains "$interactive_output" "$logo_last" && contains "$interactive_output" "$home_slogan" && not_contains "$interactive_help_output" "$logo_first" && not_contains "$interactive_long_help_output" "$logo_first" && [ "$interactive_quiet_output" = "$help_output" ]; then
  pass 'pre-rendered logo is limited to bare interactive god'
else
  fail 'pre-rendered logo is limited to bare interactive god'
fi

version_output="$(GOD_COLOR=never "$god_cli" --version)"
short_version_output="$(GOD_COLOR=never "$god_cli" -v)"
license_text="$(command cat "$license_file")"
if [ "$version_output" = "$short_version_output" ] && contains "$version_output" 'BASH_GOD 0.0.1.1' && contains "$version_output" 'License: MIT' && not_contains "$version_output" 'GNU bash' && contains "$license_text" 'MIT License'; then
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
if contains "$entry_output" "KAFKA / CONSUME / $consume_exact_label" && contains "$entry_output" 'PARAMETER' && contains "$entry_output" 'OPTIONAL' && contains "$entry_output" '--partition'; then
  pass 'numbered entry explains command parameters'
else
  fail 'numbered entry explains command parameters'
fi

details_output="$(GOD_COLOR=never "$god_cli" kafka consume --details)"
if contains "$details_output" 'KAFKA / CONSUME / DETAILS' && contains "$details_output" 'FULL DETAILS' && contains "$details_output" 'Starts a console consumer at one explicit topic partition and offset.' && contains "$details_output" 'PARAMETER' && contains "$details_output" 'OPTIONAL' && contains "$details_output" 'Print record keys, headers, and timestamps'; then
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
ivory_row="$(printf '\033[1;38;5;255m')"
gold_row="$(printf '\033[1;38;5;220m')"
if contains "$color_logo_output" "$ivory_row$logo_first" && contains "$color_logo_output" "$gold_row$logo_last" && contains "$plain_logo_output" "$logo_first" && not_contains "$plain_logo_output" "$escape_character"; then
  pass 'home logo uses one ivory-to-gold gradient with a plain NO_COLOR form'
else
  fail 'home logo uses one ivory-to-gold gradient with a plain NO_COLOR form'
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
if contains "$mongo_service_output" '$ systemctl status mongod' && contains "$mongo_backup_output" '$ mongodump ' && contains "$mongo_backup_output" '$ mongorestore ' && contains "$mongo_backup_output" '[WRITE]' && contains "$mongo_replica_output" '$ rs.status()'; then
  pass 'MongoDB catalog covers service, replica-set, dump, and restore memory'
else
  fail 'MongoDB catalog covers service, replica-set, dump, and restore memory'
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

if [ "$failures" -eq 0 ]; then
  printf '\n%d checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d checks failed.\n' "$failures" "$checks" >&2
exit 1
