#!/usr/bin/env bash

# BASH_GOD reviewed interaction coordination. Search supplies ranked records;
# this module prepares lazy reviewed-command models, owns picker callbacks,
# and hands one explicit model or edited command to the execution boundary.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_GOD_INTERACTION_NO_CANDIDATE_STATUS=126

# _god_interaction_available SORTED_RESULTS TAB
#
# Returns true only when the terminal can offer the shared rich picker. Whether
# an individual result belongs in that executable-only candidate list is a
# separate R12 policy decision made below. This keeps broad static search
# knowledge complete when a mixed result set contains ineligible rows.
_god_interaction_available() {
  # Retain the arguments in the public signature so old callers do not need a
  # coordinated change; candidate filtering deliberately consumes them later.
  : "${1:-}" "${2:-}"
  # The coordinator and reviewed-model cache still use Bash arrays; a sourced
  # zsh remains on the safe static result table until that boundary is portable.
  [ -n "${BASH_VERSION:-}" ] || return 1
  _god_stdout_is_terminal || return 1
  [ "${TERM:-}" != dumb ] || return 1
  [ -n "$(type -t _god_catalog_execution_mode 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_tui_select 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_tui_available 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_resolve_reviewed_model 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_execute_reviewed_model 2>/dev/null)" ] || return 1
  _god_tui_available || return 1
  return 0
}

# _god_interaction_candidate_state SERVICE CATALOG GROUP ENTRY COMPATIBILITY_KIND COMPATIBILITY_LABEL
#
# Emits a small, inert record describing whether one ranked search row may
# enter the executable picker. Schema 0 retains its current transitional
# behavior; Schema 1 is strict: only a freshly eligible result enters. The
# reason is intentionally retained for the aggregate static fallback, never
# rendered as a disabled picker row.
_god_interaction_candidate_state() {
  local service catalog group entry compatibility_kind compatibility_label schema assessment status
  local tab tag value candidate_state candidate_reason

  service=$1
  catalog=$2
  group=$3
  entry=$4
  compatibility_kind=${5:-}
  compatibility_label=${6:-}
  schema=0
  if [ -n "$(type -t _god_catalog_environment_schema 2>/dev/null)" ]; then
    schema="$(_god_catalog_environment_schema "$catalog" 2>/dev/null)"
  fi
  [ "$schema" = 1 ] || schema=0

  candidate_state=runnable
  candidate_reason=''
  if [ "$compatibility_kind" = blocked ]; then
    candidate_state=blocked
    candidate_reason="${compatibility_label:-command compatibility is unsupported}"
  elif [ "$schema" = 1 ]; then
    if [ -z "$(type -t _god_eligibility_assess 2>/dev/null)" ]; then
      candidate_state=blocked
      candidate_reason='environment eligibility cannot be verified by this installation'
    else
      assessment="$(_god_eligibility_assess "$service" "$catalog" "$group" "$entry" 2>/dev/null)"
      status=$?
      if [ "$status" -ne 0 ]; then
        candidate_state=blocked
        candidate_reason='environment eligibility could not be verified'
      else
        tab="$(printf '\t')"
        while IFS="$tab" read -r tag value; do
          case "$tag" in
            ELIGIBILITY) candidate_state=$value ;;
            REASON)
              candidate_reason="${candidate_reason:+$candidate_reason; }$value"
              ;;
          esac
        done <<< "$assessment"
        case "$candidate_state" in
          eligible) candidate_state=runnable; candidate_reason='' ;;
          ineligible|unknown) candidate_state=blocked ;;
          *)
            candidate_state=blocked
            candidate_reason='environment eligibility returned an invalid result'
            ;;
        esac
        [ -n "$candidate_reason" ] || [ "$candidate_state" = runnable ] || \
          candidate_reason='environment requirements are not verified'
      fi
    fi
  fi

  printf 'STATE\t%s\n' "$candidate_state"
  printf 'SCHEMA\t%s\n' "$schema"
  [ -z "$candidate_reason" ] || printf 'REASON\t%s\n' "$candidate_reason"
}

