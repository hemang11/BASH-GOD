#!/usr/bin/env bash

# BASH_GOD execution. Shows the resolved command, asks once, and runs it only
# on an explicit yes. Values harvested from the user's query never become
# shell syntax: they travel as positional parameters to `bash -c`, never
# interpolated into the command text itself.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_god_execute_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || \
  _god_execute_dir=''
if [ -n "$_god_execute_dir" ]; then
  if [ -z "$(type -t _god_catalog_command_export 2>/dev/null)" ] && [ -r "$_god_execute_dir/catalog.sh" ]; then
    # shellcheck source=catalog.sh
    . "$_god_execute_dir/catalog.sh" || exit 1
  fi
  if [ -z "$(type -t _god_resolve_command_interactive 2>/dev/null)" ] && [ -r "$_god_execute_dir/resolve.sh" ]; then
    # shellcheck source=resolve.sh
    . "$_god_execute_dir/resolve.sh" || exit 1
  fi
fi

# _god_execute_is_state_mutating RUN
#
# cd, export, unset, and source only change the child process bash -c would
# run in, never the caller's shell, so running them from here would silently
# do nothing useful. Checked against the catalog's own leading word.
_god_execute_is_state_mutating() {
  local first

  first="$1"
  first="${first#"${first%%[![:space:]]*}"}"
  first="${first%% *}"
  case "$first" in
    cd|export|unset|source) return 0 ;;
    *) return 1 ;;
  esac
}

# _god_execute_prepare_terminal
#
# Rich selection and command editing both temporarily put the controlling TTY
# into interactive modes. Restore the basics before handing control to a native
# CLI so stderr is visible and Ctrl-C is delivered as a signal, not as a raw
# byte that the child process never handles.
_god_execute_prepare_terminal() {
  stty echo icanon isig </dev/tty 2>/dev/null || :
}

# _god_execute_confirm DISPLAY RISK
#
# Returns 0 on an explicit y/Y, 1 on any other reply (default is No), 2 when
# no controlling terminal is available at all.
_god_execute_confirm() {
  local display risk reply

  display=$1
  risk=$2
  { exec 3<>/dev/tty; } 2>/dev/null || return 2

  printf '\n' >&3
  if [ -n "$risk" ]; then
    printf '  %s[%s]%s %s\n' "${_GOD_WARNING:-}" "$risk" "${_GOD_RESET:-}" "$display" >&3
  else
    printf '  %s\n' "$display" >&3
  fi
  printf 'Run this? [y/N]: ' >&3
  IFS= read -r reply <&3
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null

  case "$reply" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

# _god_execute_run TEMPLATE [VALUE ...]
#
# TEMPLATE is catalog-derived shell text with "$1", "$2", ... standing in for
# each VALUE; VALUEs are passed as bash -c's positional parameters, never
# interpolated into TEMPLATE, so a harvested `; rm -rf /` is an inert
# argument rather than shell syntax. Interactive runs use the controlling TTY
# directly; non-interactive runs inherit stdio as a fallback.
_god_execute_run() {
  local template status

  template=$1
  shift
  _god_execute_prepare_terminal

  # The picker is rendered on the controlling terminal, so hand the native
  # process that same terminal explicitly. This keeps stdout, stderr, stdin,
  # and signals together even after the picker has opened and closed its own
  # descriptor. In non-interactive environments /dev/tty is absent and the
  # established inherited-stdio path remains available.
  if { exec 3<>/dev/tty; } 2>/dev/null; then
    bash -c "$template" god-run "$@" <&3 >&3 2>&3
    status=$?
    exec 3<&- 2>/dev/null
    exec 3>&- 2>/dev/null
    return "$status"
  fi

  bash -c "$template" god-run "$@"
}

# _god_execute_resolved DISPLAY TEMPLATE RISK REVIEWED [VALUE ...]
#
# Runs an already-resolved, argument-safe command model. The rich picker
# creates this model once for the selected preview, so Enter does not make the
# user wait while the catalog is parsed and the same values are resolved again.
# TEMPLATE keeps user-derived VALUEs as positional parameters to bash -c.
_god_execute_resolved() {
  local display template risk reviewed confirm_status

  display=$1
  template=$2
  risk=$3
  reviewed=${4:-0}
  shift 4

  [ -n "$template" ] || return 2
  if _god_resolve_is_placeholder "$template"; then
    printf 'BASH_GOD: the command still contains an unresolved placeholder and was not run.\n' >&2
    return 2
  fi
  if _god_execute_is_state_mutating "$template"; then
    printf 'BASH_GOD: "%s" only changes the state of a child shell, so running it here would do nothing.\n' "${template%% *}" >&2
    printf 'Run it directly in your own shell instead.\n' >&2
    return 2
  fi

  if [ "$reviewed" != 1 ]; then
    _god_execute_confirm "$display" "$risk"
    confirm_status=$?
    case "$confirm_status" in
      0) ;;
      2)
        printf 'BASH_GOD: execution needs a terminal. Showing the command only:\n%s\n' "$display" >&2
        return 1
        ;;
      *)
        printf 'Cancelled.\n' >&2
        return 1
        ;;
    esac
  else
    printf '\n  Running selected command…\n\n' >&2
  fi

  _god_execute_run "$template" "$@"
}

