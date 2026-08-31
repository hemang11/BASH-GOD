#!/usr/bin/env bash

# BASH_GOD interactive selection. This file draws a keyboard-driven picker and
# returns the chosen index; it never evaluates catalog command text.
#
# Two entry styles share one implementation:
#   sourced   - a Bash caller sources this file and calls _god_menu_select
#   executed  - any shell runs `bash menu.sh`, feeding rows on stdin and
#               reading the chosen index from stdout
#
# The interface is drawn on /dev/tty rather than stdout so a caller may capture
# the result through a pipe while the user still sees the menu.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -o nounset
  set -o pipefail
fi

_god_menu_tty_fd=''
_god_menu_choice=-1

_god_menu_style_init() {
  local locale_name color_mode

  locale_name="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  color_mode="${GOD_COLOR:-auto}"

  case "$locale_name" in
    *UTF-8*|*UTF8*|*utf-8*|*utf8*)
      _god_menu_marker='❯'
      _god_menu_keys='↑/↓ or j/k to move · 1-9 to jump · enter to confirm · esc to cancel'
      ;;
    *)
      _god_menu_marker='>'
      _god_menu_keys='up/down or j/k to move, 1-9 to jump, enter to confirm, esc to cancel'
      ;;
  esac

  _god_menu_reset=''
  _god_menu_bold=''
  _god_menu_dim=''
  _god_menu_accent=''
  _god_menu_warning=''

  if [ -z "${NO_COLOR+x}" ]; then
    if [ "$color_mode" = always ] || {
      [ "$color_mode" != never ] &&
      [ "${TERM:-}" != dumb ] &&
      [ -t 1 ]
    }; then
      _god_menu_reset="$(printf '\033[0m')"
      _god_menu_bold="$(printf '\033[1m')"
      _god_menu_dim="$(printf '\033[2m')"
      _god_menu_accent="$(printf '\033[1;36m')"
      _god_menu_warning="$(printf '\033[1;33m')"
    fi
  fi
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
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  _god_menu_tty_fd=''
}

# Usable width of the terminal. A row wider than this wraps onto a second
# physical line, which breaks the cursor-up redraw and smears the frame, so
# every row is truncated to this value.
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

_god_menu_row_count() {
  printf '%s\n' "$1" | LC_ALL=C awk 'NF || length($0) { count++ } END { print count + 0 }'
}

_god_menu_field() {
  printf '%s\n' "$1" | LC_ALL=C awk -v want="$2" -v field="$3" -F '\t' '
    NR == want { print $field; exit }
  '
}

# Draw one frame. Height is constant so the caller can rewind by a fixed number
# of lines regardless of which row is selected or whether extras are hidden.
_god_menu_draw() {
  local rows visible selected total width label hint danger index style prefix
  local hint_width label_width

  rows=$1
  visible=$2
  selected=$3
  total=$4
  width=$5

  # Titles are the substance and hints are the route, so the hint is capped and
  # the label takes whatever is left rather than the other way round.
  hint_width=22
  label_width=$((width - hint_width - 6))
  [ "$label_width" -ge 20 ] || { label_width=$((width - 6)); hint_width=0; }
  index=1
  while [ "$index" -le "$visible" ]; do
    label="$(_god_menu_field "$rows" "$index" 1)"
    hint="$(_god_menu_field "$rows" "$index" 2)"
    danger="$(_god_menu_field "$rows" "$index" 3)"

    style=$_god_menu_dim
    prefix='   '
    if [ "$index" -eq "$selected" ]; then
      style=$_god_menu_accent
      [ "$danger" = danger ] && style=$_god_menu_warning
      prefix=" $_god_menu_marker "
    fi

    if [ "$hint_width" -gt 0 ]; then
      printf '\r\033[2K%s%s%-*.*s%s %s%-*.*s%s\n' \
        "$style" "$prefix" \
        "$label_width" "$label_width" "$label" "$_god_menu_reset" \
        "$_god_menu_dim" "$hint_width" "$hint_width" "$hint" "$_god_menu_reset" >&3
    else
      printf '\r\033[2K%s%s%-*.*s%s\n' \
        "$style" "$prefix" "$label_width" "$label_width" "$label" "$_god_menu_reset" >&3
    fi
    index=$((index + 1))
  done

  if [ "$total" -gt "$visible" ]; then
    printf '\r\033[2K  %s%s more not shown%s\n' \
      "$_god_menu_dim" "$((total - visible))" "$_god_menu_reset" >&3
  else
    printf '\r\033[2K\n' >&3
  fi
  printf '\r\033[2K  %s%s%s\n' "$_god_menu_dim" "$_god_menu_keys" "$_god_menu_reset" >&3
}