# _god_interaction_requires_service_directory CATALOG GROUP ENTRY MODE
#
# Non-LOCAL discovery records retain the existing resolved-directory contract.
# A LOCAL Schema-1 record is normally a host PATH command, but an explicit
# service: tool requirement means its exact executable still belongs in the
# resolved service directory. This is catalog metadata, not a service rule.
_god_interaction_requires_service_directory() {
  local catalog group entry mode

  catalog=$1
  group=$2
  entry=$3
  mode=${4:-}
  [ "$mode" != LOCAL ] && return 0
  [ -n "$(type -t _god_catalog_command_service_tool 2>/dev/null)" ] || return 1
  [ -n "$(_god_catalog_command_service_tool "$catalog" "$group" "$entry" 2>/dev/null)" ]
}

# _god_interaction_context_fingerprint SERVICE CATALOG GROUP ENTRY MODE
#
# Captures the reviewed context that can change while the picker is open. It
# reads only bounded cache state and filesystem freshness; it never executes a
# catalog command or probes a remote target. A different value at launch time
# forces the operator to review a fresh search result.
_god_interaction_context_fingerprint() {
  local service catalog group entry mode execution_mode execution_path discover_tool connection_kind target version
  local requires_service_directory declared_service_tool

  service=$1
  catalog=$2
  group=$3
  entry=$4
  mode=${5:-}
  execution_mode="$(_god_catalog_execution_mode "$catalog" 2>/dev/null)"
  execution_path=''
  discover_tool=''
  target=''
  version=''
  connection_kind="$(_god_catalog_connection_kind "$catalog" 2>/dev/null)"
  requires_service_directory=0
  if _god_interaction_requires_service_directory "$catalog" "$group" "$entry" "$mode"; then
    requires_service_directory=1
  fi
  declared_service_tool=''
  if [ "$requires_service_directory" = 1 ] && [ -n "$(type -t _god_catalog_command_service_tool 2>/dev/null)" ]; then
    declared_service_tool="$(_god_catalog_command_service_tool "$catalog" "$group" "$entry" 2>/dev/null)"
  fi

  case "$execution_mode" in
    DISCOVER)
      if [ "$requires_service_directory" != 1 ]; then
        # LOCAL host-tool rows do not depend on the service client's resolved
        # directory. Their explicit local requirements are assessed separately.
        execution_path=''
        discover_tool=''
        version=''
      else
      [ -n "$(type -t _god_discover_is_stale 2>/dev/null)" ] || return 1
      [ -n "$(type -t _god_discover_path 2>/dev/null)" ] || return 1
      _god_discover_is_stale "$service" "$catalog" && return 1
      execution_path="$(_god_discover_path "$service" 2>/dev/null)"
      [ -n "$execution_path" ] && [ -d "$execution_path" ] || return 1
      if [ -n "$declared_service_tool" ]; then
        discover_tool=$declared_service_tool
      elif [ -n "$(type -t _god_discover_tool 2>/dev/null)" ]; then
        discover_tool="$(_god_discover_tool "$service" 2>/dev/null)"
      fi
      [ -n "$discover_tool" ] || discover_tool="$(_god_catalog_discover_value "$catalog" probe)"
      [ -n "$discover_tool" ] || return 1
      [ -x "$execution_path/$discover_tool" ] || return 1
      if [ -n "$(type -t _god_discover_version 2>/dev/null)" ]; then
        version="$(_god_discover_version "$service" 2>/dev/null)"
      fi
      fi
      ;;
    PATH)
      # PATH catalogs have no product directory or service-version cache.
      ;;
    *) return 1 ;;
  esac

  if [ "$connection_kind" = ENDPOINT ] && [ -n "$(type -t _god_discover_target 2>/dev/null)" ]; then
    target="$(_god_discover_target "$service" 2>/dev/null)"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$execution_mode" "$execution_path" "$discover_tool" "$connection_kind" "$target" "$version"
}

