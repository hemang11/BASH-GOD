#!/usr/bin/env bash

# Shell-side adapter for the optional god-tui helper. This module owns helper
# discovery and the bounded BGTUI/1 conversation. It does not parse catalogs,
# resolve service policy, edit commands, or execute native processes.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_GOD_TUI_PROTOCOL_VERSION=1
_GOD_TUI_STATIC_FALLBACK_STATUS=125

_god_tui_reset_cache() {
  unset _god_tui_helper _god_tui_cache_key _god_tui_cache_status
}

_god_tui_installed_manifest_matches() {
  local manifest artifact expected actual

  manifest=$1
  artifact=$2
  [ -r "$manifest" ] && [ ! -L "$manifest" ] || return 1
  case "${_BASH_GOD_VERSION:-}" in
    ''|*[!0-9.]*) return 1 ;;
  esac
  expected="$(printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=%s\nprotocol=%s' \
    "$_BASH_GOD_VERSION" "$artifact" "$_GOD_TUI_PROTOCOL_VERSION")"
  actual="$(command cat "$manifest" 2>/dev/null)" || return 1
  [ "$actual" = "$expected" ]
}

_god_tui_find_helper() {
  local candidate prefix runtime manifest artifact line

  if [ -n "${_BASH_GOD_TUI_HELPER_OVERRIDE:-}" ]; then
    [ -x "$_BASH_GOD_TUI_HELPER_OVERRIDE" ] || return 1
    printf '%s\n' "$_BASH_GOD_TUI_HELPER_OVERRIDE"
    return 0
  fi

  # Source contributors may build the ignored repository-root helper with:
  #   go build -o god-tui ./cmd/god-tui
  candidate="${_BASH_GOD_CORE_DIR%/src}/god-tui"
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # A packaged runtime keeps the helper off the user's PATH. Its manifest is
  # part of the shell/helper contract: a mixed runtime, helper, or protocol
  # must fall back to static results rather than use an arbitrary PATH helper.
  case "$_BASH_GOD_CORE_DIR" in
    */lib/bash-god/src)
      prefix="${_BASH_GOD_CORE_DIR%/lib/bash-god/src}"
      candidate="$prefix/libexec/bash-god/god-tui"
      runtime="${_BASH_GOD_CORE_DIR%/src}"
      manifest="$runtime/tui-manifest"
      artifact=''
      if [ -r "$manifest" ] && [ ! -L "$manifest" ]; then
        while IFS= read -r line || [ -n "${line:-}" ]; do
          case "$line" in
            artifact=*) artifact=${line#artifact=} ;;
          esac
        done < "$manifest"
      fi
      case "$artifact" in
        darwin-amd64|darwin-arm64|linux-amd64|linux-arm64) ;;
        *) return 1 ;;
      esac
      if [ -x "$candidate" ] && _god_tui_installed_manifest_matches "$manifest" "$artifact"; then
        printf '%s\n' "$candidate"
        return 0
      fi
      return 1
      ;;
  esac

  candidate="$(command -v god-tui 2>/dev/null)" || candidate=''
  [ -n "$candidate" ] && [ -x "$candidate" ] || return 1
  printf '%s\n' "$candidate"
}

_god_tui_available() {
  local cache_key helper version

  [ -n "${BASH_VERSION:-}" ] || return 1
  [ "${TERM:-}" != dumb ] || return 1
  command -v base64 >/dev/null 2>&1 || return 1
  command -v mkfifo >/dev/null 2>&1 || return 1
  [ -n "$(type -t _god_menu_tty_available 2>/dev/null)" ] || return 1
  _god_menu_tty_available || return 1

  cache_key="${_BASH_GOD_TUI_HELPER_OVERRIDE:-auto}"
  if [ "${_god_tui_cache_key:-}" = "$cache_key" ]; then
    [ "${_god_tui_cache_status:-1}" = 0 ] || return 1
    [ -x "${_god_tui_helper:-}" ]
    return $?
  fi

  _god_tui_cache_key=$cache_key
  _god_tui_cache_status=1
  _god_tui_helper=''
  helper="$(_god_tui_find_helper)" || return 1
  version="$("$helper" --protocol-version 2>/dev/null)" || return 1
  [ "$version" = "$_GOD_TUI_PROTOCOL_VERSION" ] || return 1
  _god_tui_helper=$helper
  _god_tui_cache_status=0
  return 0
}

_god_tui_base64() {
  # BSD and GNU base64 use different no-wrap flags. Removing line endings is
  # portable and safe because the input is an already validated display field.
  printf '%s' "$1" | base64 | LC_ALL=C tr -d '\r\n'
}

