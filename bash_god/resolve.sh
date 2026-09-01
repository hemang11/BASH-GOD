#!/usr/bin/env bash

# BASH_GOD value resolution. Turns a catalog @run template plus the user's
# free-text query into two things: a human-readable DISPLAY command for the
# confirm screen, and an EXECUTE template with every user-influenced value
# lifted out to a positional parameter so it is never interpolated into shell
# syntax (execute.sh substitutes those values as arguments, not text).
#
# The engine here knows mechanisms (keyword buckets, placeholder syntax); it
# never special-cases kafka or any other service name.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_god_resolve_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || \
  _god_resolve_dir=''
if [ -n "$_god_resolve_dir" ] && [ -z "$(type -t _god_catalog_command_export 2>/dev/null)" ] && \
   [ -r "$_god_resolve_dir/catalog.sh" ]; then
  # shellcheck source=catalog.sh
  . "$_god_resolve_dir/catalog.sh" || exit 1
fi

# ---------------------------------------------------------------------------
# Pure string transforms: same input always gives same output, no filesystem
# or terminal access.
# ---------------------------------------------------------------------------

# _god_resolve_rewrite_paths RUN EXECUTION_PATH [DISCOVER_PROBES] [SELECTED_TOOL]
#
# A leading `./tool` becomes `<execution_path>/tool`; `../config/...` is
# relative to that same bin directory, not the caller's cwd, so it becomes
# `<execution_path>/../config/...`. A discovered catalog may declare an
# ordered family of native probes (for example, `mongosh` then legacy `mongo`).
# A catalog's ordered probe family declares compatible client spellings: when
# one is the first word of a non-LOCAL record, it becomes the discovered
# family member at `<execution_path>/selected-tool`. No other bare command is
# rewritten. A record with no execution path (service not resolved, or @mode
# LOCAL) is returned unchanged.
_god_resolve_rewrite_paths() {
  local run execution_path discover_probes selected_tool discover_probe token out
  local -a tokens

  run=$1
  execution_path=$2
  discover_probes=${3:-}
  selected_tool=${4:-}
  [ -n "$execution_path" ] || { printf '%s\n' "$run"; return 0; }

  # Probes are grammar-validated bare executable names. A declared probe
  # family is an explicit catalog assertion that the selected member can run
  # its client rows, so use that selected member rather than leaking a stale
  # sibling spelling from the catalog into the caller's PATH.
  while IFS= read -r discover_probe; do
    [ -n "$discover_probe" ] || continue
    case "$run" in
      "$discover_probe"|"$discover_probe "*)
        [ -n "$selected_tool" ] || selected_tool=$discover_probe
        if [ -x "$execution_path/$selected_tool" ]; then
          run="${execution_path}/${selected_tool}${run#"$discover_probe"}"
        fi
        break
        ;;
    esac
  done <<< "$discover_probes"

  IFS=' ' read -r -a tokens <<< "$run"
  out=''
  for token in "${tokens[@]}"; do
    case "$token" in
      ./*) token="${execution_path}/${token#./}" ;;
      ../*) token="${execution_path}/${token}" ;;
    esac
    out="${out:+$out }$token"
  done
  printf '%s\n' "$out"
}

# _god_resolve_rewrite_endpoint RUN TARGET PORT
#
# Catalog text stays copyable with localhost:<port>. Once explicit resync has
# cached an endpoint authority, only the reviewed runtime model rewrites that
# exact default. This deliberately does not rewrite arbitrary hosts, URLs, or
# user-provided values.
_god_resolve_rewrite_endpoint() {
  local run target port default_target

  run=$1
  target=$2
  port=$3
  [ -n "$target" ] && [ -n "$port" ] || { printf '%s\n' "$run"; return 0; }
  default_target="localhost:$port"
  printf '%s\n' "${run//"$default_target"/$target}"
}

# _god_resolve_harvest QUERY
#
# What ranking ignores: quoted phrases and ALL_CAPS/underscored words are
# name-like; bare integers (including negative) are numeric. Printed in the
# order encountered as NAME\t<value> or NUM\t<value> lines. WORDS contains one
# normalized copy of the query for all later keyword checks.
_god_resolve_harvest() {
  GOD_RESOLVE_QUERY="$1" LC_ALL=C awk 'BEGIN {
    text = ENVIRON["GOD_RESOLVE_QUERY"]
    sq = sprintf("%c", 39)
    dq = sprintf("%c", 34)

    normalized = tolower(text)
    gsub(/[^a-z0-9]+/, " ", normalized)
    print "WORDS\t" normalized

    # Pull quoted phrases out first so their contents are not re-split and
    # re-classified as bare words below.
    pattern = dq "[^" dq "]*" dq
    while (match(text, pattern)) {
      value = substr(text, RSTART + 1, RLENGTH - 2)
      if (value != "") print "NAME\t" value
      text = substr(text, 1, RSTART - 1) " " substr(text, RSTART + RLENGTH)
    }
    pattern = sq "[^" sq "]*" sq
    while (match(text, pattern)) {
      value = substr(text, RSTART + 1, RLENGTH - 2)
      if (value != "") print "NAME\t" value
      text = substr(text, 1, RSTART - 1) " " substr(text, RSTART + RLENGTH)
    }

    count = split(text, words, /[[:space:]]+/)
    for (i = 1; i <= count; i++) {
      word = words[i]
      gsub(/^[^[:alnum:]_-]+/, "", word)
      gsub(/[^[:alnum:]_-]+$/, "", word)
      if (word == "") continue
      if (word ~ /^-?[0-9]+$/) { print "NUM\t" word; continue }
      if (word ~ /_/ && word ~ /^[A-Za-z0-9_]+$/) { print "NAME\t" word; continue }
      if (word ~ /^[A-Z][A-Z0-9]*$/ && length(word) > 1) { print "NAME\t" word; continue }
    }
  }' </dev/null
}

# _god_resolve_query_has_word NORMALIZED_WORDS WORD
_god_resolve_query_has_word() {
  case "$1" in *" $2 "*) return 0 ;; esac
  return 1
}

# _god_resolve_is_placeholder VALUE
#
# True when VALUE still contains catalog placeholder syntax, e.g.
# <topic_name> or <topic_name>:<partition>. A concrete default like 20248 or
# localhost:9092 is not a placeholder and needs no prompt.
_god_resolve_is_placeholder() {
  case "$1" in
    *'<'*'>'*) return 0 ;;
    *) return 1 ;;
  esac
}

# _god_resolve_placeholder_spans TEXT
#
# Emits each distinct <placeholder> span in catalog text. Parameter metadata
# normally maps every span to a useful prompt, but this fallback prevents an
# incomplete record from ever reaching bash -c with shell metacharacters.
_god_resolve_placeholder_spans() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    {
      text = $0
      while (match(text, /<[^<>]+>/)) {
        span = substr(text, RSTART, RLENGTH)
        if (!seen[span]++) print span
        text = substr(text, RSTART + RLENGTH)
      }
    }
  '
}

# _god_resolve_placeholder_meaning SPAN
_god_resolve_placeholder_meaning() {
  local meaning

  meaning=$1
  meaning=${meaning#<}
  meaning=${meaning%>}
  meaning="${meaning//_/ }"
  printf 'Value for %s\n' "$meaning"
}

# _god_resolve_replace_span TEXT SEARCH REPLACEMENT
#
# Literal (non-regex) replacement of every occurrence of SEARCH in TEXT. This
# is for DISPLAY only, so a value is human-readable exactly where its catalog
# placeholder appeared; execute templates use the quote-aware helper below.
_god_resolve_replace_span() {
  local text search replacement prefix remaining output

  text=$1
  search=$2
  replacement=$3
  [ -n "$search" ] || { printf '%s\n' "$text"; return 0; }
  remaining=$text
  output=''
  while :; do
    case "$remaining" in
      *"$search"*) ;;
      *) break ;;
    esac
    prefix=${remaining%%"$search"*}
    remaining=${remaining#*"$search"}
    output="${output}${prefix}${replacement}"
  done
  printf '%s%s\n' "$output" "$remaining"
}

# _god_resolve_quote_context PREFIX
#
# Reports the shell quote context immediately after PREFIX: unquoted, single,
# or double. Catalog syntax is maintainer-authored, but user values must still
# be lifted safely when a placeholder is embedded inside a quoted URL or JSON
# body. The parser intentionally handles the POSIX quoting forms catalogs use;
# it never evaluates catalog text or user input.
_god_resolve_quote_context() {
  local prefix state index character escaped length

  prefix=$1
  state=unquoted
  escaped=0
  index=0
  length=${#prefix}
  while [ "$index" -lt "$length" ]; do
    character=${prefix:index:1}
    case "$state" in
      single)
        [ "$character" = "'" ] && state=unquoted
        ;;
      double)
        if [ "$escaped" = 1 ]; then
          escaped=0
        elif [ "$character" = '\\' ]; then
          escaped=1
        elif [ "$character" = '"' ]; then
          state=unquoted
        fi
        ;;
      *)
        if [ "$escaped" = 1 ]; then
          escaped=0
        elif [ "$character" = '\\' ]; then
          escaped=1
        elif [ "$character" = "'" ]; then
          state=single
        elif [ "$character" = '"' ]; then
          state=double
        fi
        ;;
    esac
    index=$((index + 1))
  done
  printf '%s\n' "$state"
}

# _god_resolve_replace_template_span TEXT SEARCH POSITION
#
# Replaces every placeholder span with a positional expansion while preserving
# the surrounding catalog syntax. Unquoted spans use a quoted expansion;
# single-quoted spans temporarily leave and re-enter single quotes; double
# quoted spans use ${N} inside the existing double quotes. In all forms the
# user-controlled value is an argument to bash -c, never parser input.
_god_resolve_replace_template_span() {
  local text search position prefix remaining output context replacement

  text=$1
  search=$2
  position=$3
  [ -n "$search" ] || { printf '%s\n' "$text"; return 0; }
  remaining=$text
  output=''
  while :; do
    case "$remaining" in
      *"$search"*) ;;
      *) break ;;
    esac
    prefix=${remaining%%"$search"*}
    context="$(_god_resolve_quote_context "$output$prefix")"
    case "$context" in
      single)
        # End the surrounding single quote, expand one positional argument
        # under double quotes, then resume the original single-quoted text.
        printf -v replacement '%s"${%s}"%s' "'" "$position" "'"
        ;;
      double)
        printf -v replacement '${%s}' "$position"
        ;;
      *)
        printf -v replacement '"${%s}"' "$position"
        ;;
    esac
    remaining=${remaining#*"$search"}
    output="${output}${prefix}${replacement}"
  done
  printf '%s%s\n' "$output" "$remaining"
}

# ---------------------------------------------------------------------------
# I/O: a config file read and, for placeholders nothing else resolved, one
# prompt per remaining value. Both degrade cleanly when unavailable.
# ---------------------------------------------------------------------------

# _god_resolve_config_file SERVICE
#
# Per-service defaults live beside discovery overrides, but no resolver code
# knows the service name. `path=` remains discovery-only and is ignored here.
_god_resolve_config_file() {
  local service

  service=$1
  case "$service" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
  esac
  case "${XDG_CONFIG_HOME:-}" in
    /*) printf '%s/bash-god/%s.conf\n' "${XDG_CONFIG_HOME%/}" "$service" ;;
    *)
      [ -n "${HOME:-}" ] || return 1
      printf '%s/.config/bash-god/%s.conf\n' "$HOME" "$service"
      ;;
  esac
}

# _god_resolve_config_value SERVICE PARAMETER CATALOG_DEFAULT
#
# Reads an optional non-secret default for the displayed parameter. The key is
# the parameter name without a leading `--`, normalized to lowercase. Secrets
# and `path` are deliberately never auto-loaded: path belongs exclusively to
# discovery and credentials must remain an explicit prompt/edit decision.
_god_resolve_config_value() {
  local service parameter fallback key file value

  service=$1
  parameter=$2
  fallback=$3
  key=${parameter#--}
  key="$(printf '%s' "$key" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  case "$key" in
    ''|*[!a-z0-9_-]*|path|*password*|*token*|*secret*|*credential*|*access-key*|*private-key*)
      printf '%s\n' "$fallback"
      return 0
      ;;
  esac

  file="$(_god_resolve_config_file "$service")" || { printf '%s\n' "$fallback"; return 0; }
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    value="$(LC_ALL=C awk -v wanted="$key" '
      /^[[:space:]]*[^#[:space:]][^=]*=/ {
        key = $0
        sub(/=.*/, "", key)
        sub(/^[[:space:]]+/, "", key)
        sub(/[[:space:]]+$/, "", key)
        if (tolower(key) != wanted) next
        value = $0
        sub(/^[^=]*=/, "", value)
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        print value
        exit
      }
    ' "$file" 2>/dev/null)"
  fi
  printf '%s\n' "${value:-$fallback}"
}

