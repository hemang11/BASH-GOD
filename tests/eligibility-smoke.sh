#!/usr/bin/env bash

# Requirements Schema 1 foundation checks. Every executable mentioned here is
# a fake under the fixture directory. The only permitted invocations are
# declared fake --version probes; no catalog @run, SSH, network, cloud, or
# local service command is allowed to execute.

set -o nounset
set -o pipefail

test_file=$BASH_SOURCE
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

field_value() {
  local records wanted tab tag value rest

  records=$1
  wanted=$2
  tab=$(printf '\t')
  while IFS="$tab" read -r tag value rest; do
    [ "$tag" = "$wanted" ] || continue
    printf '%s\n' "$value"
    return 0
  done <<< "$records"
  return 1
}

write_lines() {
  local path

  path=$1
  shift
  printf '%s\n' "$@" > "$path"
}

fixture=$(mktemp -d /tmp/bash-god-eligibility.XXXXXX) || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

catalog_dir=$fixture/catalog
fake_bin=$fixture/fake-bin
broker_dir=$fixture/broker
native_log=$fixture/native.log
system_path=$PATH
bash_bin=$(command -v bash)
awk_bin=$(command -v awk)
mkdir -p "$catalog_dir" "$fake_bin" "$broker_dir" "$fixture/home" "$fixture/config" "$fixture/state" || exit 1
: > "$native_log"

export HOME=$fixture/home
export XDG_CONFIG_HOME=$fixture/config
export XDG_STATE_HOME=$fixture/state
export BASH_GOD_R11_NATIVE_LOG=$native_log
export BASH_GOD_R11_OS=Linux

# These fixtures shadow bounded fact probes only. None implements a catalog
# operation, and a call other than --version is a test failure.
write_lines "$fake_bin/uname" \
  "#!$bash_bin" \
  'if [ "$1" = -s ]; then printf "%s\n" "$BASH_GOD_R11_OS"; exit 0; fi' \
  'exit 97'
write_lines "$fake_bin/awk" \
  "#!$bash_bin" \
  "exec \"$awk_bin\" \"\$@\""
write_lines "$fake_bin/date" \
  "#!$bash_bin" \
  'printf "date|%s\n" "$*" >> "$BASH_GOD_R11_NATIVE_LOG"' \
  'if [ "$1" = --version ]; then printf "date (GNU coreutils) %s\n" "$BASH_GOD_R11_DATE_VERSION"; exit 0; fi' \
  'exit 97'
write_lines "$fake_bin/r11-ss" \
  "#!$bash_bin" \
  'printf "r11-ss|%s\n" "$*" >> "$BASH_GOD_R11_NATIVE_LOG"' \
  'exit 97'
write_lines "$fake_bin/r11-grep" \
  "#!$bash_bin" \
  'printf "r11-grep|%s\n" "$*" >> "$BASH_GOD_R11_NATIVE_LOG"' \
  'exit 97'
write_lines "$fake_bin/r11-ssh" \
  "#!$bash_bin" \
  'printf "r11-ssh|%s\n" "$*" >> "$BASH_GOD_R11_NATIVE_LOG"' \
  'exit 97'
write_lines "$broker_dir/r11-broker" \
  "#!$bash_bin" \
  'printf "r11-broker|%s\n" "$*" >> "$BASH_GOD_R11_NATIVE_LOG"' \
  'if [ "$1" = --version ]; then printf "r11-broker %s\n" "$BASH_GOD_R11_BROKER_VERSION"; exit 0; fi' \
  'exit 97'
chmod 0700 \
  "$fake_bin/uname" \
  "$fake_bin/awk" \
  "$fake_bin/date" \
  "$fake_bin/r11-ss" \
  "$fake_bin/r11-grep" \
  "$fake_bin/r11-ssh" \
  "$broker_dir/r11-broker" || exit 1

write_lines "$catalog_dir/linux-missing.god" \
  '@title Linux missing-tool fixture' \
  '@description' \
  'A fixture for a Linux-only service-manager command.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | linux' \
  'context | execution | local' \
  'shell | local | none' \
  '@group service' \
  '@command Check a Linux service manager' \
  '@mode LOCAL' \
  '@requires' \
  'tool | local:r11-systemctl | present' \
  '@description' \
  'Uses a Linux service-manager binary.' \
  '@run' \
  'r11-systemctl status r11' \
  '@end'