_god_tui_close_session() {
  if [ "${_god_tui_write_open:-0}" = 1 ]; then
    { exec 8>&-; } 2>/dev/null || :
    _god_tui_write_open=0
  fi
  if [ "${_god_tui_read_open:-0}" = 1 ]; then
    { exec 9<&-; } 2>/dev/null || :
    _god_tui_read_open=0
  fi
}

# Bubble Tea restores the raw-mode attributes it changes. Retain the complete
# shell-side state as well: on some terminals, queued-input flags can change
# after a raw-mode session even though canonical mode and echo look normal.
# This snapshot is per picker invocation, never a generic `stty sane`, so it
# preserves the caller's own erase, flow-control, and signal preferences.
_god_tui_capture_terminal() {
  _god_tui_tty_state="$(stty -g </dev/tty 2>/dev/null)" || return 1
  [ -n "$_god_tui_tty_state" ]
}

_god_tui_restore_terminal() {
  [ -z "${_god_tui_tty_state:-}" ] || stty "$_god_tui_tty_state" </dev/tty 2>/dev/null || :
  unset _god_tui_tty_state
}

_god_tui_remove_session() {
  [ -z "${_god_tui_session_dir:-}" ] || command rm -rf -- "$_god_tui_session_dir"
  unset _god_tui_session_dir _god_tui_input_fifo _god_tui_output_fifo _god_tui_diagnostics
  unset _god_tui_write_open _god_tui_read_open _god_tui_pid
}

# The helper owns the terminal only while it is running.  The parent owns the
# short-lived FIFO bridge and must tear it down even when the operator sends a
# signal to the foreground process group.  Keep the caller's traps intact:
# BASH_GOD can be sourced by an interactive shell with its own policy.
_god_tui_install_traps() {
  _god_tui_saved_int="$(trap -p INT)"
  _god_tui_saved_hup="$(trap -p HUP)"
  _god_tui_saved_term="$(trap -p TERM)"
  _god_tui_signal=0
  trap '_god_tui_signal=130; _god_tui_abort_helper' INT HUP TERM
}

_god_tui_restore_traps() {
  if [ -n "${_god_tui_saved_int:-}" ]; then
    eval "$_god_tui_saved_int"
  else
    trap - INT
  fi
  if [ -n "${_god_tui_saved_hup:-}" ]; then
    eval "$_god_tui_saved_hup"
  else
    trap - HUP
  fi
  if [ -n "${_god_tui_saved_term:-}" ]; then
    eval "$_god_tui_saved_term"
  else
    trap - TERM
  fi
  unset _god_tui_saved_int _god_tui_saved_hup _god_tui_saved_term
}

_god_tui_interrupted() {
  [ "${_god_tui_signal:-0}" -ne 0 ]
}

_god_tui_cancel_interrupted() {
  _god_tui_abort_helper
  _god_tui_restore_traps
  _god_tui_action=CANCEL
  _god_tui_index=-1
  unset _god_tui_signal
  return 130
}

_god_tui_finish_helper() {
  local helper_status

  # The helper writes its RESULT record before its terminal library has
  # necessarily completed its own final cleanup. Closing our read end as soon
  # as the record is parsed can race that cleanup and deliver SIGPIPE to the
  # helper. That used to turn a valid EDIT result into status 141 before the
  # normal line editor could open. Signal EOF to the helper's input first, but
  # retain the result reader until the helper has actually exited.
  if [ "${_god_tui_write_open:-0}" = 1 ]; then
    { exec 8>&-; } 2>/dev/null || :
    _god_tui_write_open=0
  fi
  helper_status=0
  if [ -n "${_god_tui_pid:-}" ]; then
    if wait "$_god_tui_pid"; then
      helper_status=0
    else
      helper_status=$?
    fi
  fi
  if [ "${_god_tui_read_open:-0}" = 1 ]; then
    { exec 9<&-; } 2>/dev/null || :
    _god_tui_read_open=0
  fi
  if [ -s "${_god_tui_diagnostics:-/dev/null}" ]; then
    command cat "$_god_tui_diagnostics" >&2
  fi
  _god_tui_restore_terminal
  _god_tui_remove_session
  return "$helper_status"
}

_god_tui_abort_helper() {
  _god_tui_close_session
  if [ -n "${_god_tui_pid:-}" ]; then
    kill -TERM "$_god_tui_pid" 2>/dev/null || :
    wait "$_god_tui_pid" 2>/dev/null || :
  fi
  if [ -s "${_god_tui_diagnostics:-/dev/null}" ]; then
    command cat "$_god_tui_diagnostics" >&2
  fi
  _god_tui_restore_terminal
  _god_tui_remove_session
}

_god_tui_reject_helper() {
  printf 'BASH_GOD TUI: %s\n' "$1" >&2
  _god_tui_abort_helper
}