# _god_resolve_prompt_value MEANING EXAMPLE
#
# One line on /dev/tty, MEANING as the prompt and EXAMPLE as the default when
# the reply is empty. No /dev/tty (CI, cron, piped) returns EXAMPLE untouched.
_god_resolve_prompt_value() {
  local meaning example reply status

  meaning=$1
  example=$2
  { exec 3<>/dev/tty; } 2>/dev/null || { printf '%s\n' "$example"; return 0; }
  printf '%s [%s]: ' "$meaning" "$example" >&3
  IFS= read -r reply <&3
  status=$?
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  [ "$status" -eq 0 ] || return 130
  if [ -z "$reply" ] && _god_resolve_is_placeholder "$example"; then
    printf 'BASH_GOD: a value is required for %s.\n' "$meaning" >&3
    return 1
  fi
  printf '%s\n' "${reply:-$example}"
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

# _god_resolve_command SERVICE CATALOG GROUP ENTRY EXECUTION_PATH QUERY
#
# Prints:
#   DISPLAY\t<command with every value substituted in place, for the confirm screen>
#   TEMPLATE\t<same command with each bound value replaced by "$N", for execute.sh>
#   VALUE\t<value>              one per bound slot, in the same order as $N
#   PENDING\t<name>\t<span>\t<default>\t<meaning>
#                                      one per placeholder still unresolved
#
# Values that came from the user (harvested from the query or an optional
# per-service config default) are always lifted into VALUE/TEMPLATE, never
# baked into executable shell text. Unbound catalog defaults stay literal in
# both, since that text is maintainer-authored, the same trust level as @run.
_god_resolve_command() {
  local service catalog group entry execution_path query
  local mode run display template tag discover_probes discovered_tool execution_mode connection_kind connection_port target
  local name example meaning span query_words placeholder documented_span covered
  local -a param_names param_examples param_spans param_meanings param_keyword_classes param_bound
  local -a name_pool num_pool values
  local pool_index bound value_count i

  service=$1
  catalog=$2
  group=$3
  entry=$4
  execution_path=$5
  query=$6

  mode=''
  run=''
  param_names=()
  param_examples=()
  param_spans=()
  param_meanings=()
  param_keyword_classes=()
  param_bound=()
  while IFS="$(printf '\t')" read -r tag a b c d; do
    case "$tag" in
      MODE) mode=$a ;;
      RUN) run=$a ;;
      PARAM)
        param_names+=("$a")
        param_examples+=("$b")
        param_spans+=('')
        param_meanings+=("$c")
        param_keyword_classes+=("$d")
        ;;
    esac
  done < <(_god_catalog_command_export "$catalog" "$group" "$entry")
  [ -n "$run" ] || return 1

  execution_mode="$(_god_catalog_execution_mode "$catalog")"
  # A path has meaning only for a catalog that owns a resolved discovery
  # directory. PATH catalogs deliberately execute their spelling through the
  # caller's PATH, and display-only/LOCAL rows must stay literal even if an
  # internal caller accidentally supplies a directory.
  if [ "$mode" = LOCAL ] || [ "$execution_mode" != DISCOVER ]; then
    execution_path=''
  fi
  discover_probes=''
  discovered_tool=''
  if [ -n "$execution_path" ] && [ "$execution_mode" = DISCOVER ]; then
    discover_probes="$(_god_catalog_discover_probes "$catalog")"
    if [ -n "$(type -t _god_discover_tool 2>/dev/null)" ]; then
      discovered_tool="$(_god_discover_tool "$service" 2>/dev/null)"
    fi
    [ -n "$discovered_tool" ] || discovered_tool="$(_god_catalog_discover_value "$catalog" probe)"
  fi
  run="$(_god_resolve_rewrite_paths "$run" "$execution_path" "$discover_probes" "$discovered_tool")"
  connection_kind="$(_god_catalog_connection_kind "$catalog")"
  if [ "$mode" != LOCAL ] && [ "$connection_kind" = ENDPOINT ] && \
     [ -n "$(type -t _god_discover_target 2>/dev/null)" ]; then
    connection_port="$(_god_catalog_connection_port "$catalog")"
    target="$(_god_discover_target "$service" 2>/dev/null)"
    run="$(_god_resolve_rewrite_endpoint "$run" "$target" "$connection_port")"
  fi

  # Catalogs express a slot either as its placeholder example (the original
  # Kafka convention: `topic | <topic_name>`) or as a placeholder name with a
  # useful concrete default (for example: `<index_name> | orders-v1`).  Map
  # each parameter to the literal span actually present in @run before any
  # binding. Parameters that only document a fixed switch have no span and
  # never create a misleading positional value or prompt.
  i=0
  while [ "$i" -lt "${#param_names[@]}" ]; do
    name="${param_names[$i]}"
    example="${param_examples[$i]}"
    span=''
    if _god_resolve_is_placeholder "$name" && [[ "$run" == *"$name"* ]]; then
      span=$name
    elif [[ "$run" == *"$example"* ]]; then
      span=$example
    fi
    param_spans[$i]=$span
    i=$((i + 1))
  done

  name_pool=()
  num_pool=()
  query_words=' '
  while IFS="$(printf '\t')" read -r tag value; do
    case "$tag" in
      WORDS) query_words=" $value " ;;
      NAME) name_pool+=("$value") ;;
      NUM) num_pool+=("$value") ;;
    esac
  done < <(_god_resolve_harvest "$query")

  display=$run
  template=$run
  values=()
  value_count=${#param_names[@]}

  # A slot only competes for a harvested token when the query actually says
  # its keyword (so "offset -1 ... topic" binds --offset, not the unrelated
  # --partition slot sitting right next to it). Among slots the query does
  # name, a token binds only when exactly one eligible slot and exactly one
  # candidate token of that class both exist; anything else is left for the
  # placeholder pass rather than guessed.
  local name_eligible_count=0 num_eligible_count=0 keyword_class

  i=0
  while [ "$i" -lt "$value_count" ]; do
    keyword_class="${param_keyword_classes[$i]}"
    if [ -n "$keyword_class" ] && _god_resolve_query_has_word "$query_words" "${keyword_class%%:*}"; then
      case "$keyword_class" in
        *:name) name_eligible_count=$((name_eligible_count + 1)) ;;
        *:num) num_eligible_count=$((num_eligible_count + 1)) ;;
      esac
    fi
    i=$((i + 1))
  done

  i=0
  while [ "$i" -lt "$value_count" ]; do
    name="${param_names[$i]}"
    example="${param_examples[$i]}"
    span="${param_spans[$i]}"
    meaning="${param_meanings[$i]}"
    bound=''

    if [ -n "$span" ] && ! _god_resolve_is_placeholder "$span"; then
      bound="$(_god_resolve_config_value "$service" "$name" "$span")"
      [ "$bound" = "$span" ] && bound=''
    fi
    if [ -n "$span" ] && [ -z "$bound" ]; then
      keyword_class="${param_keyword_classes[$i]}"
      if [ -n "$keyword_class" ] && _god_resolve_query_has_word "$query_words" "${keyword_class%%:*}"; then
        case "$keyword_class" in
          *:name)
            [ "$name_eligible_count" -eq 1 ] && [ "${#name_pool[@]}" -eq 1 ] && bound="${name_pool[0]}"
            ;;
          *:num)
            [ "$num_eligible_count" -eq 1 ] && [ "${#num_pool[@]}" -eq 1 ] && bound="${num_pool[0]}"
            ;;
        esac
      fi
    fi

    if [ -n "$bound" ]; then
      values+=("$bound")
      pool_index=${#values[@]}
      display="$(_god_resolve_replace_span "$display" "$span" "$bound")"
      template="$(_god_resolve_replace_template_span "$template" "$span" "$pool_index")"
      param_bound[$i]=1
    fi
    i=$((i + 1))
  done

  printf 'DISPLAY\t%s\n' "$display"
  printf 'TEMPLATE\t%s\n' "$template"
  if [ "${#values[@]}" -gt 0 ]; then
    for value in "${values[@]}"; do
      printf 'VALUE\t%s\n' "$value"
    done
  fi

  i=0
  while [ "$i" -lt "$value_count" ]; do
    name="${param_names[$i]}"
    example="${param_examples[$i]}"
    span="${param_spans[$i]}"
    if [ -n "$span" ] && _god_resolve_is_placeholder "$span" && [ "${param_bound[$i]:-0}" != 1 ]; then
      printf 'PENDING\t%s\t%s\t%s\t%s\n' "$name" "$span" "$example" "${param_meanings[$i]}"
    fi
    i=$((i + 1))
  done

  # Parameter metadata can name a flag (for example, -n) instead of repeating
  # the <namespace> span it documents. Prompt every span no declared parameter
  # already owns, so incomplete catalog metadata cannot leak raw placeholder
  # syntax to bash -c. A declared span may contain a placeholder inside a
  # larger value, such as User:<principal>.
  while IFS= read -r placeholder; do
    [ -n "$placeholder" ] || continue
    covered=0
    i=0
    while [ "$i" -lt "$value_count" ]; do
      documented_span="${param_spans[$i]}"
      case "$documented_span" in
        *"$placeholder"*) covered=1; break ;;
      esac
      i=$((i + 1))
    done
    [ "$covered" = 1 ] && continue
    printf 'PENDING\t%s\t%s\t%s\t%s\n' \
      "$placeholder" "$placeholder" "$placeholder" \
      "$(_god_resolve_placeholder_meaning "$placeholder")"
  done < <(_god_resolve_placeholder_spans "$run")
}