write_lines "$catalog_dir/gnu-date.god" \
  '@title GNU date fixture' \
  '@description' \
  'A fixture for a separately installed GNU utility.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  'context | execution | local' \
  'shell | local | none' \
  '@group time' \
  '@command Convert with GNU date' \
  '@mode LOCAL' \
  '@requires' \
  'tool | local:date | gnu' \
  'tool-version | local:date | >=9.0' \
  '@description' \
  'Uses the GNU date implementation.' \
  '@run' \
  "date -d '<timestamp>' +%s" \
  '@end'

write_lines "$catalog_dir/pipeline.god" \
  '@title Pipeline fixture' \
  '@description' \
  'A fixture for explicit external tools in one local pipeline.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  'context | execution | local' \
  'shell | local | none' \
  '@group inspect' \
  '@command Check a local listener' \
  '@mode LOCAL' \
  '@requires' \
  'shell | local | posix' \
  'tool | local:r11-ss | present' \
  'tool | local:r11-grep | present' \
  '@description' \
  'Names both tools used by the reviewed pipeline.' \
  '@run' \
  "r11-ss -ltnp | r11-grep ':27017'" \
  '@end'

write_lines "$catalog_dir/remote.god" \
  '@title Remote fixture' \
  '@description' \
  'A fixture for a deliberately unverified remote system.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  'context | execution | remote' \
  'shell | local | none' \
  '@group remote' \
  '@command Inspect a remote systemd unit' \
  '@mode LOCAL' \
  '@requires' \
  'tool | local:r11-ssh | present' \
  'os | remote | linux' \
  'tool | remote:r11-systemctl | present' \
  'shell | remote | posix' \
  '@description' \
  'Needs independently supplied remote facts.' \
  '@run' \
  "r11-ssh <host> 'r11-systemctl status <unit>'" \
  '@end'

write_lines "$catalog_dir/broker.god" \
  '@title Broker fixture' \
  '@description' \
  'A fixture for service-tool and service-version facts.' \
  '@discover' \
  'probe | r11-broker | Fixture broker client' \
  "root | $broker_dir | Fixture broker directory" \
  'version | <probe> --version | Fixture client version' \
  '@connection NONE' \
  '@synced 3.9' \
  '@environment 1' \
  'os | local | any' \
  'context | execution | local' \
  'shell | local | none' \
  '@group broker' \
  '@command Use a supported broker syntax' \
  '@mode MODERN' \
  '@since 3.0' \
  '@requires' \
  'tool | service:r11-broker | present' \
  'tool-version | service:r11-broker | >=3.0' \
  '@description' \
  'Requires a supported broker client and service version.' \
  '@run' \
  'r11-broker inspect' \
  '@end' \
  '@command Require a missing sibling tool' \
  '@mode MODERN' \
  '@since 3.0' \
  '@requires' \
  'tool | service:r11-helper | present' \
  '@description' \
  'Uses a sibling binary that is intentionally absent.' \
  '@run' \
  'r11-helper inspect' \
  '@end'

write_lines "$catalog_dir/missing-requires.god" \
  '@title Missing requirements fixture' \
  '@description' \
  'Invalid schema fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  '@group invalid' \
  '@command Missing requirements' \
  '@mode LOCAL' \
  '@description' \
  'Must be rejected.' \
  '@run' \
  'r11-invalid' \
  '@end'

write_lines "$catalog_dir/service-in-path.god" \
  '@title Service scope in path fixture' \
  '@description' \
  'Invalid schema fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  '@group invalid' \
  '@command Invalid service scope' \
  '@mode LOCAL' \
  '@requires' \
  'tool | service:r11-tool | present' \
  '@description' \
  'Must be rejected.' \
  '@run' \
  'r11-tool' \
  '@end'

write_lines "$catalog_dir/remote-local.god" \
  '@title Remote requirement with local context fixture' \
  '@description' \
  'Invalid schema fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'context | execution | local' \
  '@group invalid' \
  '@command Invalid remote requirement' \
  '@mode LOCAL' \
  '@requires' \
  'os | remote | linux' \
  '@description' \
  'Must be rejected.' \
  '@run' \
  'r11-invalid' \
  '@end'

write_lines "$catalog_dir/remote-neutral-os.god" \
  '@title Neutral remote OS fixture' \
  '@description' \
  'Invalid schema fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'context | execution | remote' \
  '@group invalid' \
  '@command Neutral remote OS is not evidence' \
  '@mode LOCAL' \
  '@requires' \
  'os | remote | any' \
  '@description' \
  'A neutral remote OS requirement cannot establish a remote environment.' \
  '@run' \
  'r11-invalid' \
  '@end'