_god_tui_write_request() {
  local rows initial header subtitle provider total index title compatibility risk runnable detail detail_known

  rows=$1
  initial=$2
  header=$3
  subtitle=$4
  provider=$5
  total="$(_god_menu_row_count "$rows")"

  printf 'BGTUI\t1\tSTART\t%s\t%s\t%s\t%s\n' \
    "$((initial - 1))" "$total" "$(_god_tui_base64 "$header")" "$(_god_tui_base64 "$subtitle")" >&8 || return 1

  index=1
  while [ "$index" -le "$total" ]; do
    title="$(_god_menu_field "$rows" "$index" 1)"
    compatibility="$(_god_menu_field "$rows" "$index" 2)"
    risk="$(_god_menu_field "$rows" "$index" 3)"
    runnable="$(_god_menu_field "$rows" "$index" 4)"
    detail=''
    detail_known=0
    if [ "$index" -eq "$initial" ]; then
      _god_menu_provider_detail=''
      "$provider" "$index" || return 1
      detail=${_god_menu_provider_detail:-}
      [ -n "$detail" ] || return 1
      detail_known=1
    fi
    printf 'BGTUI\t1\tROW\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$((index - 1))" "$runnable" "$detail_known" \
      "$(_god_tui_base64 "$title")" "$(_god_tui_base64 "$compatibility")" \
      "$(_god_tui_base64 "$risk")" "$(_god_tui_base64 "$detail")" >&8 || return 1
    index=$((index + 1))
  done
  printf 'BGTUI\t1\tREADY\n' >&8
}

_god_tui_send_detail() {
  local request_id index provider selected detail reason

  request_id=$1
  index=$2
  provider=$3
  selected=$((index + 1))
  _god_menu_provider_detail=''
  if "$provider" "$selected" && [ -n "${_god_menu_provider_detail:-}" ]; then
    detail=$_god_menu_provider_detail
    printf 'BGTUI\t1\tDETAIL_RESULT\t%s\t%s\tOK\t%s\t\n' \
      "$request_id" "$index" "$(_god_tui_base64 "$detail")" >&8
    return $?
  fi

  reason='unable to resolve this command'
  printf 'BGTUI\t1\tDETAIL_RESULT\t%s\t%s\tERROR\t\t%s\n' \
    "$request_id" "$index" "$(_god_tui_base64 "$reason")" >&8
}

