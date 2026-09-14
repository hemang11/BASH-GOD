#!/usr/bin/env bash

# BASH_GOD Requirements Schema 1 eligibility foundation.
#
# This module owns declared-requirement parsing, bounded local facts, and a
# pure decision. It deliberately does not alter search, rendering, picker
# rows, editing, or execution; R12 owns that presentation boundary.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_god_eligibility_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || \
  _god_eligibility_dir=''
if [ -n "$_god_eligibility_dir" ] && [ -z "$(type -t _god_catalog_command_export 2>/dev/null)" ] && \
   [ -r "$_god_eligibility_dir/catalog.sh" ]; then
  # shellcheck source=catalog.sh
  . "$_god_eligibility_dir/catalog.sh" || exit 1
fi
if [ -n "$_god_eligibility_dir" ] && [ -z "$(type -t _god_discover_is_stale 2>/dev/null)" ] && \
   [ -r "$_god_eligibility_dir/discover.sh" ]; then
  # shellcheck source=discover.sh
  . "$_god_eligibility_dir/discover.sh" || exit 1
fi

# Facts are invocation-local, newline-separated tab records:
#
#   FACT<TAB>os<TAB>local<TAB>linux
#   FACT<TAB>tool<TAB>local:date<TAB>gnu
#   FACT<TAB>tool-version<TAB>local:date<TAB>9.4
#
# The optional fifth argument accepted by assess/collect supplies explicit
# facts. That is the only way to describe a remote system: this module never
# opens SSH, reads DNS, or guesses remote facts from a Target.

_god_eligibility_tab() {
  printf '\t'
}

_god_eligibility_append_line() {
  if [ -n "$1" ]; then
    printf '%s\n%s\n' "$1" "$2"
  else
    printf '%s\n' "$2"
  fi
}

_god_eligibility_is_numeric_version() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)*$ ]]
}

_god_eligibility_version_compare() {
  LC_ALL=C awk -v left="$1" -v right="$2" '
    BEGIN {
      left_count = split(left, left_parts, /\./)
      right_count = split(right, right_parts, /\./)
      total = left_count > right_count ? left_count : right_count
      for (position = 1; position <= total; position++) {
        left_value = position <= left_count ? left_parts[position] + 0 : 0
        right_value = position <= right_count ? right_parts[position] + 0 : 0
        if (left_value > right_value) { print 1; exit }
        if (left_value < right_value) { print -1; exit }
      }
      print 0
    }
  '
}

_god_eligibility_version_matches() {
  local actual constraint comparison expected result

  actual=$1
  constraint=$2
  case "$constraint" in
    '>='*) comparison='>='; expected=${constraint#>=} ;;
    '<='*) comparison='<='; expected=${constraint#<=} ;;
    '>'*) comparison='>'; expected=${constraint#>} ;;
    '<'*) comparison='<'; expected=${constraint#<} ;;
    '=') return 1 ;;
    =*) comparison='='; expected=${constraint#=} ;;
    *) return 1 ;;
  esac
  _god_eligibility_is_numeric_version "$actual" && _god_eligibility_is_numeric_version "$expected" || return 1
  result="$(_god_eligibility_version_compare "$actual" "$expected")"
  case "$comparison" in
    '>=') [ "$result" -ge 0 ] ;;
    '<=') [ "$result" -le 0 ] ;;
    '>') [ "$result" -gt 0 ] ;;
    '<') [ "$result" -lt 0 ] ;;
    '=') [ "$result" -eq 0 ] ;;
  esac
}