write_lines "$catalog_dir/remote-neutral-shell.god" \
  '@title Neutral remote shell fixture' \
  '@description' \
  'Invalid schema fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'context | execution | remote' \
  '@group invalid' \
  '@command Neutral remote shell is not evidence' \
  '@mode LOCAL' \
  '@requires' \
  'shell | remote | none' \
  '@description' \
  'A neutral remote shell requirement cannot establish a remote environment.' \
  '@run' \
  'r11-invalid' \
  '@end'

write_lines "$catalog_dir/misplaced-requires.god" \
  '@title Misplaced requirements fixture' \
  '@description' \
  'Invalid schema fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  '@group invalid' \
  '@command Misplaced requirements' \
  '@mode LOCAL' \
  '@description' \
  'Requirements must precede this field.' \
  '@requires' \
  'tool | local:r11-tool | present' \
  '@run' \
  'r11-tool' \
  '@end'

write_lines "$catalog_dir/version-without-tool.god" \
  '@title Unmatched tool version fixture' \
  '@description' \
  'Invalid schema fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  '@group invalid' \
  '@command Version without tool' \
  '@mode LOCAL' \
  '@requires' \
  'tool-version | local:r11-tool | >=1.0' \
  '@description' \
  'A version constraint needs its matching tool row.' \
  '@run' \
  'r11-tool' \
  '@end'

write_lines "$catalog_dir/schema-zero.god" \
  '@title Schema-zero fixture' \
  '@description' \
  'A fixture retained to prove the staged migration fallback.' \
  '@execution PATH' \
  '@connection NONE' \
  '@group legacy' \
  '@command Browse an unreviewed legacy command' \
  '@mode LOCAL' \
  '@description' \
  'Has no reviewed Requirements Schema 1 declaration.' \
  '@run' \
  'r11-legacy inspect' \
  '@end'

# Source only shared parser/discovery/eligibility modules. No route or
# catalog operation is invoked in this suite.
# shellcheck source=../src/catalog.sh
. "$project_dir/src/catalog.sh"
# shellcheck source=../src/discover.sh
. "$project_dir/src/discover.sh"
# shellcheck source=../src/eligibility.sh
. "$project_dir/src/eligibility.sh"

PATH="$fake_bin:$system_path"
export PATH
tab=$(printf '\t')

schema_zero="$catalog_dir/schema-zero.god"
schema_zero_result="$(_god_eligibility_assess schema-zero "$schema_zero" legacy 1)"
if _god_validate_catalog "$schema_zero" && \
   [ -z "$(_god_catalog_environment_schema "$schema_zero")" ] && \
   [ "$(field_value "$schema_zero_result" ELIGIBILITY)" = unknown ] && \
   contains "$schema_zero_result" 'Catalog uses Requirements Schema 0.'; then
  pass 'Schema-0 fixtures remain valid and explicitly unverified during the staged migration'
else
  fail 'Schema-0 fixtures remain valid and explicitly unverified during the staged migration'
fi

gnu_export="$(_god_catalog_environment_export "$catalog_dir/gnu-date.god")"
gnu_command_export="$(_god_catalog_command_export "$catalog_dir/gnu-date.god" time 1)"
if _god_validate_catalog "$catalog_dir/gnu-date.god" && \
   contains "$gnu_export" "SCHEMA""$tab""1" && \
   contains "$gnu_export" "DEFAULT""$tab""os""$tab""local""$tab""any" && \
   contains "$gnu_command_export" "REQUIRE""$tab""tool""$tab""local:date""$tab""gnu" && \
   contains "$gnu_command_export" "REQUIRE""$tab""tool-version""$tab""local:date""$tab"">=9.0"; then
  pass 'Schema-1 parser exports service defaults and per-command requirements'
else
  fail 'Schema-1 parser exports service defaults and per-command requirements'
fi

invalid_count=0
for invalid_catalog in \
  "$catalog_dir/missing-requires.god" \
  "$catalog_dir/service-in-path.god" \
  "$catalog_dir/remote-local.god" \
  "$catalog_dir/remote-neutral-os.god" \
  "$catalog_dir/remote-neutral-shell.god" \
  "$catalog_dir/misplaced-requires.god" \
  "$catalog_dir/version-without-tool.god"; do
  _god_validate_catalog "$invalid_catalog" >/dev/null 2>&1 || invalid_count=$((invalid_count + 1))
done
if [ "$invalid_count" -eq 7 ]; then
  pass 'Schema-1 validation rejects missing, misplaced, contradictory, and neutral-only remote requirements'
