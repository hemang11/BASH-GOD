#!/usr/bin/env bash

# R13 migration regression coverage. The real catalogs are parsed as inert
# data, while every availability fact comes from this temporary fixture. No
# catalog @run line, cloud client, endpoint, service manager, or network call
# may reach the host.

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir=$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P) || exit 1
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd -P) || exit 1

checks=0
failures=0

pass() {
  checks=$((checks + 1))
  printf 'ok %02d - %s\n' "$checks" "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'not ok %02d - %s\n' "$checks" "$1" >&2
}

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

fixture=$(mktemp -d "${TMPDIR:-/tmp}/bash-god-r13.XXXXXX") || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

fake_bin=$fixture/fake-bin
fake_aws=$fixture/aws
fake_elasticsearch=$fixture/elasticsearch
fake_k8s=$fixture/k8s
fake_mongo=$fixture/mongo
fake_kafka=$fixture/kafka
mkdir -p "$fake_bin" "$fake_aws" "$fake_elasticsearch" "$fake_k8s" "$fake_mongo" "$fake_kafka" || exit 1

make_tool() {
  local path

  path=$1
  printf '%s\n' '#!/usr/bin/env bash' 'exit 97' > "$path"
  chmod 0700 "$path"
}

entry_number() {
  local catalog group title

  catalog=$1
  group=$2
  title=$3
  LC_ALL=C awk -v wanted_group="$group" -v wanted_title="$title" '
    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      selected = tolower(current) == tolower(wanted_group)
      position = 0
      next
    }
    selected && /^@command[[:space:]]+/ {
      position++
      current = $0
      sub(/^@command[[:space:]]+/, "", current)
      if (current == wanted_title) {
        print position
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "$catalog"
}

requirements_for() {
  local catalog group entry

  catalog=$1
  group=$2
  entry=$3
  _god_catalog_command_export "$catalog" "$group" "$entry" | LC_ALL=C awk -F '\t' '$1 == "REQUIRE" { print $2 " | " $3 " | " $4 }'
}

mode_for() {
  local catalog group entry

  catalog=$1
  group=$2
  entry=$3
  _god_catalog_command_export "$catalog" "$group" "$entry" | LC_ALL=C awk -F '\t' '$1 == "MODE" { print $2; exit }'
}

display_for() {
  local service catalog group entry execution_path query

  service=$1
  catalog=$2
  group=$3
  entry=$4
  execution_path=$5
  query=${6:-}
  _god_resolve_command "$service" "$catalog" "$group" "$entry" "$execution_path" "$query" | LC_ALL=C awk -F '\t' '$1 == "DISPLAY" { print $2; exit }'
}

eligibility_of() {
  local service catalog group entry facts output

  service=$1
  catalog=$2
  group=$3
  entry=$4
  facts=${5:-}
  output=$(_god_eligibility_assess "$service" "$catalog" "$group" "$entry" "$facts" 2>/dev/null) || return 1
  printf '%s\n' "$output" | LC_ALL=C awk -F '\t' '$1 == "ELIGIBILITY" { print $2; exit }'
}

command_count() {
  LC_ALL=C awk '/^@command[[:space:]]/ { count++ } END { print count + 0 }' "$1"
}

requires_count() {
  LC_ALL=C awk '/^@requires$/ { count++ } END { print count + 0 }' "$1"
}

aws_catalog=$project_dir/catalog/aws/service.god
elasticsearch_catalog=$project_dir/catalog/elasticsearch/service.god
k8s_catalog=$project_dir/catalog/k8s/service.god
mongo_catalog=$project_dir/catalog/mongo/service.god
general_catalog=$project_dir/catalog/general/service.god
network_catalog=$project_dir/catalog/network/service.god
kafka_catalog=$project_dir/catalog/kafka/service.god

# shellcheck source=../BASH_GOD.sh
. "$project_dir/BASH_GOD.sh" || exit 1

# Every eligibility fact is fixture-controlled. In particular, the test does
# not use host PATH, uname, discovery state, an AWS profile, or an endpoint.
_god_eligibility_local_os() {
  printf '%s\n' linux
}
_god_eligibility_local_tool_path() {
  [ -x "$fake_bin/$1" ] && printf '%s\n' "$fake_bin/$1"
}
_god_discover_is_stale() {
  return 1
}
_god_discover_path() {
  case "$1" in
    aws) printf '%s\n' "$fake_aws" ;;
    elasticsearch) printf '%s\n' "$fake_elasticsearch" ;;
    k8s) printf '%s\n' "$fake_k8s" ;;
    mongo) [ "${mongo_discovery_available:-1}" = 1 ] && printf '%s\n' "$fake_mongo" ;;
    kafka) printf '%s\n' "$fake_kafka" ;;
    *) return 1 ;;
  esac
}
_god_discover_tool() {
  case "$1" in
    aws) printf '%s\n' aws ;;
    elasticsearch) printf '%s\n' curl ;;
    k8s) printf '%s\n' kubectl ;;
    mongo) printf '%s\n' mongosh ;;
    kafka) printf '%s\n' kafka-topics.sh ;;
    *) return 1 ;;
  esac
}
_god_discover_version() {
  case "$1" in
    aws) printf '%s\n' 2.36.34 ;;
    elasticsearch) printf '%s\n' 7.17.0 ;;
    k8s) printf '%s\n' 1.37.0 ;;
    mongo) [ "${mongo_discovery_available:-1}" = 1 ] && printf '%s\n' 4.2.22 ;;
    kafka) printf '%s\n' 3.9.2 ;;
    *) return 1 ;;
  esac
}
_god_discover_target() {
  case "$1" in
    mongo) printf '%s\n' mongo.fixture:27017 ;;
    *) return 1 ;;
  esac
}