# _god_resolve_command_interactive SERVICE CATALOG GROUP ENTRY EXECUTION_PATH QUERY
#
# Runs _god_resolve_command, then prompts once per remaining PENDING
# placeholder (skipped with no /dev/tty, leaving the placeholder literal).
# Same DISPLAY/TEMPLATE/VALUE output shape, with no PENDING lines left when a
# terminal was available to fill them.
_god_resolve_command_interactive() {
  local service catalog group entry execution_path query
  local tag a b c d display template value_count answer pool_index resolved prompt_status

  service=$1
  catalog=$2
  group=$3
  entry=$4
  execution_path=$5
  query=$6

  display=''
  template=''
  local -a values pending_names pending_spans pending_examples pending_meanings
  values=()
  pending_names=()
  pending_spans=()
  pending_examples=()
  pending_meanings=()

  resolved="$(_god_resolve_command "$service" "$catalog" "$group" "$entry" "$execution_path" "$query")" || return $?
  while IFS="$(printf '\t')" read -r tag a b c d; do
    case "$tag" in
      DISPLAY) display=$a ;;
      TEMPLATE) template=$a ;;
      VALUE) values+=("$a") ;;
      PENDING)
        pending_names+=("$a")
        pending_spans+=("$b")
        pending_examples+=("$c")
        pending_meanings+=("$d")
        ;;
    esac
  done <<< "$resolved"

  value_count=${#pending_names[@]}
  i=0
  while [ "$i" -lt "$value_count" ]; do
    answer="$(_god_resolve_prompt_value "${pending_meanings[$i]}" "${pending_examples[$i]}")"
    prompt_status=$?
    [ "$prompt_status" -eq 0 ] || return "$prompt_status"
    if [ "$answer" != "${pending_examples[$i]}" ]; then
      values+=("$answer")
      pool_index=${#values[@]}
      display="$(_god_resolve_replace_span "$display" "${pending_spans[$i]}" "$answer")"
      template="$(_god_resolve_replace_template_span "$template" "${pending_spans[$i]}" "$pool_index")"
    fi
    i=$((i + 1))
  done

  printf 'DISPLAY\t%s\n' "$display"
  printf 'TEMPLATE\t%s\n' "$template"
  if [ "${#values[@]}" -gt 0 ]; then
    for answer in "${values[@]}"; do
      printf 'VALUE\t%s\n' "$answer"
    done
  fi
}