# _god_interaction_recheck_selected STORAGE_INDEX
#
# Rechecks a chosen immutable candidate immediately before any edit, prompt,
# or child launch. A schema-one record must still be eligible; any changed
# discovery path, selected client, Target, or cached version also stops the
# launch rather than silently changing the reviewed command.
_god_interaction_recheck_selected() {
  local storage_index service catalog group entry mode expected actual schema state_payload tab tag value state reason

  storage_index=$1
  service="${rich_services[$storage_index]:-}"
  catalog="${rich_catalogs[$storage_index]:-}"
  group="${rich_groups[$storage_index]:-}"
  entry="${rich_entries[$storage_index]:-}"
  mode="${rich_modes[$storage_index]:-}"
  expected="${rich_fingerprints[$storage_index]:-}"
  schema="${rich_schemas[$storage_index]:-0}"
  [ -n "$service" ] && [ -n "$catalog" ] && [ -n "$group" ] && [ -n "$entry" ] && [ -n "$expected" ] || return 2

  actual="$(_god_interaction_context_fingerprint "$service" "$catalog" "$group" "$entry" "$mode" 2>/dev/null)" || actual=''
  if [ -z "$actual" ] || [ "$actual" != "$expected" ]; then
    printf 'BASH_GOD: selected command is no longer executable because its reviewed context changed. Run the search again.\n' >&2
    return 2
  fi
  [ "$schema" = 1 ] || return 0

  state_payload="$(_god_interaction_candidate_state "$service" "$catalog" "$group" "$entry" '' '')" || return 2
  tab="$(printf '\t')"
  state=''
  reason=''
  while IFS="$tab" read -r tag value; do
    case "$tag" in
      STATE) state=$value ;;
      REASON) reason="${reason:+$reason; }$value" ;;
    esac
  done <<< "$state_payload"
  if [ "$state" != runnable ]; then
    printf 'BASH_GOD: selected command is no longer executable%s%s. Run the search again.\n' \
      "${reason:+: }" "$reason" >&2
    return 2
  fi
}


# _god_interaction_detail_provider SELECTED
#
# Called directly by the shared TUI adapter while
# _god_interaction_offer_search_results is still on the stack. The callback and
# its dynamically scoped cache are both owned here; menu.sh sees only display
# text, and search.sh sees only the interaction entry point.
_god_interaction_detail_provider() {
  local selected storage_index service group entry catalog execution_path model model_tag model_value display

  selected=$1
  if [ -n "${BASH_VERSION:-}" ]; then
    storage_index=$((selected - 1))
  else
    storage_index=$selected
  fi

  model="${models[$storage_index]:-}"
  if [ -z "$model" ]; then
    service="${rich_services[$storage_index]:-}"
    group="${rich_groups[$storage_index]:-}"
    entry="${rich_entries[$storage_index]:-}"
    catalog="${rich_catalogs[$storage_index]:-}"
    execution_path="${rich_execution_paths[$storage_index]:-}"
    [ -n "$service" ] && [ -n "$group" ] && [ -n "$entry" ] && [ -n "$catalog" ] || return 1
    model="$(_god_resolve_reviewed_model \
      "$service" "$catalog" "$group" "$entry" "$execution_path" "$query" \
      "${rich_eligibilities[$storage_index]:-blocked}" "${rich_reasons[$storage_index]:-unavailable}")" || return 1
    models[$storage_index]=$model
  fi

  display=''
  while IFS="$tab" read -r model_tag model_value; do
    [ "$model_tag" = DISPLAY ] && { display=$model_value; break; }
  done <<< "$model"
  [ -n "$display" ] || return 1
  _god_menu_provider_detail=$display
}

# _god_interaction_detail_cached SELECTED
#
# Kept separate from the provider so navigation can skip the transient
# resolving frame for a command that the operator has already visited.
_god_interaction_detail_cached() {
  local selected storage_index

  selected=$1
  if [ -n "${BASH_VERSION:-}" ]; then
    storage_index=$((selected - 1))
  else
    storage_index=$selected
  fi
  [ -n "${models[$storage_index]:-}" ]
}