# _god_menu_select ROWS [SELECTED]
#
# ROWS is newline-delimited; each line is LABEL<TAB>HINT<TAB>[danger].
# Sets _god_menu_choice to the 0-based index, or -1 when cancelled.
_god_menu_select() {
  local rows selected total visible width key rest frame

  rows=$1
  selected=${2:-1}
  _god_menu_choice=-1

  total="$(_god_menu_row_count "$rows")"
  [ "$total" -gt 0 ] || return 1

  visible=$total
  [ "$visible" -le 9 ] || visible=9
  [ "$selected" -ge 1 ] || selected=1
  [ "$selected" -le "$visible" ] || selected=1

  _god_menu_open_tty || return 1
  width="$(_god_menu_width)"
  frame=$((visible + 2))

  # A dumb terminal cannot reposition the cursor; list once and read a number.
  if [ "${TERM:-}" = dumb ]; then
    _god_menu_dumb_select "$rows" "$visible" "$total"
    _god_menu_close_tty
    return 0
  fi

  printf '\n' >&3
  while :; do
    _god_menu_draw "$rows" "$visible" "$selected" "$total" "$width"

    IFS= read -r -s -n 1 key <&3 || {
      printf '\n' >&3
      _god_menu_close_tty
      return 0
    }

    case "$key" in
      '')
        _god_menu_choice=$((selected - 1))
        printf '\n' >&3
        _god_menu_close_tty
        return 0
        ;;
      [1-9])
        if [ "$key" -le "$visible" ]; then
          _god_menu_choice=$((key - 1))
          printf '\n' >&3
          _god_menu_close_tty
          return 0
        fi
        continue
        ;;
      k|K) [ "$selected" -gt 1 ] && selected=$((selected - 1)) ;;
      j|J) [ "$selected" -lt "$visible" ] && selected=$((selected + 1)) ;;
      q|Q)
        printf '\n' >&3
        _god_menu_close_tty
        return 0
        ;;
      "$(printf '\033')")
        # Bash 3.2 supports whole-second timeouts only. A bare Escape produces
        # no follow-up bytes, so the timeout is what distinguishes it from an
        # arrow key rather than blocking forever.
        rest=''
        IFS= read -r -s -n 2 -t 1 rest <&3 || rest=''
        case "$rest" in
          '[A') [ "$selected" -gt 1 ] && selected=$((selected - 1)) ;;
          '[B') [ "$selected" -lt "$visible" ] && selected=$((selected + 1)) ;;
          '')
            printf '\n' >&3
            _god_menu_close_tty
            return 0
            ;;
        esac
        ;;
      *) continue ;;
    esac
    printf '\033[%sA' "$frame" >&3
  done
}

_god_menu_dumb_select() {
  local rows visible total index label reply

  rows=$1
  visible=$2
  total=$3

  index=1
  while [ "$index" -le "$visible" ]; do
    label="$(_god_menu_field "$rows" "$index" 1)"
    printf '  %s) %s\n' "$index" "$label" >&3
    index=$((index + 1))
  done
  [ "$total" -le "$visible" ] || printf '  %s more not shown\n' "$((total - visible))" >&3
  printf 'Select 1-%s, or press enter to cancel: ' "$visible" >&3

  IFS= read -r reply <&3 || reply=''
  case "$reply" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ "$reply" -ge 1 ] && [ "$reply" -le "$visible" ] || return 0
  _god_menu_choice=$((reply - 1))
}

# Executed rather than sourced: rows arrive on stdin, the chosen index leaves on
# stdout. Exit status 0 means a selection was made, 1 means cancelled or no
# terminal was available.
_god_menu_main() {
  local rows selected

  selected=${1:-1}
  rows="$(command cat)"
  _god_menu_style_init
  _god_menu_select "$rows" "$selected" || return 1
  [ "$_god_menu_choice" -ge 0 ] || return 1
  printf '%s\n' "$_god_menu_choice"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _god_menu_main "$@"
fi