_god_eligibility_valid_tool_subject() {
  [[ "$1" =~ ^(local|service|remote):[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]
}

_god_eligibility_fact_exists() {
  local facts wanted_kind wanted_subject tab tag kind subject value extra

  facts=$1
  wanted_kind=$2
  wanted_subject=$3
  tab="$(_god_eligibility_tab)"
  while IFS="$tab" read -r tag kind subject value extra; do
    [ "$tag" = FACT ] || continue
    [ "$kind" = "$wanted_kind" ] && [ "$subject" = "$wanted_subject" ] && return 0
  done <<< "$facts"
  return 1
}

_god_eligibility_fact_value() {
  local facts wanted_kind wanted_subject tab tag kind subject value extra

  facts=$1
  wanted_kind=$2
  wanted_subject=$3
  tab="$(_god_eligibility_tab)"
  while IFS="$tab" read -r tag kind subject value extra; do
    [ "$tag" = FACT ] || continue
    [ "$kind" = "$wanted_kind" ] && [ "$subject" = "$wanted_subject" ] || continue
    printf '%s\n' "$value"
    return 0
  done <<< "$facts"
  return 1
}

_god_eligibility_facts_without() {
  local facts wanted_kind wanted_subject tab tag kind subject value extra

  facts=$1
  wanted_kind=$2
  wanted_subject=$3
  tab="$(_god_eligibility_tab)"
  while IFS="$tab" read -r tag kind subject value extra; do
    [ -n "$tag" ] || continue
    [ "$tag" = FACT ] && [ "$kind" = "$wanted_kind" ] && [ "$subject" = "$wanted_subject" ] && continue
    printf '%s\t%s\t%s\t%s\n' "$tag" "$kind" "$subject" "$value"
  done <<< "$facts"
}

_god_eligibility_fact_set() {
  _god_eligibility_facts_without "$1" "$2" "$3"
  printf 'FACT\t%s\t%s\t%s\n' "$2" "$3" "$4"
}

# A fact snapshot has one fact per kind/subject. Rejecting ambiguity here
# keeps the evaluator deterministic and makes a future remote source fail
# closed rather than override a local fact accidentally.
_god_eligibility_validate_facts() {
  local facts tab tag kind subject value extra seen key

  facts=$1
  tab="$(_god_eligibility_tab)"
  seen=''
  while IFS="$tab" read -r tag kind subject value extra; do
    [ -n "$tag" ] || continue
    if [ "$tag" != FACT ] || [ -z "$kind" ] || [ -z "$subject" ] || [ -z "$value" ] || [ -n "${extra:-}" ]; then
      printf 'BASH_GOD: invalid eligibility fact; expected FACT<TAB>KIND<TAB>SUBJECT<TAB>VALUE.\n' >&2
      return 2
    fi
    key="$kind$tab$subject"
    case "$seen" in
      *"$key"$'\n'*)
        printf 'BASH_GOD: duplicate eligibility fact for %s %s.\n' "$kind" "$subject" >&2
        return 2
        ;;
    esac
    seen="${seen}${key}"$'\n'
    case "$kind" in
      os)
        case "$subject:$value" in
          local:linux|local:darwin|local:freebsd|local:unknown|remote:linux|remote:darwin|remote:freebsd|remote:unknown) ;;
          *) printf 'BASH_GOD: invalid OS eligibility fact for %s.\n' "$subject" >&2; return 2 ;;
        esac
        ;;
      context)
        case "$subject:$value" in
          execution:local|execution:remote|execution:unknown) ;;
          *) printf 'BASH_GOD: invalid context eligibility fact.\n' >&2; return 2 ;;
        esac
        ;;
      shell)
        case "$subject:$value" in
          local:none|local:posix|local:bash|local:unknown|remote:none|remote:posix|remote:bash|remote:unknown) ;;
          *) printf 'BASH_GOD: invalid shell eligibility fact for %s.\n' "$subject" >&2; return 2 ;;
        esac
        ;;
      tool)
        _god_eligibility_valid_tool_subject "$subject" || {
          printf 'BASH_GOD: invalid tool eligibility subject %s.\n' "$subject" >&2
          return 2
        }
        case "$value" in
          present|absent|gnu|bsd|unknown) ;;
          *) printf 'BASH_GOD: invalid tool eligibility fact for %s.\n' "$subject" >&2; return 2 ;;
        esac
        ;;
      tool-version)
        _god_eligibility_valid_tool_subject "$subject" || {
          printf 'BASH_GOD: invalid tool-version eligibility subject %s.\n' "$subject" >&2
          return 2
        }
        [ "$value" = unknown ] || _god_eligibility_is_numeric_version "$value" || {
          printf 'BASH_GOD: invalid tool-version eligibility fact for %s.\n' "$subject" >&2
          return 2
        }
        ;;
      service-version)
        [ "$subject" = service ] && { [ "$value" = unknown ] || _god_eligibility_is_numeric_version "$value"; } || {
          printf 'BASH_GOD: invalid service-version eligibility fact.\n' >&2
          return 2
        }
        ;;
      *)
        printf 'BASH_GOD: unknown eligibility fact kind %s.\n' "$kind" >&2
        return 2
        ;;
    esac
  done <<< "$facts"
}