# _god_interaction_discovered_tool_missing EXECUTION_PATH RUN DISCOVER_PROBES SELECTED_TOOL
#
# A catalog may declare several interchangeable discovery tools, such as a
# modern client and an explicitly supported legacy fallback. Only a command
# whose first word is one of those declared tools is tied to the resolved
# directory. The discovered member is the family runner for every such row,
# so a modern spelling can safely use the catalog-declared legacy fallback.
# Return the missing selected runner only when the cache/path is inconsistent.
_god_interaction_discovered_tool_missing() {
  local execution_path run discover_probes selected_tool first probe

  execution_path=$1
  run=$2
  discover_probes=$3
  selected_tool=${4:-}
  [ -n "$execution_path" ] || return 1
  first="${run#"${run%%[![:space:]]*}"}"
  first="${first%%[[:space:]]*}"
  [ -n "$first" ] || return 1

  while IFS= read -r probe; do
    [ -n "$probe" ] || continue
    [ "$first" = "$probe" ] || continue
    [ -n "$selected_tool" ] || selected_tool=$probe
    [ -x "$execution_path/$selected_tool" ] || { printf '%s\n' "$selected_tool"; return 0; }
    return 1
  done <<< "$discover_probes"
  return 1
}

# _god_interaction_select ROWS INITIAL HEADER_TITLE HEADER_SUBTITLE
#
# Adapts the BGTUI/1 helper result into explicit shell-owned result fields.
# UI text stays on /dev/tty. A successful result sets one ACTION
# (RUN|EDIT|CANCEL), a zero-based INDEX for RUN/EDIT, and the exact reviewed
# model. Cancellation is an action, while terminal or provider failures remain
# non-zero statuses. Keep these fields out of command substitution: terminal
# helper cleanup and native editing must retain the caller's real TTY context.
_god_interaction_select() {
  local menu_rows initial_selected header_title header_subtitle picker_status selected_index storage_index model

  menu_rows=$1
  initial_selected=$2
  header_title=$3
  header_subtitle=$4

  _god_tui_select "$menu_rows" "$initial_selected" "$header_title" "$header_subtitle" \
    _god_interaction_detail_provider
  picker_status=$?
  [ "$picker_status" -eq 0 ] || return "$picker_status"

  _god_interaction_result_version=1
  _god_interaction_result_action=CANCEL
  _god_interaction_result_index=-1
  _god_interaction_result_model=''
  if [ "${_god_tui_action:-CANCEL}" = CANCEL ]; then
    return 0
  fi

  selected_index=$((_god_tui_index + 1))
  _god_interaction_detail_provider "$selected_index" || return 3
  if [ -n "${BASH_VERSION:-}" ]; then
    storage_index=$_god_tui_index
  else
    storage_index=$selected_index
  fi
  model="${models[$storage_index]:-}"
  [ -n "$model" ] || return 3
  _god_interaction_result_action=$_god_tui_action
  _god_interaction_result_index=$_god_tui_index
  _god_interaction_result_model=$model
}