make_tool "$fake_aws/aws"
make_tool "$fake_elasticsearch/curl"
make_tool "$fake_k8s/kubectl"
make_tool "$fake_mongo/mongosh"
make_tool "$fake_mongo/mongo"
make_tool "$fake_kafka/kafka-topics.sh"
make_tool "$fake_bin/curl"
make_tool "$fake_bin/env"
make_tool "$fake_bin/mongodump"
make_tool "$fake_bin/mongorestore"
make_tool "$fake_bin/sw_vers"
make_tool "$fake_bin/ps"
make_tool "$fake_bin/route"
make_tool "$fake_bin/ss"
make_tool "$fake_bin/grep"
make_tool "$fake_bin/openssl"
make_tool "$fake_bin/ssh"

# This starts red against Schema-0 catalogs: a whole migrated catalog must
# opt into Schema 1 and give every command one non-empty requirements block.
if [ "$(command_count "$aws_catalog")" -eq "$(requires_count "$aws_catalog")" ] && \
   [ "$(command_count "$elasticsearch_catalog")" -eq "$(requires_count "$elasticsearch_catalog")" ] && \
   [ "$(command_count "$k8s_catalog")" -eq "$(requires_count "$k8s_catalog")" ] && \
   [ "$(command_count "$mongo_catalog")" -eq "$(requires_count "$mongo_catalog")" ] && \
   [ "$(command_count "$general_catalog")" -eq "$(requires_count "$general_catalog")" ] && \
   [ "$(command_count "$network_catalog")" -eq "$(requires_count "$network_catalog")" ] && \
   [ "$(command_count "$kafka_catalog")" -eq "$(requires_count "$kafka_catalog")" ] && \
   LC_ALL=C grep -Fqx '@environment 1' "$aws_catalog" && \
   LC_ALL=C grep -Fqx '@environment 1' "$elasticsearch_catalog" && \
   LC_ALL=C grep -Fqx '@environment 1' "$k8s_catalog" && \
   LC_ALL=C grep -Fqx '@environment 1' "$mongo_catalog" && \
   LC_ALL=C grep -Fqx '@environment 1' "$general_catalog" && \
   LC_ALL=C grep -Fqx '@environment 1' "$network_catalog" && \
   LC_ALL=C grep -Fqx '@environment 1' "$kafka_catalog"; then
  pass 'AWS, Elasticsearch, Kubernetes, MongoDB, General, Network, and Kafka opt into Schema 1 only with complete command requirements'
