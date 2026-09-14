#!/usr/bin/env bash

set -o nounset
set -o pipefail

project_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)" || exit 1

checks=0
failures=0

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

fixture="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-tui-adapter.XXXXXX")" || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

fake_helper="$fixture/god-tui"
fake_log="$fixture/helper.log"
detail_log="$fixture/detail.log"

command cat > "$fake_helper" <<'FAKE_HELPER'
#!/usr/bin/env bash
set -o nounset

if [ "${1:-}" = --protocol-version ]; then
  printf '%s\n' "${FAKE_TUI_VERSION:-1}"
  exit 0
fi

while IFS= read -r record; do
  printf '%s\n' "$record" >> "$FAKE_TUI_LOG"
  case "$record" in
    BGTUI$'\t'1$'\t'READY) break ;;
  esac
done

case "${FAKE_TUI_MODE:-run_initial}" in
  run_initial)
    printf 'BGTUI\t1\tRESULT\tRUN\t0\n'
    ;;
  run_second)
    printf 'BGTUI\t1\tDETAIL\t41\t1\n'
    IFS= read -r reply || exit 2
    printf '%s\n' "$reply" >> "$FAKE_TUI_LOG"
    printf 'BGTUI\t1\tRESULT\tRUN\t1\n'
    ;;
  edit_initial)
    printf 'BGTUI\t1\tRESULT\tEDIT\t0\n'
    ;;
  run_blocked)
    printf 'BGTUI\t1\tRESULT\tRUN\t1\n'
    ;;
  terminal_error)
    printf 'synthetic terminal failure\n' >&2
    exit 3
    ;;
  hold_until_closed)
    # The parent signal test closes this bridge; do not use a timing-based
    # fake because a real terminal can be arbitrarily slow.
    while IFS= read -r record; do
      printf '%s\n' "$record" >> "$FAKE_TUI_LOG"
    done
    ;;
  *) exit 2 ;;
esac
FAKE_HELPER
chmod 0755 "$fake_helper"

# shellcheck source=../BASH_GOD.sh
. "$project_dir/BASH_GOD.sh" || exit 1

export TERM=xterm-256color
export FAKE_TUI_LOG="$fake_log"
export FAKE_TUI_VERSION=1
_BASH_GOD_TUI_HELPER_OVERRIDE="$fake_helper"
_god_menu_tty_available() { return 0; }
# The protocol fixture deliberately runs without a controlling TTY. Real
# terminal-state restoration belongs to tui-pty-smoke.sh; keep this adapter
# unit focused on the bounded wire conversation.
_god_tui_capture_terminal() { _god_tui_tty_state=''; return 0; }

rows="$(printf 'First operation\t\t\t1\t\nSecond operation\tneeds review\tWARN\t1\t')"
escape="$(printf '\033')"

test_detail_provider() {
  printf '%s\n' "$1" >> "$detail_log"
  case "$1" in
    1) _god_menu_provider_detail="printf '%s' '\$HOME; still data'" ;;
    2) _god_menu_provider_detail="curl -sS 'https://host/path?q=two words&literal=\$HOME;still-data'" ;;
    *) return 1 ;;
  esac
}

if [ -r "$project_dir/src/ui/tui.sh" ] && \
   [ -n "$(type -t _god_tui_available 2>/dev/null)" ] && \
   [ -n "$(type -t _god_tui_select 2>/dev/null)" ]; then
  pass 'the shared shell adapter is sourced'
else
  fail 'the shared shell adapter is sourced'
fi

if _god_tui_available && [ "${_god_tui_helper:-}" = "$fake_helper" ]; then
  pass 'the adapter accepts only a protocol-compatible helper'
else
  fail 'the adapter accepts only a protocol-compatible helper'
fi