# _god_interaction_offer_search_results SORTED_RESULTS TAB QUERY [HEADER_TITLE] [HEADER_SUBTITLE]
#
# The caller has already established that the terminal can host a picker.
# Build a clean executable-only candidate list: titles in the list and the
# selected, complete command in the detail panel. Broad static search remains
# responsible for showing rows that are ineligible, unknown, stale, or
# otherwise unavailable here. Details are resolved only when highlighted and
# are then cached; there is intentionally no second compact list or legacy
# command picker underneath it.
_god_interaction_offer_search_results() {
  local sorted_results tab query header_title header_subtitle menu_rows picker_status row_fields separator
  local line svc grp ent title risk native_run intent since schema mode remaining_run native_tool missing_probe compatibility_kind compatibility_label service catalog execution_path
  local previous_service previous_catalog previous_execution_path previous_execution_mode previous_discover_probes previous_discover_tool previous_unavailable_reason
  local model model_tag model_value pending storage_index row_index initial_selected interactive_model original edit_status
  local candidate_payload candidate_state candidate_schema candidate_reason context_fingerprint first_exclusion_reason needs_service_directory
  local candidate_count candidate_index candidate_other candidate_best candidate_since candidate_best_since candidate_compare candidate_tied
  local result_tag result_value result_version action edited_command
  local -a models rich_services rich_groups rich_entries rich_catalogs rich_execution_paths rich_eligibilities rich_reasons rich_schemas rich_fingerprints rich_modes
  local -a candidate_services candidate_groups candidate_entries candidate_catalogs candidate_titles candidate_risks candidate_labels candidate_paths candidate_schemas candidate_fingerprints candidate_modes candidate_intents candidate_sinces candidate_selected candidate_processed

  sorted_results="$1"
  tab="$2"
  query="$3"
  header_title="${4:-SEARCH RESULTS}"
  header_subtitle="${5:-}"

  _god_stdout_is_terminal || return 1
  [ -n "$(type -t _god_tui_select 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_resolve_reviewed_model 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_execute_reviewed_model 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_menu_style_init 2>/dev/null)" ] && _god_menu_style_init

  menu_rows=''
  separator="$(printf '\034')"
  models=()
  rich_services=()
  rich_groups=()
  rich_entries=()
  rich_catalogs=()
  rich_execution_paths=()
  rich_eligibilities=()
  rich_reasons=()
  rich_schemas=()
  rich_fingerprints=()
  rich_modes=()
  candidate_services=()
  candidate_groups=()
  candidate_entries=()
  candidate_catalogs=()
  candidate_titles=()
  candidate_risks=()
  candidate_labels=()
  candidate_paths=()
  candidate_schemas=()
  candidate_fingerprints=()
  candidate_modes=()
  candidate_intents=()
  candidate_sinces=()
  candidate_selected=()
  candidate_processed=()
  previous_service=''
  previous_catalog=''
  previous_execution_path=''
  previous_execution_mode=''
  previous_discover_probes=''
  previous_discover_tool=''
  previous_unavailable_reason=''
  row_index=0
  initial_selected=1
  first_exclusion_reason=''
  _god_interaction_no_candidate_reason=''
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    row_fields="$(printf '%s' "$line" | LC_ALL=C awk -F "$tab" -v separator="$separator" '{ printf "%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s", $3, separator, $4, separator, $5, separator, $6, separator, $8, separator, $7, separator, $11, separator, $9, separator, $12, separator, $13, separator, $14, separator, $15 }')"
    IFS="$separator" read -r svc grp ent title risk native_run intent since schema mode compatibility_kind compatibility_label <<< "$row_fields"
    [ -n "$svc" ] || continue

    if [ "$svc" != "$previous_service" ]; then
      previous_catalog="$(_god_catalog_for "$svc" 2>/dev/null)" || return 1
      previous_execution_mode="$(_god_catalog_execution_mode "$previous_catalog")"
      previous_execution_path=''
      previous_discover_probes=''
      previous_discover_tool=''
      previous_unavailable_reason=''
      case "$previous_execution_mode" in
        DISCOVER)
          previous_discover_probes="$(_god_catalog_discover_probes "$previous_catalog")"
          if [ -n "$(type -t _god_discover_tool 2>/dev/null)" ]; then
            previous_discover_tool="$(_god_discover_tool "$svc" 2>/dev/null)"
          fi
          [ -n "$previous_discover_tool" ] || previous_discover_tool="$(_god_catalog_discover_value "$previous_catalog" probe)"
          if [ -z "$(type -t _god_discover_is_stale 2>/dev/null)" ] || \
             [ -z "$(type -t _god_discover_path 2>/dev/null)" ]; then
            previous_unavailable_reason='client discovery is unavailable in this installation'
          elif _god_discover_is_stale "$svc" "$previous_catalog"; then
            previous_unavailable_reason="${svc} client discovery is stale; run god ${svc} --resync"
          else
            previous_execution_path="$(_god_discover_path "$svc" 2>/dev/null)"
            [ -n "$previous_execution_path" ] && [ -d "$previous_execution_path" ] || \
              previous_unavailable_reason="${svc} client is not resolved; run god ${svc} --resync"
          fi
          ;;
        PATH)
          # PATH catalogs deliberately keep their command spelling unchanged.
          ;;
        *) previous_unavailable_reason='this catalog does not declare an executable mode' ;;
      esac
      previous_service=$svc
    fi
    [ -n "$previous_catalog" ] || return 1

    # Schema-0 retains its existing discovery preflight. Schema-1 derives
    # availability from its exact requirements below, so a local Database Tool
    # can remain independent of an absent shell client while a service: row
    # still fails closed through eligibility.
    if [ "$schema" != 1 ] && [ "$mode" != LOCAL ] && [ -n "$previous_unavailable_reason" ]; then
      compatibility_kind=blocked
      compatibility_label=$previous_unavailable_reason
    fi

    # Version metadata is the human explanation, but a resolved discovery
    # directory is still the final authority. Check generic leading ./tools
    # once before the picker starts; navigation remains filesystem-free. PATH
    # services intentionally skip this because no one directory owns them.
    if [ "$schema" != 1 ] && [ "$previous_execution_mode" = DISCOVER ] && \
       [ "$mode" != LOCAL ] && [ "$compatibility_kind" != blocked ]; then
      missing_probe="$(_god_interaction_discovered_tool_missing "$previous_execution_path" "$native_run" "$previous_discover_probes" "$previous_discover_tool")" || missing_probe=''
      if [ -n "$missing_probe" ]; then
        compatibility_kind=blocked
        compatibility_label="$missing_probe is not installed"
      else
        remaining_run=$native_run
        while [[ "$remaining_run" =~ (^|[[:space:]\|\;\&\(])\.\/([A-Za-z0-9._-]+) ]]; do
          native_tool=${BASH_REMATCH[2]}
          if [ ! -x "$previous_execution_path/$native_tool" ]; then
            compatibility_kind=blocked
            compatibility_label="$native_tool is not installed"
            break
          fi
          remaining_run=${remaining_run#*"./$native_tool"}
        done
      fi
    fi

    candidate_payload="$(_god_interaction_candidate_state \
      "$svc" "$previous_catalog" "$grp" "$ent" "$compatibility_kind" "$compatibility_label")" || return 1
    candidate_state=''
    candidate_schema=0
    candidate_reason=''
    while IFS="$tab" read -r result_tag result_value; do
      case "$result_tag" in
        STATE) candidate_state=$result_value ;;
        SCHEMA) candidate_schema=$result_value ;;
        REASON) candidate_reason="${candidate_reason:+$candidate_reason; }$result_value" ;;
      esac
    done <<< "$candidate_payload"
    if [ "$candidate_state" != runnable ]; then
      [ -n "$first_exclusion_reason" ] || first_exclusion_reason="$candidate_reason"
      continue
    fi

    needs_service_directory=0
    if _god_interaction_requires_service_directory "$previous_catalog" "$grp" "$ent" "$mode"; then
      needs_service_directory=1
    fi
    if [ "$needs_service_directory" = 1 ]; then
      if [ -n "$previous_unavailable_reason" ] || [ -z "$previous_execution_path" ]; then
        [ -n "$first_exclusion_reason" ] || \
          first_exclusion_reason="${previous_unavailable_reason:-the reviewed service directory is unavailable}"
        continue
      fi
      execution_path=$previous_execution_path
    else
      execution_path=''
    fi
    context_fingerprint="$(_god_interaction_context_fingerprint \
      "$svc" "$previous_catalog" "$grp" "$ent" "$mode" 2>/dev/null)" || context_fingerprint=''
    if [ -z "$context_fingerprint" ]; then
      [ -n "$first_exclusion_reason" ] || \
        first_exclusion_reason='the reviewed execution context is unavailable'
      continue
    fi

    candidate_services+=("$svc")
    candidate_groups+=("$grp")
    candidate_entries+=("$ent")
    candidate_catalogs+=("$previous_catalog")
    candidate_titles+=("$title")
    candidate_risks+=("$risk")
    candidate_labels+=("$compatibility_label")
    candidate_paths+=("$execution_path")
    candidate_schemas+=("$candidate_schema")
    candidate_fingerprints+=("$context_fingerprint")
    candidate_modes+=("$mode")
    candidate_intents+=("$intent")
    candidate_sinces+=("$since")
  done <<< "$sorted_results"
  candidate_count=${#candidate_services[@]}
  if [ "$candidate_count" -eq 0 ]; then
    _god_interaction_no_candidate_reason="${first_exclusion_reason:-environment requirements are not verified}"
    return "$_GOD_INTERACTION_NO_CANDIDATE_STATUS"
  fi

  # search.sh retains Schema-1 intent families until each member has been
  # evaluated here. Select the newest eligible member only after that filter;
  # tied reviewed variants are deliberately unavailable rather than chosen by
  # incidental catalog order.
  candidate_index=0
  while [ "$candidate_index" -lt "$candidate_count" ]; do
    candidate_selected[$candidate_index]=1
    candidate_processed[$candidate_index]=0
    candidate_index=$((candidate_index + 1))
  done
  candidate_index=0
  while [ "$candidate_index" -lt "$candidate_count" ]; do
    if [ "${candidate_schemas[$candidate_index]}" != 1 ] || \
       [ -z "${candidate_intents[$candidate_index]}" ] || \
       [ "${candidate_processed[$candidate_index]}" = 1 ]; then
      candidate_index=$((candidate_index + 1))
      continue
    fi
    candidate_processed[$candidate_index]=1
    candidate_best=$candidate_index
    candidate_best_since="${candidate_sinces[$candidate_index]:-0}"
    candidate_tied=0
    candidate_other=$((candidate_index + 1))
    while [ "$candidate_other" -lt "$candidate_count" ]; do
      if [ "${candidate_schemas[$candidate_other]}" = 1 ] && \
         [ "${candidate_services[$candidate_other]}" = "${candidate_services[$candidate_index]}" ] && \
         [ "${candidate_intents[$candidate_other]}" = "${candidate_intents[$candidate_index]}" ]; then
        candidate_processed[$candidate_other]=1
        candidate_since="${candidate_sinces[$candidate_other]:-0}"
        candidate_compare="$(_god_version_compare "$candidate_since" "$candidate_best_since")"
        case "$candidate_compare" in
          1)
            candidate_best=$candidate_other
            candidate_best_since=$candidate_since
            candidate_tied=0
            ;;
          0) candidate_tied=1 ;;
        esac
      fi
      candidate_other=$((candidate_other + 1))
    done

    candidate_other=$candidate_index
    while [ "$candidate_other" -lt "$candidate_count" ]; do
      if [ "${candidate_schemas[$candidate_other]}" = 1 ] && \
         [ "${candidate_services[$candidate_other]}" = "${candidate_services[$candidate_index]}" ] && \
         [ "${candidate_intents[$candidate_other]}" = "${candidate_intents[$candidate_index]}" ]; then
        candidate_selected[$candidate_other]=0
      fi
      candidate_other=$((candidate_other + 1))
    done
    if [ "$candidate_tied" = 1 ]; then
      [ -n "$first_exclusion_reason" ] || \
        first_exclusion_reason='several equally compatible reviewed variants are eligible'
    else
      candidate_selected[$candidate_best]=1
    fi
    candidate_index=$((candidate_index + 1))
  done

  row_index=0
  candidate_index=0
  while [ "$candidate_index" -lt "$candidate_count" ]; do
    if [ "${candidate_selected[$candidate_index]}" = 1 ]; then
      row_index=$((row_index + 1))
      menu_rows="${menu_rows:+$menu_rows
}$(printf '%s\t%s\t%s\t%s\t%s' \
        "${candidate_titles[$candidate_index]}" \
        "${candidate_labels[$candidate_index]}" \
        "${candidate_risks[$candidate_index]}" 1 '')"
      rich_services+=("${candidate_services[$candidate_index]}")
      rich_groups+=("${candidate_groups[$candidate_index]}")
      rich_entries+=("${candidate_entries[$candidate_index]}")
      rich_catalogs+=("${candidate_catalogs[$candidate_index]}")
      rich_execution_paths+=("${candidate_paths[$candidate_index]}")
      rich_eligibilities+=(runnable)
      rich_reasons+=('')
      rich_schemas+=("${candidate_schemas[$candidate_index]}")
      rich_fingerprints+=("${candidate_fingerprints[$candidate_index]}")
      rich_modes+=("${candidate_modes[$candidate_index]}")
    fi
    candidate_index=$((candidate_index + 1))
  done
  if [ -z "$menu_rows" ]; then
    _god_interaction_no_candidate_reason="${first_exclusion_reason:-environment requirements are not verified}"
    return "$_GOD_INTERACTION_NO_CANDIDATE_STATUS"
  fi

  _god_interaction_result_version=''
  _god_interaction_result_action=''
  _god_interaction_result_index=''
  _god_interaction_result_model=''
  _god_interaction_select "$menu_rows" "$initial_selected" "$header_title" "$header_subtitle"
  picker_status=$?
  [ "$picker_status" -eq 0 ] || return "$picker_status"

  result_version=$_god_interaction_result_version
  action=$_god_interaction_result_action
  storage_index=$_god_interaction_result_index
  model=$_god_interaction_result_model
  unset _god_interaction_result_version _god_interaction_result_action
  unset _god_interaction_result_index _god_interaction_result_model
  [ "$result_version" = 1 ] || return 3
  [ "$action" != CANCEL ] || return 0
  case "$action" in RUN|EDIT) ;; *) return 3 ;; esac
  case "$storage_index" in ''|*[!0-9]*) return 3 ;; esac

  service="${rich_services[$storage_index]:-}"
  catalog="${rich_catalogs[$storage_index]:-}"
  execution_path="${rich_execution_paths[$storage_index]:-}"
  group="${rich_groups[$storage_index]:-}"
  entry="${rich_entries[$storage_index]:-}"
  [ -n "$service" ] && [ -n "$catalog" ] && [ -n "$group" ] && [ -n "$entry" ] && [ -n "$model" ] || return 1

  _god_interaction_recheck_selected "$storage_index" || return $?

  risk=''
  original=''
  while IFS="$tab" read -r model_tag model_value; do
    case "$model_tag" in
      RISK) risk=$model_value ;;
      DISPLAY) original=$model_value ;;
    esac
  done <<< "$model"
  if [ "$action" = EDIT ]; then
    [ -n "$original" ] || return 3
    _god_menu_edited_command=''
    _god_menu_open_tty || return 3
    _god_menu_readline_edit "$original"
    edit_status=$?
    _god_menu_close_tty
    [ "$edit_status" -eq 0 ] || return "$edit_status"
    edited_command=$_god_menu_edited_command
    if [ -n "$edited_command" ] && [ "$edited_command" != "$original" ] && \
       [ -n "$(type -t _god_execute_edited 2>/dev/null)" ]; then
      _god_execute_edited "$edited_command" "$risk" 1
      return $?
    fi
  fi

  pending=0
  while IFS="$tab" read -r model_tag model_value; do
    case "$model_tag" in
      PENDING) pending=1 ;;
    esac
  done <<< "$model"

  # Placeholder prompts happen only after the operator picks that row. A
  # fully prepared command takes the fast path and executes the exact safe
  # template that was already previewed, without another catalog parse.
  if [ "$pending" = 1 ]; then
    interactive_model="$(_god_resolve_reviewed_model_interactive \
      "$service" "$catalog" "$group" "$entry" "$execution_path" "$query" runnable '')" || return $?
    # A placeholder prompt can keep the terminal in user control long enough
    # for PATH, discovery, Target, or declared requirements to change.
    _god_interaction_recheck_selected "$storage_index" || return $?
    _god_execute_reviewed_model "$interactive_model" 1
  else
    _god_execute_reviewed_model "$model" 1
  fi
}