else
  fail 'AWS, Elasticsearch, Kubernetes, MongoDB, General, Network, and Kafka opt into Schema 1 only with complete command requirements'
fi

aws_identity=$(entry_number "$aws_catalog" identity 'Show the current AWS identity') || exit 1
aws_session=$(entry_number "$aws_catalog" ssm 'Open a Session Manager shell on an instance') || exit 1
aws_specific_user=$(entry_number "$aws_catalog" ssm 'Open a Session Manager shell as a specific host user') || exit 1
aws_imdsv2=$(entry_number "$aws_catalog" imds 'Show the metadata role name through an IMDSv2 token') || exit 1
aws_env_identity=$(entry_number "$aws_catalog" imds 'Verify the instance role without exported keys') || exit 1
es_rest=$(entry_number "$elasticsearch_catalog" indices 'List indices') || exit 1
es_systemd=$(entry_number "$elasticsearch_catalog" service 'Check the Elasticsearch systemd service') || exit 1
es_pipeline=$(entry_number "$elasticsearch_catalog" shards 'Find unassigned shards') || exit 1
k8s_pods=$(entry_number "$k8s_catalog" pods 'List pods in a namespace') || exit 1
k8s_exec=$(entry_number "$k8s_catalog" exec 'Open a shell inside a pod') || exit 1
k8s_diff=$(entry_number "$k8s_catalog" manifests 'Preview manifest differences') || exit 1
mongo_mongosh=$(entry_number "$mongo_catalog" connect 'Connect with mongosh') || exit 1
mongo_legacy=$(entry_number "$mongo_catalog" connect 'Connect with the legacy mongo shell') || exit 1
mongo_listener=$(entry_number "$mongo_catalog" service 'Check whether the MongoDB listener port is open') || exit 1
mongo_dump=$(entry_number "$mongo_catalog" backup 'Dump one database') || exit 1
general_linux_memory=$(entry_number "$general_catalog" resources 'Show Linux memory totals') || exit 1
general_macos_version=$(entry_number "$general_catalog" host 'Show the macOS version') || exit 1
general_cpu=$(entry_number "$general_catalog" processes 'Show the busiest Linux processes by CPU') || exit 1
general_shell_help=$(entry_number "$general_catalog" native 'Show Bash builtin help') || exit 1
network_linux_interface=$(entry_number "$network_catalog" interfaces 'Show Linux network interfaces and addresses') || exit 1
network_macos_route=$(entry_number "$network_catalog" interfaces 'Show the macOS default route') || exit 1
network_port=$(entry_number "$network_catalog" ports 'Check which Linux process is listening on one TCP port') || exit 1
network_tls=$(entry_number "$network_catalog" http 'Inspect a server TLS handshake and certificate chain') || exit 1
network_ssh=$(entry_number "$network_catalog" ssh 'Connect to a host through SSH') || exit 1
kafka_topics=$(entry_number "$kafka_catalog" topics 'List topics through a broker') || exit 1
kafka_offsets=$(entry_number "$kafka_catalog" offset 'Show latest offsets for a topic') || exit 1
kafka_listener=$(entry_number "$kafka_catalog" broker 'Find the local Kafka broker listener') || exit 1
kafka_producer=$(entry_number "$kafka_catalog" produce 'Publish one message') || exit 1
kafka_config=$(entry_number "$kafka_catalog" broker 'Show broker configuration') || exit 1