_god_eligibility_merge_facts() {
  local explicit generated merged tab tag kind subject value extra line

  explicit=$1
  generated=$2
  _god_eligibility_validate_facts "$explicit" || return $?
  _god_eligibility_validate_facts "$generated" || return $?
  merged=$explicit
  tab="$(_god_eligibility_tab)"
  while IFS="$tab" read -r tag kind subject value extra; do
    [ "$tag" = FACT ] || continue
    _god_eligibility_fact_exists "$merged" "$kind" "$subject" && continue
    line="$(printf 'FACT\t%s\t%s\t%s' "$kind" "$subject" "$value")"
    merged="$(_god_eligibility_append_line "$merged" "$line")"
  done <<< "$generated"
  printf '%s\n' "$merged"
}

# Normalizes schema defaults and command-level scalar overrides. No host
# command or discovery cache is read here, so the decision below stays pure.
_god_eligibility_effective_requirements() {
  local catalog group entry environment command_export tab tag kind subject value extra
  local schema os_local context_execution shell_local mode since until declared line

  catalog=$1
  group=$2
  entry=$3
  environment="$(_god_catalog_environment_export "$catalog")" || return 1
  tab="$(_god_eligibility_tab)"
  schema=''
  os_local=any
  context_execution=local
  shell_local=none
  while IFS="$tab" read -r tag kind subject value extra; do
    case "$tag" in
      SCHEMA) schema=$kind ;;
      DEFAULT)
        case "$kind:$subject" in
          os:local) os_local=$value ;;
          context:execution) context_execution=$value ;;
          shell:local) shell_local=$value ;;
        esac
        ;;
    esac
  done <<< "$environment"
  [ "$schema" = 1 ] || return 1

  mode=''
  since=''
  until=''
  declared=''
  command_export="$(_god_catalog_command_export "$catalog" "$group" "$entry")" || return 1
  while IFS="$tab" read -r tag kind subject value extra; do
    case "$tag" in
      MODE) mode=$kind ;;
      SINCE) since=$kind ;;
      UNTIL) until=$kind ;;
      REQUIRE)
        case "$kind:$subject" in
          os:local) os_local=$value ;;
          context:execution) context_execution=$value ;;
          shell:local) shell_local=$value ;;
          *)
            line="$(printf 'REQUIREMENT\t%s\t%s\t%s' "$kind" "$subject" "$value")"
            declared="$(_god_eligibility_append_line "$declared" "$line")"
            ;;
        esac
        ;;
    esac
  done <<< "$command_export"

  printf 'REQUIREMENT\tos\tlocal\t%s\n' "$os_local"
  printf 'REQUIREMENT\tcontext\texecution\t%s\n' "$context_execution"
  printf 'REQUIREMENT\tshell\tlocal\t%s\n' "$shell_local"
  [ -z "$declared" ] || printf '%s\n' "$declared"
  if [ "$mode" != LOCAL ] && { [ -n "$since" ] || [ -n "$until" ]; }; then
    printf 'REQUIREMENT\tservice-version\tservice\t%s\t%s\n' "$since" "$until"
  fi
}

_god_eligibility_requirement_value() {
  local requirements wanted_kind wanted_subject tab tag kind subject value extra

  requirements=$1
  wanted_kind=$2
  wanted_subject=$3
  tab="$(_god_eligibility_tab)"
  while IFS="$tab" read -r tag kind subject value extra; do
    [ "$tag" = REQUIREMENT ] && [ "$kind" = "$wanted_kind" ] && [ "$subject" = "$wanted_subject" ] || continue
    printf '%s\n' "$value"
    return 0
  done <<< "$requirements"
  return 1
}