: > "$fake_log"
: > "$detail_log"
export FAKE_TUI_MODE=run_second
adapter_status=0
_god_tui_select "$rows" 1 'KAFKA SEARCH RESULTS' 'Smart search: offsets' test_detail_provider || adapter_status=$?
helper_wire="$(command cat "$fake_log")"
detail_calls="$(command cat "$detail_log")"
if [ "$adapter_status" -eq 0 ] && [ "${_god_tui_action:-}" = RUN ] && \
   [ "${_god_tui_index:-}" = 1 ] && [ "$detail_calls" = "$(printf '1\n2')" ] && \
   contains "$helper_wire" $'BGTUI\t1\tSTART\t0\t2\t' && \
   contains "$helper_wire" $'BGTUI\t1\tROW\t0\t1\t1\t' && \
   contains "$helper_wire" $'BGTUI\t1\tROW\t1\t1\t0\t' && \
   contains "$helper_wire" $'BGTUI\t1\tDETAIL_RESULT\t41\t1\tOK\t' && \
   ! contains "$helper_wire" '$HOME; still data' && \
   ! contains "$helper_wire" 'https://host/path'; then
  pass 'lazy detail exchange preserves encoded display data and immutable indices'
else
  fail 'lazy detail exchange preserves encoded display data and immutable indices'
fi

export FAKE_TUI_MODE=run_blocked
blocked_rows="$(printf 'Runnable\t\t\t1\t\nBlocked\tmissing tool\t\t0\t')"
blocked_diagnostics="$fixture/blocked.err"
blocked_status=0
_god_tui_select "$blocked_rows" 1 'SEARCH RESULTS' 'Smart search: test' test_detail_provider > /dev/null 2> "$blocked_diagnostics" || blocked_status=$?
if [ "$blocked_status" -eq 3 ] && [ "${_god_tui_action:-}" = CANCEL ] && \
   contains "$(command cat "$blocked_diagnostics")" 'refused a result for a blocked row'; then
  pass 'the parent refuses a helper result for a blocked row'
else
  fail 'the parent refuses a helper result for a blocked row'
fi

export FAKE_TUI_MODE=terminal_error
fallback_status=0
_god_tui_select "$rows" 1 'SEARCH RESULTS' 'Smart search: test' test_detail_provider >/dev/null 2>&1 || fallback_status=$?
if [ "$fallback_status" -eq 125 ] && [ "${_god_tui_action:-}" = CANCEL ]; then
  pass 'terminal startup failure requests the static search fallback'
else
  fail 'terminal startup failure requests the static search fallback'
fi

_god_tui_reset_cache
_BASH_GOD_TUI_HELPER_OVERRIDE="$fixture/missing-god-tui"
if ! _god_tui_available; then
  pass 'a missing helper leaves the static path available'
else
  fail 'a missing helper leaves the static path available'
fi

_god_tui_reset_cache
_BASH_GOD_TUI_HELPER_OVERRIDE="$fake_helper"
export FAKE_TUI_VERSION=99
if ! _god_tui_available; then
  pass 'a protocol-mismatched helper leaves the static path available'
else
  fail 'a protocol-mismatched helper leaves the static path available'
fi
export FAKE_TUI_VERSION=1
_god_tui_reset_cache

GOD_COLOR=never
_god_style_init
_god_stdout_is_terminal() { return 0; }
export FAKE_TUI_MODE=terminal_error
: > "$fake_log"
terminal_fallback_output="$(_god_search 'current hostname' smart list general '' 0 2>&1)"
if contains "$terminal_fallback_output" 'GENERAL SEARCH RESULTS' && \
   contains "$terminal_fallback_output" 'MATCHING OPERATIONS' && \
   contains "$(command cat "$fake_log")" $'BGTUI\t1\tREADY'; then
  pass 'search renders the static results when helper terminal startup fails'
else
  fail 'search renders the static results when helper terminal startup fails'
  printf '%s\n' "$terminal_fallback_output"
fi

_god_tui_reset_cache
_BASH_GOD_TUI_HELPER_OVERRIDE="$fixture/missing-god-tui"
missing_fallback_output="$(_god_search 'current hostname' smart list general '' 0 2>&1)"
if contains "$missing_fallback_output" 'GENERAL SEARCH RESULTS' && \
   contains "$missing_fallback_output" 'MATCHING OPERATIONS' && \
   ! contains "$missing_fallback_output" "$escape"; then
  pass 'missing-helper search fallback is static and control-sequence free'
else
  fail 'missing-helper search fallback is static and control-sequence free'
  printf '%s\n' "$missing_fallback_output"