aws_identity_requirements=$(requirements_for "$aws_catalog" identity "$aws_identity")
aws_session_requirements=$(requirements_for "$aws_catalog" ssm "$aws_session")
aws_specific_user_requirements=$(requirements_for "$aws_catalog" ssm "$aws_specific_user")
aws_imdsv2_requirements=$(requirements_for "$aws_catalog" imds "$aws_imdsv2")
aws_env_identity_requirements=$(requirements_for "$aws_catalog" imds "$aws_env_identity")
es_rest_requirements=$(requirements_for "$elasticsearch_catalog" indices "$es_rest")
es_systemd_requirements=$(requirements_for "$elasticsearch_catalog" service "$es_systemd")
es_pipeline_requirements=$(requirements_for "$elasticsearch_catalog" shards "$es_pipeline")
k8s_pods_requirements=$(requirements_for "$k8s_catalog" pods "$k8s_pods")
k8s_exec_requirements=$(requirements_for "$k8s_catalog" exec "$k8s_exec")
k8s_diff_requirements=$(requirements_for "$k8s_catalog" manifests "$k8s_diff")
mongo_mongosh_requirements=$(requirements_for "$mongo_catalog" connect "$mongo_mongosh")
mongo_legacy_requirements=$(requirements_for "$mongo_catalog" connect "$mongo_legacy")
mongo_listener_requirements=$(requirements_for "$mongo_catalog" service "$mongo_listener")
mongo_dump_requirements=$(requirements_for "$mongo_catalog" backup "$mongo_dump")
general_linux_memory_requirements=$(requirements_for "$general_catalog" resources "$general_linux_memory")
general_macos_version_requirements=$(requirements_for "$general_catalog" host "$general_macos_version")
general_cpu_requirements=$(requirements_for "$general_catalog" processes "$general_cpu")
general_shell_help_requirements=$(requirements_for "$general_catalog" native "$general_shell_help")
network_linux_interface_requirements=$(requirements_for "$network_catalog" interfaces "$network_linux_interface")
network_macos_route_requirements=$(requirements_for "$network_catalog" interfaces "$network_macos_route")
network_port_requirements=$(requirements_for "$network_catalog" ports "$network_port")
network_tls_requirements=$(requirements_for "$network_catalog" http "$network_tls")
network_ssh_requirements=$(requirements_for "$network_catalog" ssh "$network_ssh")
kafka_topics_requirements=$(requirements_for "$kafka_catalog" topics "$kafka_topics")
kafka_offsets_requirements=$(requirements_for "$kafka_catalog" offset "$kafka_offsets")
kafka_listener_requirements=$(requirements_for "$kafka_catalog" broker "$kafka_listener")
kafka_producer_requirements=$(requirements_for "$kafka_catalog" produce "$kafka_producer")
kafka_config_requirements=$(requirements_for "$kafka_catalog" broker "$kafka_config")

if contains "$aws_identity_requirements" 'tool | service:aws | present' && \
   contains "$aws_session_requirements" 'tool | local:session-manager-plugin | present' && \
   contains "$aws_specific_user_requirements" 'context | execution | remote' && \
   contains "$aws_specific_user_requirements" 'tool | remote:sudo | present' && \
   contains "$aws_imdsv2_requirements" 'shell | local | posix' && \
   contains "$aws_imdsv2_requirements" 'tool | local:curl | present' && \
   contains "$aws_env_identity_requirements" 'tool | local:env | present'; then
  pass 'AWS requirements separate local clients, shell grammar, and unverified remote work'
else
  fail 'AWS requirements separate local clients, shell grammar, and unverified remote work'
fi

if contains "$es_rest_requirements" 'tool | service:curl | present' && \
   contains "$es_systemd_requirements" 'os | local | linux' && \
   contains "$es_systemd_requirements" 'tool | local:systemctl | present' && \
   contains "$es_pipeline_requirements" 'shell | local | posix' && \
   contains "$es_pipeline_requirements" 'tool | local:awk | present'; then
  pass 'Elasticsearch requirements separate REST client, Linux diagnostics, and shell pipeline helpers'
else
  fail 'Elasticsearch requirements separate REST client, Linux diagnostics, and shell pipeline helpers'
fi

if contains "$k8s_pods_requirements" 'tool | service:kubectl | present' && \
   contains "$k8s_exec_requirements" 'context | execution | remote' && \
   contains "$k8s_exec_requirements" 'tool | remote:sh | present' && \
   contains "$k8s_diff_requirements" 'tool | local:diff | present'; then
  pass 'Kubernetes requirements keep client facts local and a container shell explicitly unknown'