else
  fail 'Schema-1 validation rejects missing, misplaced, contradictory, and neutral-only remote requirements'
fi

# The pure evaluator is also defensive because future callers consume its
# normalized records directly. A malformed remote-neutral set must fail rather
# than turn into an eligible result when catalog validation was bypassed.
neutral_remote_requirements=$(printf '%s\n' \
  "REQUIREMENT${tab}os${tab}local${tab}any" \
  "REQUIREMENT${tab}context${tab}execution${tab}remote" \
  "REQUIREMENT${tab}shell${tab}local${tab}none" \
  "REQUIREMENT${tab}shell${tab}remote${tab}none")
neutral_remote_facts=$(printf '%s\n' \
  "FACT${tab}os${tab}local${tab}linux" \
  "FACT${tab}context${tab}execution${tab}remote" \
  "FACT${tab}shell${tab}local${tab}bash")
if neutral_remote_result="$(_god_eligibility_decide "$neutral_remote_requirements" "$neutral_remote_facts" 2>&1)"; then
  fail 'Pure eligibility rejects neutral-only remote requirements'
  printf '%s\n' "$neutral_remote_result"
elif contains "$neutral_remote_result" 'remote execution requires a meaningful remote OS, shell, or tool requirement'; then
  pass 'Pure eligibility rejects neutral-only remote requirements'
else
  fail 'Pure eligibility rejects neutral-only remote requirements'
  printf '%s\n' "$neutral_remote_result"
fi

linux_missing="$(_god_eligibility_assess linux "$catalog_dir/linux-missing.god" service 1)"
if [ "$(field_value "$linux_missing" ELIGIBILITY)" = ineligible ] && \
   contains "$linux_missing" 'local:r11-systemctl present; tool is absent'; then
  pass 'Linux-only command with a missing local tool is deterministically ineligible'
else
  fail 'Linux-only command with a missing local tool is deterministically ineligible'
  printf '%s\n' "$linux_missing"
fi

# Decision state is structural, not inferred from the human-readable reason:
# `unknown` is a valid bare-tool-name fragment and an absent tool is known
# false regardless of how it is spelled.
unknown_tool_requirements=$(printf 'REQUIREMENT\ttool\tlocal:unknown-tool\tpresent')
unknown_tool_facts=$(printf 'FACT\ttool\tlocal:unknown-tool\tabsent')
unknown_tool_result="$(_god_eligibility_decide "$unknown_tool_requirements" "$unknown_tool_facts")"
if [ "$(field_value "$unknown_tool_result" ELIGIBILITY)" = ineligible ] && \
   contains "$unknown_tool_result" 'local:unknown-tool present; tool is absent'; then
  pass 'Known-ineligible facts remain ineligible when a valid tool name contains unknown'
else
  fail 'Known-ineligible facts remain ineligible when a valid tool name contains unknown'
  printf '%s\n' "$unknown_tool_result"
fi

export BASH_GOD_R11_OS=Darwin
export BASH_GOD_R11_DATE_VERSION=8.9
gnu_too_old="$(_god_eligibility_assess date "$catalog_dir/gnu-date.god" time 1)"
export BASH_GOD_R11_DATE_VERSION=9.4
gnu_on_darwin="$(_god_eligibility_assess date "$catalog_dir/gnu-date.god" time 1)"
if [ "$(field_value "$gnu_too_old" ELIGIBILITY)" = ineligible ] && \
   contains "$gnu_too_old" 'version >=9.0; found 8.9' && \
   [ "$(field_value "$gnu_on_darwin" ELIGIBILITY)" = eligible ]; then
  pass 'A separately installed GNU tool on macOS is eligible only at its declared version'
else
  fail 'A separately installed GNU tool on macOS is eligible only at its declared version'
  printf '%s\n%s\n' "$gnu_too_old" "$gnu_on_darwin"
fi

export BASH_GOD_R11_OS=Linux
pipeline_ok="$(_god_eligibility_assess pipeline "$catalog_dir/pipeline.god" inspect 1)"
command rm -f -- "$fake_bin/r11-grep"
pipeline_missing="$(_god_eligibility_assess pipeline "$catalog_dir/pipeline.god" inspect 1)"
if [ "$(field_value "$pipeline_ok" ELIGIBILITY)" = eligible ] && \
   [ "$(field_value "$pipeline_missing" ELIGIBILITY)" = ineligible ] && \
   contains "$pipeline_missing" 'local:r11-grep present; tool is absent'; then
  pass 'Every explicitly declared external tool in a local pipeline is evaluated fresh'