fi

_god_tui_reset_cache
_BASH_GOD_TUI_HELPER_OVERRIDE="$fake_helper"

models=("$(printf 'MODEL\t1\nIDENTITY\tkafka\tgroups\t1\nCONTEXT\tDISCOVER\tENDPOINT\nELIGIBILITY\trunnable\nRISK\t\nDISPLAY\toriginal command\nTEMPLATE\tprintf ok')")
tab="$(printf '\t')"
query=test
_god_interaction_detail_provider() {
  _god_menu_provider_detail='original command'
}
export FAKE_TUI_MODE=edit_initial
interaction_status=0
_god_interaction_result_version=''
_god_interaction_result_action=''
_god_interaction_result_index=''
_god_interaction_result_model=''
_god_interaction_select "$(printf 'Editable\t\t\t1\t')" 1 'SEARCH RESULTS' 'Smart search: edit' || interaction_status=$?
if [ "$interaction_status" -eq 0 ] && [ "${_god_interaction_result_version:-}" = 1 ] && \
   [ "${_god_interaction_result_action:-}" = EDIT ] && \
   [ "${_god_interaction_result_index:-}" = 0 ] && \
   contains "${_god_interaction_result_model:-}" $'DISPLAY\toriginal command'; then
  pass 'EDIT releases the helper with the selected reviewed model for native editor handoff'
else
  fail 'EDIT releases the helper with the selected reviewed model for native editor handoff'
fi

# The parent owns the bridge, so an interrupt directed only to the parent must
# still release the helper, restore the caller's trap, and return promptly.
# Wait only for the fake's observable READY record; no sleep-based timing is
# involved in this regression check.
: > "$fake_log"
signal_output="$(TERM=xterm-256color FAKE_TUI_MODE=hold_until_closed \
  FAKE_TUI_LOG="$fake_log" _BASH_GOD_TUI_HELPER_OVERRIDE="$fake_helper" \
  bash -c '
    . "$1/BASH_GOD.sh"
    _god_menu_tty_available() { return 0; }
    _god_tui_capture_terminal() { _god_tui_tty_state=""; return 0; }
    test_detail_provider() { _god_menu_provider_detail="fake command"; }
    trap '\''printf "CALLER_INT\\n"'\'' INT
    (
      attempts=0
      while ! LC_ALL=C grep -Fq $'\''BGTUI\t1\tREADY'\'' "$FAKE_TUI_LOG" 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -le 100000 ] || exit 1
      done
      kill -TERM "$$"
    ) &
    _god_tui_select $'\''First operation\t\t\t1\t'\'' 1 "SEARCH RESULTS" "Smart search: signal" test_detail_provider
    signal_status=$?
    printf "SELECT_STATUS:%s\\n" "$signal_status"
    trap -p INT
  ' _ "$project_dir" 2>&1)"
if contains "$signal_output" 'SELECT_STATUS:130' && \
   contains "$signal_output" 'CALLER_INT'; then
  pass 'parent interrupt closes the helper bridge and restores caller traps'
else
  fail 'parent interrupt closes the helper bridge and restores caller traps'
  printf '%s\n' "$signal_output"
fi

edited_placeholder_output="$(bash -c '
  . "$1/BASH_GOD.sh"
  _god_execute_run() { printf "UNEXPECTED CHILD\n"; }
  _god_execute_edited "kubectl get pods -n <namespace> --watch" "" 1
  printf "EDITED PLACEHOLDER STATUS:%s\n" "$?"
' _ "$project_dir" 2>&1)"
if contains "$edited_placeholder_output" 'edited command still contains an unresolved placeholder' && \
   contains "$edited_placeholder_output" 'EDITED PLACEHOLDER STATUS:2' && \
   ! contains "$edited_placeholder_output" 'UNEXPECTED CHILD'; then
  pass 'an edited unresolved command stops before the child boundary'
else
  fail 'an edited unresolved command stops before the child boundary'
  printf '%s\n' "$edited_placeholder_output"
fi

printf '\n%d adapter checks passed.\n' "$((checks - failures))"
[ "$failures" -eq 0 ]