else
  fail 'Kubernetes requirements keep client facts local and a container shell explicitly unknown'
fi

if contains "$mongo_mongosh_requirements" 'tool | service:mongosh | present' && \
   contains "$mongo_legacy_requirements" 'tool | service:mongo | present' && \
   contains "$mongo_listener_requirements" 'os | local | linux' && \
   contains "$mongo_listener_requirements" 'shell | local | posix' && \
   contains "$mongo_listener_requirements" 'tool | local:ss | present' && \
   contains "$mongo_listener_requirements" 'tool | local:grep | present' && \
   contains "$mongo_dump_requirements" 'tool | local:mongodump | present' && \
   [ "$(mode_for "$mongo_catalog" backup "$mongo_dump")" = LOCAL ]; then
  pass 'MongoDB requirements distinguish modern shell, legacy shell, local host checks, and Database Tools'
else
  fail 'MongoDB requirements distinguish modern shell, legacy shell, local host checks, and Database Tools'
fi

if contains "$general_linux_memory_requirements" 'os | local | linux' && \
   contains "$general_linux_memory_requirements" 'tool | local:free | present' && \
   contains "$general_macos_version_requirements" 'os | local | darwin' && \
   contains "$general_macos_version_requirements" 'tool | local:sw_vers | present' && \
   contains "$general_cpu_requirements" 'shell | local | posix' && \
   contains "$general_cpu_requirements" 'tool | local:ps | gnu' && \
   contains "$general_shell_help_requirements" 'shell | local | bash'; then
  pass 'General requirements declare OS, implementation, pipeline, and Bash-builtin boundaries'
else
  fail 'General requirements declare OS, implementation, pipeline, and Bash-builtin boundaries'
fi

if contains "$network_linux_interface_requirements" 'os | local | linux' && \
   contains "$network_linux_interface_requirements" 'tool | local:ip | present' && \
   contains "$network_macos_route_requirements" 'os | local | darwin' && \
   contains "$network_macos_route_requirements" 'tool | local:route | present' && \
   contains "$network_port_requirements" 'shell | local | posix' && \
   contains "$network_port_requirements" 'tool | local:ss | present' && \
   contains "$network_port_requirements" 'tool | local:grep | present' && \
   contains "$network_tls_requirements" 'shell | local | posix' && \
   contains "$network_tls_requirements" 'tool | local:openssl | present' && \
   contains "$network_ssh_requirements" 'tool | local:ssh | present'; then
  pass 'Network requirements distinguish OS, shell syntax, local utility facts, and ordinary local SSH clients'
else
  fail 'Network requirements distinguish OS, shell syntax, local utility facts, and ordinary local SSH clients'
fi

if contains "$kafka_topics_requirements" 'tool | service:kafka-topics.sh | present' && \
   contains "$kafka_offsets_requirements" 'tool | service:kafka-get-offsets.sh | present' && \
   contains "$kafka_listener_requirements" 'os | local | linux' && \
   contains "$kafka_listener_requirements" 'tool | local:ss | present' && \
   contains "$kafka_producer_requirements" 'shell | local | posix' && \
   contains "$kafka_producer_requirements" 'tool | service:kafka-console-producer.sh | present' && \
   contains "$kafka_config_requirements" 'tool | local:cat | present' && \
   ! contains "$kafka_config_requirements" 'tool | service:'; then
  pass 'Kafka requirements distinguish exact sibling scripts, local diagnostics, shell pipelines, and local config files'
else
  fail 'Kafka requirements distinguish exact sibling scripts, local diagnostics, shell pipelines, and local config files'
fi