_god_eligibility_tool_needs_metadata() {
  local requirements wanted_subject wanted_value tab tag kind subject value extra

  requirements=$1
  wanted_subject=$2
  wanted_value=$3
  [ "$wanted_value" = present ] || return 0
  tab="$(_god_eligibility_tab)"
  while IFS="$tab" read -r tag kind subject value extra; do
    [ "$tag" = REQUIREMENT ] && [ "$kind" = tool-version ] && [ "$subject" = "$wanted_subject" ] && return 0
  done <<< "$requirements"
  return 1
}

_god_eligibility_local_os() {
  case "$(LC_ALL=C uname -s 2>/dev/null)" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    FreeBSD) printf 'freebsd\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

_god_eligibility_local_shell() {
  if [ -n "${BASH_VERSION:-}" ]; then
    printf 'bash\n'
  else
    printf 'unknown\n'
  fi
}

_god_eligibility_local_tool_path() {
  local name hit

  name=$1
  hit="$(command -v "$name" 2>/dev/null)" || hit=''
  case "$hit" in
    /*) [ -f "$hit" ] && [ -x "$hit" ] && printf '%s\n' "$hit" ;;
  esac
}

# _god_discover_is_stale has an intentionally inverted convention: return 0
# means stale, return 1 means its selected probe is still fresh.
_god_eligibility_fresh_service_directory() {
  local service catalog path

  service=$1
  catalog=$2
  [ -n "$(type -t _god_catalog_has_discover 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_discover_is_stale 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_discover_path 2>/dev/null)" ] || return 1
  _god_catalog_has_discover "$catalog" || return 1
  if _god_discover_is_stale "$service" "$catalog"; then
    return 1
  fi
  path="$(_god_discover_path "$service" 2>/dev/null)" || return 1
  [ -n "$path" ] && [ -d "$path" ] && printf '%s\n' "$path"
}

_god_eligibility_service_version() {
  local service catalog version

  service=$1
  catalog=$2
  _god_eligibility_fresh_service_directory "$service" "$catalog" >/dev/null || return 1
  [ -n "$(type -t _god_discover_version 2>/dev/null)" ] || return 1
  version="$(_god_discover_version "$service" 2>/dev/null)" || return 1
  _god_eligibility_is_numeric_version "$version" || return 1
  printf '%s\n' "$version"
}

_god_eligibility_first_version() {
  LC_ALL=C awk '
    match($0, /[0-9]+([.][0-9]+)+/) { print substr($0, RSTART, RLENGTH); exit }
  '
}

# The only version probe is a declared, locally verified executable receiving
# exactly literal --version. It is direct (no eval), never an @run line, never
# remote, and its result is not persisted.
_god_eligibility_probe_tool_metadata() {
  local tool_path output implementation version

  tool_path=$1
  output="$(LC_ALL=C "$tool_path" --version 2>&1)" || true
  implementation=present
  case "$output" in
    *GNU*|*gnu*) implementation=gnu ;;
    *BSD*|*bsd*) implementation=bsd ;;
  esac
  version="$(printf '%s\n' "$output" | _god_eligibility_first_version)"
  printf '%s\t%s\n' "$implementation" "$version"
}

# Collects only declared requirements. Local facts are fresh for every call,
# which invalidates PATH changes. Discovery-cache facts are used only after
# its selected probe is rechecked; stale/missing state becomes unknown rather
# than false. R11 has no persistent eligibility-fact cache or remote probing.
_god_eligibility_collect_facts() {
  local service catalog group entry explicit requirements generated tab tag kind subject value extra
  local context path service_directory service_directory_known scope name tool_value metadata implementation version service_version line

  service=$1
  catalog=$2
  group=$3
  entry=$4
  explicit=${5:-}
  requirements="$(_god_eligibility_effective_requirements "$catalog" "$group" "$entry")" || return 1
  _god_eligibility_validate_facts "$explicit" || return $?
  generated=''
  tab="$(_god_eligibility_tab)"

  if ! _god_eligibility_fact_exists "$explicit" os local; then
    line="$(printf 'FACT\tos\tlocal\t%s' "$(_god_eligibility_local_os)")"
    generated="$(_god_eligibility_append_line "$generated" "$line")"
  fi
  context="$(_god_eligibility_requirement_value "$requirements" context execution)" || context=unknown
  if ! _god_eligibility_fact_exists "$explicit" context execution; then
    line="$(printf 'FACT\tcontext\texecution\t%s' "$context")"
    generated="$(_god_eligibility_append_line "$generated" "$line")"
  fi
  if ! _god_eligibility_fact_exists "$explicit" shell local; then
    line="$(printf 'FACT\tshell\tlocal\t%s' "$(_god_eligibility_local_shell)")"
    generated="$(_god_eligibility_append_line "$generated" "$line")"
  fi

  while IFS="$tab" read -r tag kind subject value extra; do
    [ "$tag" = REQUIREMENT ] && [ "$kind" = tool ] || continue
    scope=${subject%%:*}
    name=${subject#*:}
    path=''
    service_directory=''
    service_directory_known=0
    if _god_eligibility_fact_exists "$explicit" tool "$subject"; then
      tool_value="$(_god_eligibility_fact_value "$explicit" tool "$subject")"
    else
      case "$scope" in
        local) path="$(_god_eligibility_local_tool_path "$name")" ;;
        service)
          service_directory="$(_god_eligibility_fresh_service_directory "$service" "$catalog" 2>/dev/null)"
          if [ -n "$service_directory" ]; then
            service_directory_known=1
            path="$service_directory/$name"
          fi
          [ -x "$path" ] || path=''
          ;;
        remote) ;;
      esac
      case "$scope" in
        remote) tool_value=unknown ;;
        service)
          # A missing sibling in a freshly rechecked service directory is a
          # known false. A stale/no discovery cache is not evidence that the
          # sibling is absent, so leave that fact unknown.
          [ "$service_directory_known" -eq 1 ] || continue
          if [ -n "$path" ]; then tool_value=present; else tool_value=absent; fi
          line="$(printf 'FACT\ttool\t%s\t%s' "$subject" "$tool_value")"
          generated="$(_god_eligibility_append_line "$generated" "$line")"
          ;;
        *)
          if [ -n "$path" ]; then tool_value=present; else tool_value=absent; fi
          line="$(printf 'FACT\ttool\t%s\t%s' "$subject" "$tool_value")"
          generated="$(_god_eligibility_append_line "$generated" "$line")"
          ;;
      esac
    fi

    [ -n "$path" ] || {
      case "$scope" in
        local) path="$(_god_eligibility_local_tool_path "$name")" ;;
        service)
          if [ -z "$service_directory" ]; then
            service_directory="$(_god_eligibility_fresh_service_directory "$service" "$catalog" 2>/dev/null)"
          fi
          [ -z "$service_directory" ] || {
            path="$service_directory/$name"
            [ -x "$path" ] || path=''
          }
          ;;
      esac
    }
    [ -n "$path" ] || continue
    _god_eligibility_tool_needs_metadata "$requirements" "$subject" "$value" || continue
    metadata="$(_god_eligibility_probe_tool_metadata "$path")"
    IFS="$tab" read -r implementation version <<< "$metadata"
    if ! _god_eligibility_fact_exists "$explicit" tool "$subject" && \
       { [ "$implementation" = gnu ] || [ "$implementation" = bsd ]; }; then
      generated="$(_god_eligibility_fact_set "$generated" tool "$subject" "$implementation")"
    fi
    if ! _god_eligibility_fact_exists "$explicit" tool-version "$subject" && \
       _god_eligibility_is_numeric_version "$version"; then
      line="$(printf 'FACT\ttool-version\t%s\t%s' "$subject" "$version")"
      generated="$(_god_eligibility_append_line "$generated" "$line")"
    fi
  done <<< "$requirements"

  if _god_eligibility_requirement_value "$requirements" service-version service >/dev/null && \
     ! _god_eligibility_fact_exists "$explicit" service-version service; then
    service_version="$(_god_eligibility_service_version "$service" "$catalog" 2>/dev/null)"
    if _god_eligibility_is_numeric_version "$service_version"; then
      line="$(printf 'FACT\tservice-version\tservice\t%s' "$service_version")"
      generated="$(_god_eligibility_append_line "$generated" "$line")"
    fi
  fi

  _god_eligibility_merge_facts "$explicit" "$generated"
}

# Validates the small normalized requirement language consumed by the pure
# evaluator. Catalog validation is the authoritative syntax check; this
# defensive check keeps the public evaluator deterministic if a future caller
# passes malformed exported data directly.
_god_eligibility_validate_requirements() {
  local requirements tab tag kind subject value extra key scalar_seen tool_seen version_constraint_pattern
  local context_execution remote_requirement remote_meaningful

  requirements=$1
  tab="$(_god_eligibility_tab)"
  scalar_seen=''
  tool_seen=''
  context_execution=local
  remote_requirement=0
  remote_meaningful=0
  version_constraint_pattern='^(>=|>|=|<=|<)[0-9]+([.][0-9]+)*$'
  while IFS="$tab" read -r tag kind subject value extra; do
    [ -n "$tag" ] || continue
    if [ "$tag" != REQUIREMENT ] || [ -z "$kind" ] || [ -z "$subject" ]; then
      printf 'BASH_GOD: invalid eligibility requirement.\n' >&2
      return 2
    fi
    case "$kind" in
      os)
        case "$subject:$value" in
          local:any|local:linux|local:darwin|local:freebsd|remote:any|remote:linux|remote:darwin|remote:freebsd) ;;
          *) printf 'BASH_GOD: invalid OS eligibility requirement.\n' >&2; return 2 ;;
        esac
        [ -z "$extra" ] || { printf 'BASH_GOD: invalid OS eligibility requirement.\n' >&2; return 2; }
        key="$kind$tab$subject"
        case "$scalar_seen" in *"$key"$'\n'*) printf 'BASH_GOD: duplicate eligibility requirement for %s %s.\n' "$kind" "$subject" >&2; return 2 ;; esac
        scalar_seen="${scalar_seen}${key}"$'\n'
        if [ "$subject" = remote ]; then
          remote_requirement=1
          [ "$value" = any ] || remote_meaningful=1
        fi
        ;;
      context)
        [ "$subject" = execution ] && { [ "$value" = local ] || [ "$value" = remote ]; } && [ -z "$extra" ] || {
          printf 'BASH_GOD: invalid execution-context eligibility requirement.\n' >&2
          return 2
        }
        key="$kind$tab$subject"
        case "$scalar_seen" in *"$key"$'\n'*) printf 'BASH_GOD: duplicate eligibility requirement for %s %s.\n' "$kind" "$subject" >&2; return 2 ;; esac
        scalar_seen="${scalar_seen}${key}"$'\n'
        context_execution=$value
        ;;
      shell)
        case "$subject:$value" in
          local:none|local:posix|local:bash|remote:none|remote:posix|remote:bash) ;;
          *) printf 'BASH_GOD: invalid shell eligibility requirement.\n' >&2; return 2 ;;
        esac
        [ -z "$extra" ] || { printf 'BASH_GOD: invalid shell eligibility requirement.\n' >&2; return 2; }
        key="$kind$tab$subject"
        case "$scalar_seen" in *"$key"$'\n'*) printf 'BASH_GOD: duplicate eligibility requirement for %s %s.\n' "$kind" "$subject" >&2; return 2 ;; esac
        scalar_seen="${scalar_seen}${key}"$'\n'
        if [ "$subject" = remote ]; then
          remote_requirement=1
          [ "$value" = none ] || remote_meaningful=1
        fi
        ;;
      tool)
        _god_eligibility_valid_tool_subject "$subject" && { [ "$value" = present ] || [ "$value" = gnu ] || [ "$value" = bsd ]; } && [ -z "$extra" ] || {
          printf 'BASH_GOD: invalid tool eligibility requirement.\n' >&2
          return 2
        }
        key="$kind$tab$subject"
        case "$tool_seen" in *"$key"$'\n'*) printf 'BASH_GOD: duplicate tool eligibility requirement for %s.\n' "$subject" >&2; return 2 ;; esac
        tool_seen="${tool_seen}${key}"$'\n'
        case "$subject" in
          remote:*) remote_requirement=1; remote_meaningful=1 ;;
        esac
        ;;
      tool-version)
        _god_eligibility_valid_tool_subject "$subject" && [[ "$value" =~ $version_constraint_pattern ]] && [ -z "$extra" ] || {
          printf 'BASH_GOD: invalid tool-version eligibility requirement.\n' >&2
          return 2
        }
        case "$subject" in
          remote:*) remote_requirement=1 ;;
        esac
        ;;
      service-version)
        [ "$subject" = service ] && { [ -z "$value" ] || _god_eligibility_is_numeric_version "$value"; } && \
          { [ -z "$extra" ] || _god_eligibility_is_numeric_version "$extra"; } && \
          { [ -n "$value" ] || [ -n "$extra" ]; } || {
            printf 'BASH_GOD: invalid service-version eligibility requirement.\n' >&2
            return 2
          }
        ;;
      *)
        printf 'BASH_GOD: unknown eligibility requirement kind %s.\n' "$kind" >&2
        return 2
        ;;
    esac
  done <<< "$requirements"

  if [ "$context_execution" = local ] && [ "$remote_requirement" -ne 0 ]; then
    printf 'BASH_GOD: remote eligibility requirements require remote execution context.\n' >&2
    return 2
  fi
  if [ "$context_execution" = remote ] && [ "$remote_meaningful" -eq 0 ]; then
    printf 'BASH_GOD: remote execution requires a meaningful remote OS, shell, or tool requirement.\n' >&2
    return 2
  fi
}

# _god_eligibility_decide REQUIREMENTS FACTS
#
# This is intentionally pure: it reads no cache, PATH, OS, shell, target, or
# remote state. Its only inputs are the normalized requirement set and a
# validated snapshot of bounded facts. It prints stable machine-readable
# records for R12:
#
#   ELIGIBILITY<TAB>eligible|ineligible|unknown
#   REASON<TAB>human-readable explanation   (zero or more)
_god_eligibility_decide() {
  local requirements facts tab tag kind subject value extra actual false_reasons unknown_reasons reason assessment

  requirements=$1
  facts=$2
  _god_eligibility_validate_requirements "$requirements" || return $?
  _god_eligibility_validate_facts "$facts" || return $?
  tab="$(_god_eligibility_tab)"
  false_reasons=''
  unknown_reasons=''

  while IFS="$tab" read -r tag kind subject value extra; do
    [ "$tag" = REQUIREMENT ] || continue
    actual=''
    reason=''
    assessment=''
    case "$kind" in
      os)
        [ "$value" = any ] && continue
        actual="$(_god_eligibility_fact_value "$facts" os "$subject")" || actual=''
        case "$actual" in
          "$value") ;;
          ''|unknown) assessment=unknown; reason="requires $subject OS $value; that OS is unknown" ;;
          *) assessment=ineligible; reason="requires $subject OS $value; found $actual" ;;
        esac
        ;;
      context)
        actual="$(_god_eligibility_fact_value "$facts" context "$subject")" || actual=''
        case "$actual" in
          "$value") ;;
          ''|unknown) assessment=unknown; reason="requires $value execution context; context is unknown" ;;
          *) assessment=ineligible; reason="requires $value execution context; found $actual" ;;
        esac
        ;;
      shell)
        [ "$value" = none ] && continue
        actual="$(_god_eligibility_fact_value "$facts" shell "$subject")" || actual=''
        case "$value:$actual" in
          posix:posix|posix:bash|bash:bash) ;;
          *:|*:unknown) assessment=unknown; reason="requires $subject $value shell; shell is unknown" ;;
          *) assessment=ineligible; reason="requires $subject $value shell; found $actual" ;;
        esac
        ;;
      tool)
        actual="$(_god_eligibility_fact_value "$facts" tool "$subject")" || actual=''
        case "$value:$actual" in
          present:present|present:gnu|present:bsd|gnu:gnu|bsd:bsd) ;;
          *:|*:unknown) assessment=unknown; reason="requires $subject $value; tool state is unknown" ;;
          *:absent) assessment=ineligible; reason="requires $subject $value; tool is absent" ;;
          gnu:present|bsd:present) assessment=unknown; reason="requires $subject $value; implementation is unknown" ;;
          *) assessment=ineligible; reason="requires $subject $value; found $actual" ;;
        esac
        ;;
      tool-version)
        actual="$(_god_eligibility_fact_value "$facts" tool-version "$subject")" || actual=''
        case "$actual" in
          ''|unknown) assessment=unknown; reason="requires $subject version $value; version is unknown" ;;
          *)
            if _god_eligibility_version_matches "$actual" "$value"; then
              :
            else
              assessment=ineligible; reason="requires $subject version $value; found $actual"
            fi
            ;;
        esac
        ;;
      service-version)
        actual="$(_god_eligibility_fact_value "$facts" service-version service)" || actual=''
        case "$actual" in
          ''|unknown) assessment=unknown; reason='requires a known service version; version is unknown' ;;
          *)
            if { [ -z "$value" ] || _god_eligibility_version_matches "$actual" ">=$value"; } && \
               { [ -z "$extra" ] || _god_eligibility_version_matches "$actual" "<=$extra"; }; then
              :
            else
              if [ -n "$value" ] && ! _god_eligibility_version_matches "$actual" ">=$value"; then
                assessment=ineligible; reason="requires service version >=$value; found $actual"
              else
                assessment=ineligible; reason="requires service version <=$extra; found $actual"
              fi
            fi
            ;;
        esac
        ;;
    esac

    [ -z "$reason" ] && continue
    case "$assessment" in
      unknown) unknown_reasons="$(_god_eligibility_append_line "$unknown_reasons" "$reason")" ;;
      ineligible) false_reasons="$(_god_eligibility_append_line "$false_reasons" "$reason")" ;;
      *)
        printf 'BASH_GOD: invalid eligibility assessment state.\n' >&2
        return 2
        ;;
    esac
  done <<< "$requirements"

  if [ -n "$false_reasons" ]; then
    printf 'ELIGIBILITY\tineligible\n'
    while IFS= read -r reason; do
      [ -n "$reason" ] && printf 'REASON\t%s\n' "$reason"
    done <<< "$false_reasons"
  elif [ -n "$unknown_reasons" ]; then
    printf 'ELIGIBILITY\tunknown\n'
    while IFS= read -r reason; do
      [ -n "$reason" ] && printf 'REASON\t%s\n' "$reason"
    done <<< "$unknown_reasons"
  else
    printf 'ELIGIBILITY\teligible\n'
  fi
}

# _god_eligibility_assess SERVICE CATALOG GROUP ENTRY [EXPLICIT_FACTS]
#
# Shared orchestration above the pure decision. It is intentionally unused by
# current browse/picker paths: Schema-0 catalogs remain behaviorally identical
# until R12 elects to consume the answer for an executable-only view.
_god_eligibility_assess() {
  local service catalog group entry explicit schema requirements facts

  service=$1
  catalog=$2
  group=$3
  entry=$4
  explicit=${5:-}
  _god_validate_catalog "$catalog" || return 2
  schema="$(_god_catalog_environment_schema "$catalog")"
  if [ "$schema" != 1 ]; then
    printf 'ELIGIBILITY\tunknown\n'
    printf 'REASON\tCatalog uses Requirements Schema 0.\n'
    return 0
  fi
  requirements="$(_god_eligibility_effective_requirements "$catalog" "$group" "$entry")" || return 2
  facts="$(_god_eligibility_collect_facts "$service" "$catalog" "$group" "$entry" "$explicit")" || return $?
  _god_eligibility_decide "$requirements" "$facts"
}
