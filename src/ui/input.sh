#!/usr/bin/env bash

# BASH_GOD terminal input and editor adapter. This module owns /dev/tty
# helpers for the basic maintenance menu and the native command-line editor
# handoff. Browse-time raw input, redraw, and signal handling belong to god-tui.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

: "${_god_menu_tty_fd:=}"

# One basic-picker read owns both ESC and its optional arrow tail. Results are
# returned as data so menu.sh can decide what a key means without reading the
# terminal itself.
_god_menu_read_basic_key() {
  _god_menu_basic_key=''
  _god_menu_basic_tail=''
  IFS= read -r -s -n 1 _god_menu_basic_key <&3 || return 1
  if [ "$_god_menu_basic_key" = "$(printf '\033')" ]; then
    IFS= read -r -s -n 2 -t 1 _god_menu_basic_tail <&3 || _god_menu_basic_tail=''
  fi
}

_god_menu_read_reply() {
  _god_menu_reply=''
  IFS= read -r _god_menu_reply <&3 || _god_menu_reply=''
}

# Open the controlling terminal on a dedicated descriptor. Absent in CI, cron,
# and containers without a controlling terminal, so callers must handle failure
# rather than block.
_god_menu_open_tty() {
  # Bash reports a failed redirection itself, so the whole compound command is
  # silenced rather than the exec alone.
  { exec 3<>/dev/tty; } 2>/dev/null || return 1
  _god_menu_tty_fd=3
  return 0
}

_god_menu_close_tty() {
  [ -n "$_god_menu_tty_fd" ] || return 0
  # `exec` without a command changes the current shell's descriptors. Scope
  # stderr suppression to this close attempt so a successful editor/picker
  # handoff never accidentally discards later native-command diagnostics.
  { exec 3<&-; } 2>/dev/null || :
  { exec 3>&-; } 2>/dev/null || :
  _god_menu_tty_fd=''
}

# Usable width for the compact basic selector. A conservative fallback keeps
# its fixed redraw frame readable when a terminal does not report dimensions.
_god_menu_width() {
  local size width

  width=''
  if [ -n "$_god_menu_tty_fd" ]; then
    size="$(stty size <&3 2>/dev/null)" || size=''
    width="${size##* }"
  fi
  case "$width" in
    ''|*[!0-9]*) width=80 ;;
  esac
  [ "$width" -ge 40 ] || width=80
  printf '%s\n' "$width"
}

_god_menu_tty_available() {
  _god_menu_open_tty || return 1
  _god_menu_close_tty
}

# The Go helper owns browse-time raw input, rendering, and signals. This
# module resumes only after it exits, for the native command-line editor.

_god_menu_readline_edit() {
  local initial result_file prompt status marker_start marker_end tty_state

  initial=$1
  _god_menu_edited_command=''

  # Readline-compatible editors may temporarily adjust more than canonical
  # mode and echo. Preserve the exact controlling-TTY state so returning from
  # edit is indistinguishable from having typed directly at the shell.
  tty_state="$(stty -g <&3 2>/dev/null)" || tty_state=''

  result_file="$(mktemp "${TMPDIR:-/tmp}/bash-god-edit.XXXXXX" 2>/dev/null)" || return 1

  # BASH_GOD's rich interaction path is Bash-owned, so prefer Bash readline
  # when it can prefill the command. This preserves familiar word movement
  # (Option/Alt-left and right) instead of unexpectedly switching shells.
  if [ -n "${BASH_VERSION:-}" ] && help read 2>/dev/null | LC_ALL=C grep -q -- '-i'; then
    IFS= read -r -e -i "$initial" -p '  $ ' _god_menu_edited_command <&3 >&3 2>&3
    status=$?
    [ -z "$tty_state" ] || stty "$tty_state" <&3 2>/dev/null || :
    rm -f "$result_file"
    return "$status"
  fi

  if command -v zsh >/dev/null 2>&1; then
    BASH_GOD_EDIT_INITIAL=$initial \
    BASH_GOD_EDIT_RESULT=$result_file \
      zsh -f -c '
cmd=$BASH_GOD_EDIT_INITIAL
vared -p "  $ " cmd
edit_status=$?
if [ "$edit_status" -eq 0 ]; then
  print -rn -- "$cmd" > "$BASH_GOD_EDIT_RESULT" || exit 1
fi
exit "$edit_status"
' <&3 >&3 2>&3
    status=$?
    if [ "$status" -eq 0 ] && [ -r "$result_file" ]; then
      if IFS= read -r _god_menu_edited_command < "$result_file"; then
        :
      elif [ -n "$_god_menu_edited_command" ]; then
        :
      else
        _god_menu_edited_command=''
      fi
    fi
    [ -z "$tty_state" ] || stty "$tty_state" <&3 2>/dev/null || :
    rm -f "$result_file"
    return "$status"
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    printf '  BASH_GOD: command editing needs zsh, bash read -i, or python3 readline on this terminal.\n' >&3
    [ -z "$tty_state" ] || stty "$tty_state" <&3 2>/dev/null || :
    rm -f "$result_file"
    return 1
  fi

  marker_start="$(printf '\001')"
  marker_end="$(printf '\002')"
  if [ -n "$_god_menu_command$_god_menu_reset" ]; then
    prompt="  ${marker_start}${_god_menu_command}${marker_end}\$${marker_start}${_god_menu_reset}${marker_end} "
  else
    prompt='  $ '
  fi
  BASH_GOD_EDIT_INITIAL=$initial \
  BASH_GOD_EDIT_RESULT=$result_file \
  BASH_GOD_EDIT_PROMPT=$prompt \
    python3 -c '
import os
import sys

try:
    import readline
except Exception as exc:
    print(f"  BASH_GOD: python readline unavailable: {exc}", file=sys.stderr)
    sys.exit(2)

initial = os.environ.get("BASH_GOD_EDIT_INITIAL", "")
result = os.environ["BASH_GOD_EDIT_RESULT"]
prompt = os.environ.get("BASH_GOD_EDIT_PROMPT", "$ ")

def prefill():
    readline.insert_text(initial)
    redisplay = getattr(readline, "redisplay", None)
    if redisplay is not None:
        redisplay()

readline.set_startup_hook(prefill)
try:
    line = input(prompt)
except (EOFError, KeyboardInterrupt):
    print()
    sys.exit(130)
finally:
    readline.set_startup_hook()

with open(result, "w", encoding="utf-8") as handle:
    handle.write(line)
' <&3 >&3 2>&3
  status=$?
  if [ "$status" -eq 0 ] && [ -r "$result_file" ]; then
    if IFS= read -r _god_menu_edited_command < "$result_file"; then
      :
    elif [ -n "$_god_menu_edited_command" ]; then
      :
    else
      _god_menu_edited_command=''
    fi
  fi
  [ -z "$tty_state" ] || stty "$tty_state" <&3 2>/dev/null || :
  rm -f "$result_file"
  return "$status"
}