# _god_tui_select ROWS INITIAL HEADER SUBTITLE DETAIL_PROVIDER
#
# ROWS is the existing 1-based menu model. BGTUI uses immutable zero-based
# indices. On success this sets _god_tui_action and _god_tui_index; it never
# edits or executes a command. Status 125 asks search.sh to render the static
# matching-operations view because the helper could not provide a terminal UI.
_god_tui_select() {
  local rows initial header subtitle provider total helper_status got_result
  local protocol version record field_a field_b extra request_id index action runnable

  rows=$1
  initial=$2
  header=$3
  subtitle=$4
  provider=$5
  _god_tui_action=CANCEL
  _god_tui_index=-1

  total="$(_god_menu_row_count "$rows")"
  case "$total" in ''|*[!0-9]*) return 3 ;; esac
  [ "$total" -ge 1 ] && [ "$total" -le 256 ] || return 3
  case "$initial" in ''|*[!0-9]*) return 3 ;; esac
  [ "$initial" -ge 1 ] && [ "$initial" -le "$total" ] || return 3
  [ -n "$provider" ] && [ -n "$(type -t "$provider" 2>/dev/null)" ] || return 3
  _god_tui_available || return "$_GOD_TUI_STATIC_FALLBACK_STATUS"

  _god_tui_session_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-tui.XXXXXX" 2>/dev/null)" || return 3
  _god_tui_input_fifo="$_god_tui_session_dir/to-helper"
  _god_tui_output_fifo="$_god_tui_session_dir/from-helper"
  _god_tui_diagnostics="$_god_tui_session_dir/diagnostics"
  _god_tui_install_traps
  if ! mkfifo "$_god_tui_input_fifo" "$_god_tui_output_fifo"; then
    _god_tui_remove_session
    _god_tui_restore_traps
    return 3
  fi

  if ! _god_tui_capture_terminal; then
    _god_tui_abort_helper >/dev/null 2>&1 || :
    _god_tui_restore_traps
    return "$_GOD_TUI_STATIC_FALLBACK_STATUS"
  fi

  "$_god_tui_helper" < "$_god_tui_input_fifo" > "$_god_tui_output_fifo" 2> "$_god_tui_diagnostics" &
  _god_tui_pid=$!
  _god_tui_write_open=0
  _god_tui_read_open=0
  if ! { exec 8>"$_god_tui_input_fifo"; }; then
    _god_tui_abort_helper >/dev/null 2>&1 || :
    _god_tui_restore_traps
    return "$_GOD_TUI_STATIC_FALLBACK_STATUS"
  fi
  _god_tui_write_open=1
  if ! { exec 9<"$_god_tui_output_fifo"; }; then
    _god_tui_abort_helper >/dev/null 2>&1 || :
    _god_tui_restore_traps
    return "$_GOD_TUI_STATIC_FALLBACK_STATUS"
  fi
  _god_tui_read_open=1

  if _god_tui_interrupted; then
    _god_tui_cancel_interrupted
    return $?
  fi

  if ! _god_tui_write_request "$rows" "$initial" "$header" "$subtitle" "$provider"; then
    if _god_tui_interrupted; then
      _god_tui_cancel_interrupted
      return $?
    fi
    _god_tui_reject_helper 'could not send the initial picker model' >/dev/null || :
    _god_tui_restore_traps
    return 3
  fi

  got_result=0
  while IFS="$(printf '\t')" read -r protocol version record field_a field_b extra <&9; do
    if _god_tui_interrupted; then
      _god_tui_cancel_interrupted
      return $?
    fi
    [ "$protocol" = BGTUI ] && [ "$version" = "$_GOD_TUI_PROTOCOL_VERSION" ] || {
      _god_tui_reject_helper 'received an unsupported protocol response' >/dev/null || :
      _god_tui_restore_traps
      return 3
    }
    case "$record" in
      DETAIL)
        [ -z "$extra" ] || { _god_tui_reject_helper 'received an invalid detail request' >/dev/null || :; _god_tui_restore_traps; return 3; }
        request_id=$field_a
        index=$field_b
        case "$request_id" in ''|0|*[!0-9]*) _god_tui_reject_helper 'received an invalid detail request id' >/dev/null || :; _god_tui_restore_traps; return 3 ;; esac
        case "$index" in ''|*[!0-9]*) _god_tui_reject_helper 'received an invalid detail index' >/dev/null || :; _god_tui_restore_traps; return 3 ;; esac
        [ "$index" -lt "$total" ] || { _god_tui_reject_helper 'received an out-of-range detail index' >/dev/null || :; _god_tui_restore_traps; return 3; }
        _god_tui_send_detail "$request_id" "$index" "$provider" || {
          if _god_tui_interrupted; then
            _god_tui_cancel_interrupted
            return $?
          fi
          _god_tui_reject_helper 'could not send the resolved picker detail' >/dev/null || :
          _god_tui_restore_traps
          return 3
        }
        ;;
      RESULT)
        [ -z "$extra" ] || { _god_tui_reject_helper 'received an invalid picker result' >/dev/null || :; _god_tui_restore_traps; return 3; }
        action=$field_a
        index=$field_b
        case "$action" in
          CANCEL)
            [ "$index" = -1 ] || { _god_tui_reject_helper 'received an invalid cancellation index' >/dev/null || :; _god_tui_restore_traps; return 3; }
            _god_tui_action=CANCEL
            _god_tui_index=-1
            ;;
          RUN|EDIT)
            case "$index" in ''|*[!0-9]*) _god_tui_reject_helper 'received an invalid result index' >/dev/null || :; _god_tui_restore_traps; return 3 ;; esac
            [ "$index" -lt "$total" ] || { _god_tui_reject_helper 'received an out-of-range result index' >/dev/null || :; _god_tui_restore_traps; return 3; }
            runnable="$(_god_menu_field "$rows" "$((index + 1))" 4)"
            [ "$runnable" = 1 ] || { _god_tui_reject_helper 'refused a result for a blocked row' >/dev/null || :; _god_tui_restore_traps; return 3; }
            _god_tui_action=$action
            _god_tui_index=$index
            ;;
          *) _god_tui_reject_helper 'received an unknown picker action' >/dev/null || :; _god_tui_restore_traps; return 3 ;;
        esac
        got_result=1
        break
        ;;
      *) _god_tui_reject_helper 'received an unknown protocol record' >/dev/null || :; _god_tui_restore_traps; return 3 ;;
    esac
  done

  if _god_tui_interrupted; then
    _god_tui_cancel_interrupted
    return $?
  fi

  helper_status=0
  _god_tui_finish_helper || helper_status=$?
  _god_tui_restore_traps
  unset _god_tui_signal
  if [ "$helper_status" -eq 130 ]; then
    _god_tui_action=CANCEL
    _god_tui_index=-1
    return 130
  fi
  if [ "$helper_status" -eq 2 ] || [ "$helper_status" -eq 3 ]; then
    _god_tui_action=CANCEL
    _god_tui_index=-1
    return "$_GOD_TUI_STATIC_FALLBACK_STATUS"
  fi
  [ "$helper_status" -eq 0 ] && [ "$got_result" -eq 1 ] || return 3
  return 0
}