else
  fail 'Every explicitly declared external tool in a local pipeline is evaluated fresh'
  printf '%s\n%s\n' "$pipeline_ok" "$pipeline_missing"
fi

remote_unknown="$(_god_eligibility_assess remote "$catalog_dir/remote.god" remote 1)"
remote_facts=$(printf '%s\n' \
  "FACT""$tab""os""$tab""remote""$tab""linux" \
  "FACT""$tab""shell""$tab""remote""$tab""posix" \
  "FACT""$tab""tool""$tab""remote:r11-systemctl""$tab""present")
remote_explicit="$(_god_eligibility_assess remote "$catalog_dir/remote.god" remote 1 "$remote_facts")"
if [ "$(field_value "$remote_unknown" ELIGIBILITY)" = unknown ] && \
   contains "$remote_unknown" 'remote OS linux; that OS is unknown' && \
   [ "$(field_value "$remote_explicit" ELIGIBILITY)" = eligible ]; then
  pass 'Meaningful remote requirements stay unknown until an explicit remote fact snapshot supplies them'
else
  fail 'Meaningful remote requirements stay unknown until an explicit remote fact snapshot supplies them'
  printf '%s\n%s\n' "$remote_unknown" "$remote_explicit"
fi

export BASH_GOD_R11_BROKER_VERSION=2.8
_god_discover_resolve broker "$catalog_dir/broker.god" || exit 1
broker_unsupported="$(_god_eligibility_assess broker "$catalog_dir/broker.god" broker 1)"
export BASH_GOD_R11_BROKER_VERSION=unknown
_god_discover_resolve broker "$catalog_dir/broker.god" || exit 1
broker_unknown="$(_god_eligibility_assess broker "$catalog_dir/broker.god" broker 1)"
export BASH_GOD_R11_BROKER_VERSION=3.9.2
_god_discover_resolve broker "$catalog_dir/broker.god" || exit 1
broker_eligible="$(_god_eligibility_assess broker "$catalog_dir/broker.god" broker 1)"
broker_sibling_missing="$(_god_eligibility_assess broker "$catalog_dir/broker.god" broker 2)"
if [ "$(field_value "$broker_unsupported" ELIGIBILITY)" = ineligible ] && \
   contains "$broker_unsupported" 'requires service version >=3.0; found 2.8' && \
   [ "$(field_value "$broker_unknown" ELIGIBILITY)" = unknown ] && \
   [ "$(field_value "$broker_eligible" ELIGIBILITY)" = eligible ] && \
   [ "$(field_value "$broker_sibling_missing" ELIGIBILITY)" = ineligible ] && \
   contains "$broker_sibling_missing" 'service:r11-helper present; tool is absent'; then
  pass 'Service versions, service tools, unsupported versions, and unknown versions have distinct outcomes'
else
  fail 'Service versions, service tools, unsupported versions, and unknown versions have distinct outcomes'
  printf '%s\n%s\n%s\n%s\n' "$broker_unsupported" "$broker_unknown" "$broker_eligible" "$broker_sibling_missing"
fi

command rm -f -- "$broker_dir/r11-broker"
broker_stale="$(_god_eligibility_assess broker "$catalog_dir/broker.god" broker 1)"
if [ "$(field_value "$broker_stale" ELIGIBILITY)" = unknown ] && \
   contains "$broker_stale" 'service:r11-broker present; tool state is unknown'; then
  pass 'A stale discovery cache becomes unknown rather than claiming a missing service tool'
else
  fail 'A stale discovery cache becomes unknown rather than claiming a missing service tool'
  printf '%s\n' "$broker_stale"
fi

unexpected_native=$(LC_ALL=C awk -F'|' '
  $1 == "date" && $2 == "--version" { next }
  $1 == "r11-broker" && $2 == "--version" { next }
  { print }
' "$native_log")
if [ -z "$unexpected_native" ] && \
   ! LC_ALL=C grep -Fq 'r11-ssh|' "$native_log" && \
   ! LC_ALL=C grep -Fq 'r11-ss|' "$native_log" && \
   ! LC_ALL=C grep -Fq 'r11-grep|' "$native_log"; then
  pass 'Eligibility uses only bounded fake version probes and never runs catalog operations'
else
  fail 'Eligibility uses only bounded fake version probes and never runs catalog operations'
  printf '%s\n' "$native_log"
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d eligibility checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d eligibility checks failed.\n' "$failures" "$checks" >&2
exit 1