# _god_execute_command SERVICE CATALOG GROUP ENTRY EXECUTION_PATH QUERY [REVIEWED]
#
# Returns 0 after running the command, 1 when the user declined or no
# terminal was available, 2 when the record cannot be executed at all
# (a shell-state mutator, or the record has no @run to show). REVIEWED=1 is
# used only by the rich picker: Enter there is the explicit confirmation after
# the complete resolved command has been on screen.
_god_execute_command() {
  local service catalog group entry execution_path query reviewed tab
  local run risk tag value display template resolved resolve_status
  local -a values

  service=$1
  catalog=$2
  group=$3
  entry=$4
  execution_path=$5
  query=$6
  reviewed=${7:-0}
  tab="$(printf '\t')"

  run=''
  risk=''
  while IFS="$tab" read -r tag value; do
    case "$tag" in
      RUN) run=$value ;;
      RISK) risk=$value ;;
    esac
  done < <(_god_catalog_command_export "$catalog" "$group" "$entry")
  [ -n "$run" ] || return 2

  display=''
  template=''
  values=()
  resolved="$(_god_resolve_command_interactive "$service" "$catalog" "$group" "$entry" "$execution_path" "$query")"
  resolve_status=$?
  [ "$resolve_status" -eq 0 ] || return "$resolve_status"
  while IFS="$tab" read -r tag value; do
    case "$tag" in
      DISPLAY) display=$value ;;
      TEMPLATE) template=$value ;;
      VALUE) values+=("$value") ;;
    esac
  done <<< "$resolved"
  [ -n "$template" ] || return 2

  _god_execute_resolved "$display" "$template" "$risk" "$reviewed" "${values[@]}"
}

# _god_execute_edited COMMAND RISK [REVIEWED]
#
# Runs a command line the user hand-edited in the picker's detail panel.
# COMMAND is already fully expanded, human-typed text — the same trust level
# as anything a user runs directly in their own shell — so it goes to
# `bash -c` verbatim rather than through TEMPLATE/VALUE templating.
# Returns 0 after running, 1 when declined or no terminal, 2 for a
# shell-state mutator.
_god_execute_edited() {
  local command risk reviewed confirm_status

  command=$1
  risk=$2
  reviewed=${3:-0}
  [ -n "$command" ] || return 2

  if _god_execute_is_state_mutating "$command"; then
    printf 'BASH_GOD: "%s" only changes the state of a child shell, so running it here would do nothing.\n' "${command%% *}" >&2
    printf 'Run it directly in your own shell instead.\n' >&2
    return 2
  fi

  if [ "$reviewed" != 1 ]; then
    _god_execute_confirm "$command" "$risk"
    confirm_status=$?
    case "$confirm_status" in
      0) ;;
      2)
        printf 'BASH_GOD: execution needs a terminal. Showing the command only:\n%s\n' "$command" >&2
        return 1
        ;;
      *)
        printf 'Cancelled.\n' >&2
        return 1
        ;;
    esac
  else
    printf '\n  Running selected command…\n\n' >&2
  fi

  _god_execute_run "$command"
}