aws_identity_state=$(eligibility_of aws "$aws_catalog" identity "$aws_identity") || aws_identity_state=error
aws_imdsv2_state=$(eligibility_of aws "$aws_catalog" imds "$aws_imdsv2") || aws_imdsv2_state=error
aws_env_identity_state=$(eligibility_of aws "$aws_catalog" imds "$aws_env_identity") || aws_env_identity_state=error
if [ "$aws_identity_state" = eligible ] && [ "$aws_imdsv2_state" = eligible ] && [ "$aws_env_identity_state" = eligible ]; then
  pass 'fixture-local AWS requirements admit only rows whose named local facts exist'
else
  fail 'fixture-local AWS requirements admit only rows whose named local facts exist'
fi

aws_session_without_plugin=$(eligibility_of aws "$aws_catalog" ssm "$aws_session") || aws_session_without_plugin=error
make_tool "$fake_bin/session-manager-plugin"
aws_session_with_plugin=$(eligibility_of aws "$aws_catalog" ssm "$aws_session") || aws_session_with_plugin=error
aws_specific_user_state=$(eligibility_of aws "$aws_catalog" ssm "$aws_specific_user") || aws_specific_user_state=error
if [ "$aws_session_without_plugin" = ineligible ] && [ "$aws_session_with_plugin" = eligible ] && \
   [ "$aws_specific_user_state" = unknown ]; then
  pass 'Session Manager plugin is local while a managed-node sudo command remains unknown'
else
  fail 'Session Manager plugin is local while a managed-node sudo command remains unknown'
fi

es_rest_state=$(eligibility_of elasticsearch "$elasticsearch_catalog" indices "$es_rest") || es_rest_state=error
darwin_fact=$(printf 'FACT\tos\tlocal\tdarwin')
es_systemd_state=$(eligibility_of elasticsearch "$elasticsearch_catalog" service "$es_systemd" "$darwin_fact") || es_systemd_state=error
es_pipeline_without_awk=$(eligibility_of elasticsearch "$elasticsearch_catalog" shards "$es_pipeline") || es_pipeline_without_awk=error
make_tool "$fake_bin/awk"
es_pipeline_with_awk=$(eligibility_of elasticsearch "$elasticsearch_catalog" shards "$es_pipeline") || es_pipeline_with_awk=error
if [ "$es_rest_state" = eligible ] && [ "$es_systemd_state" = ineligible ] && \
   [ "$es_pipeline_without_awk" = ineligible ] && [ "$es_pipeline_with_awk" = eligible ]; then
  pass 'REST rows remain local-client eligible while Linux and pipeline requirements fail closed'
else
  fail 'REST rows remain local-client eligible while Linux and pipeline requirements fail closed'
fi

k8s_pods_state=$(eligibility_of k8s "$k8s_catalog" pods "$k8s_pods") || k8s_pods_state=error
k8s_exec_state=$(eligibility_of k8s "$k8s_catalog" exec "$k8s_exec") || k8s_exec_state=error
k8s_diff_without_helper=$(eligibility_of k8s "$k8s_catalog" manifests "$k8s_diff") || k8s_diff_without_helper=error
make_tool "$fake_bin/diff"
k8s_diff_with_helper=$(eligibility_of k8s "$k8s_catalog" manifests "$k8s_diff") || k8s_diff_with_helper=error
if [ "$k8s_pods_state" = eligible ] && [ "$k8s_exec_state" = unknown ] && \
   [ "$k8s_diff_without_helper" = ineligible ] && [ "$k8s_diff_with_helper" = eligible ]; then
  pass 'Kubernetes never treats a selected pod as remote-shell evidence and names diff explicitly'
else
  fail 'Kubernetes never treats a selected pod as remote-shell evidence and names diff explicitly'
fi

mongo_discovery_available=1
mongo_mongosh_state=$(eligibility_of mongo "$mongo_catalog" connect "$mongo_mongosh") || mongo_mongosh_state=error
mongo_legacy_state=$(eligibility_of mongo "$mongo_catalog" connect "$mongo_legacy") || mongo_legacy_state=error
legacy_display=$(display_for mongo "$mongo_catalog" connect "$mongo_legacy" "$fake_mongo")
mongo_discovery_available=0
mongo_dump_state=$(eligibility_of mongo "$mongo_catalog" backup "$mongo_dump") || mongo_dump_state=error
dump_display=$(display_for mongo "$mongo_catalog" backup "$mongo_dump" '')
if [ "$mongo_mongosh_state" = eligible ] && [ "$mongo_legacy_state" = eligible ] && \
   contains "$legacy_display" "$fake_mongo/mongo --host" && \
   ! contains "$legacy_display" "$fake_mongo/mongosh --host" && \
   [ "$mongo_dump_state" = eligible ] && \
   contains "$dump_display" 'mongodump --host mongo.fixture --port 27017'; then
  pass 'MongoDB uses the exact reviewed shell and lets independent Database Tools use the cached Target'
else
  fail 'MongoDB uses the exact reviewed shell and lets independent Database Tools use the cached Target'
fi

linux_memory_without_free=$(eligibility_of general "$general_catalog" resources "$general_linux_memory") || linux_memory_without_free=error
make_tool "$fake_bin/free"
linux_memory_with_free=$(eligibility_of general "$general_catalog" resources "$general_linux_memory") || linux_memory_with_free=error
darwin_fact=$(printf 'FACT\tos\tlocal\tdarwin')
macos_version_state=$(eligibility_of general "$general_catalog" host "$general_macos_version" "$darwin_fact") || macos_version_state=error
linux_memory_on_darwin=$(eligibility_of general "$general_catalog" resources "$general_linux_memory" "$darwin_fact") || linux_memory_on_darwin=error
if [ "$linux_memory_without_free" = ineligible ] && [ "$linux_memory_with_free" = eligible ] && \
   [ "$macos_version_state" = eligible ] && [ "$linux_memory_on_darwin" = ineligible ]; then
  pass 'General executable eligibility is fact-based and never presents known Linux rows on Darwin'
else
  fail 'General executable eligibility is fact-based and never presents known Linux rows on Darwin'
fi

network_linux_without_ip=$(eligibility_of network "$network_catalog" interfaces "$network_linux_interface") || network_linux_without_ip=error
make_tool "$fake_bin/ip"
network_linux_with_ip=$(eligibility_of network "$network_catalog" interfaces "$network_linux_interface") || network_linux_with_ip=error
network_macos_route_state=$(eligibility_of network "$network_catalog" interfaces "$network_macos_route" "$darwin_fact") || network_macos_route_state=error
network_linux_on_darwin=$(eligibility_of network "$network_catalog" interfaces "$network_linux_interface" "$darwin_fact") || network_linux_on_darwin=error
if [ "$network_linux_without_ip" = ineligible ] && [ "$network_linux_with_ip" = eligible ] && \
   [ "$network_macos_route_state" = eligible ] && [ "$network_linux_on_darwin" = ineligible ]; then
  pass 'Network executable eligibility is fact-based and does not present known Linux routes on Darwin'
else
  fail 'Network executable eligibility is fact-based and does not present known Linux routes on Darwin'
fi

kafka_topics_state=$(eligibility_of kafka "$kafka_catalog" topics "$kafka_topics") || kafka_topics_state=error
kafka_offsets_without_script=$(eligibility_of kafka "$kafka_catalog" offset "$kafka_offsets") || kafka_offsets_without_script=error
make_tool "$fake_kafka/kafka-get-offsets.sh"
kafka_offsets_with_script=$(eligibility_of kafka "$kafka_catalog" offset "$kafka_offsets") || kafka_offsets_with_script=error
if [ "$kafka_topics_state" = eligible ] && [ "$kafka_offsets_without_script" = ineligible ] && \
   [ "$kafka_offsets_with_script" = eligible ]; then
  pass 'Kafka discovery proves only the exact declared sibling script, never the whole installation'
else
  fail 'Kafka discovery proves only the exact declared sibling script, never the whole installation'
fi

if [ "$failures" -ne 0 ]; then
  printf '\n%d of %d R13 catalog-requirements checks failed.\n' "$failures" "$checks" >&2
  exit 1
fi

printf '\n%d R13 catalog-requirements checks passed.\n' "$checks"
