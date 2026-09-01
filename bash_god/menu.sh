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
      _god_menu_top_left='╭'
      _god_menu_top_right='╮'
      _god_menu_bottom_left='╰'
      _god_menu_bottom_right='╯'
      _god_menu_vertical='│'
      _god_menu_horizontal='─'
      _god_menu_marker='❯'
      _god_menu_keys='↑/↓ or j/k to move · 1-9 to jump · enter to confirm · esc to cancel'
      _god_menu_keys_rich='↑/↓ move · e edit · enter run · esc cancel'
      _god_menu_keys_rich_unavailable='↑/↓ move · unavailable for detected version · esc cancel'
      ;;
    *)
      _god_menu_top_left='+'
      _god_menu_top_right='+'
      _god_menu_bottom_left='+'
      _god_menu_bottom_right='+'
      _god_menu_vertical='|'
      _god_menu_horizontal='-'
      _god_menu_marker='>'
      _god_menu_keys='up/down or j/k to move, 1-9 to jump, enter to confirm, esc to cancel'
      _god_menu_keys_rich='up/down move, e edit, enter run, esc cancel'
      _god_menu_keys_rich_unavailable='up/down move, unavailable for detected version, esc cancel'
      ;;
  esac

  _god_menu_reset=''
  _god_menu_bold=''
  _god_menu_dim=''
  _god_menu_brand=''
  _god_menu_accent=''
  _god_menu_command=''
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
      _god_menu_brand="$(printf '\033[1;35m')"
      _god_menu_accent="$(printf '\033[1;36m')"
      _god_menu_command="$(printf '\033[32m')"
      _god_menu_warning="$(printf '\033[1;33m')"
    fi
  fi

  # When the picker is sourced by BASH_GOD, inherit the already-initialized
  # product theme exactly. Keeping a second set of nominally identical ANSI
  # values here caused subtle header colour drift across terminal emulators.
  if [ -n "${_GOD_RESET+x}" ]; then
    _god_menu_reset=$_GOD_RESET
    _god_menu_bold=$_GOD_BOLD
    _god_menu_dim=$_GOD_DIM
    _god_menu_brand=$_GOD_BRAND
    _god_menu_accent=$_GOD_ACCENT
    _god_menu_command=$_GOD_COMMAND
    _god_menu_warning=$_GOD_WARNING
    _god_menu_top_left=$_GOD_TOP_LEFT
    _god_menu_top_right=$_GOD_TOP_RIGHT
    _god_menu_bottom_left=$_GOD_BOTTOM_LEFT
    _god_menu_bottom_right=$_GOD_BOTTOM_RIGHT
    _god_menu_vertical=$_GOD_VERTICAL
    _god_menu_horizontal=$_GOD_HORIZONTAL
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
  local rows wanted wanted_field line row_index field_index tab rest

  rows=$1
  wanted=$2
  wanted_field=$3
  tab="$(printf '\t')"
  row_index=0
  while IFS= read -r line; do
    row_index=$((row_index + 1))
    [ "$row_index" -eq "$wanted" ] || continue
    rest=$line
    field_index=1
    while [ "$field_index" -lt "$wanted_field" ]; do
      case "$rest" in
        *"$tab"*) rest=${rest#*"$tab"} ;;
        *) rest=''; break ;;
      esac
      field_index=$((field_index + 1))
    done
    case "$rest" in
      *"$tab"*) printf '%s\n' "${rest%%"$tab"*}" ;;
      *) printf '%s\n' "$rest" ;;
    esac
    return 0
  done <<< "$rows"
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

# ---------------------------------------------------------------------------
# Rich picker: a single interactive search result view for an already-resolved
# service. The highlighted operation owns the detail panel; the other rows stay
# deliberately quiet so a long absolute command never turns the picker into a
# clipped second table.
# ---------------------------------------------------------------------------

_god_menu_tty_available() {
  _god_menu_open_tty || return 1
  _god_menu_close_tty
}

# The rich picker deliberately stays in the caller's terminal buffer.  An
# alternate screen makes a command-picker feel like a separate program and,
# worse, makes a later placeholder question appear to jump back to another
# screen.  We draw the static header/list once, then redraw only the two rows
# whose selection changed and the fixed detail region below them.
_god_menu_rich_cursor_available() {
  local sc rc el cuu civis cnorm

  command -v tput >/dev/null 2>&1 || return 1
  # Bash 3.2 cannot make the ESC-vs-arrow distinction with a sub-second
  # `read -t`, so the inline picker needs the tiny select-based tail reader.
  command -v perl >/dev/null 2>&1 || return 1
  sc="$(tput sc 2>/dev/null)" || return 1
  rc="$(tput rc 2>/dev/null)" || return 1
  el="$(tput el 2>/dev/null)" || return 1
  cuu="$(tput cuu1 2>/dev/null)" || return 1
  civis="$(tput civis 2>/dev/null)" || return 1
  cnorm="$(tput cnorm 2>/dev/null)" || return 1
  [ -n "$sc" ] && [ -n "$rc" ] && [ -n "$el" ] && [ -n "$cuu" ] && \
    [ -n "$civis" ] && [ -n "$cnorm" ]
}

# Rich mode has a deliberately higher terminal-width floor than the compact
# static table.  If there is not enough room to reserve a safe command panel,
# the caller keeps the established MATCHING OPERATIONS fallback instead.
_god_menu_rich_available() {
  local size height width

  _god_menu_tty_available || return 1
  _god_menu_rich_cursor_available || return 1
  _god_menu_open_tty || return 1
  size="$(stty size <&3 2>/dev/null)" || size=''
  height="${size%% *}"
  width="${size##* }"
  _god_menu_close_tty
  case "$height" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$width" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$height" -ge 18 ] && [ "$width" -ge 60 ]
}

_god_menu_rich_cursor_start() {
  _god_menu_rich_sc="$(tput sc 2>/dev/null)" || return 1
  _god_menu_rich_rc="$(tput rc 2>/dev/null)" || return 1
  _god_menu_rich_el="$(tput el 2>/dev/null)" || return 1
  _god_menu_rich_cuu1="$(tput cuu1 2>/dev/null)" || return 1
  [ -n "$_god_menu_rich_sc" ] && [ -n "$_god_menu_rich_rc" ] && \
    [ -n "$_god_menu_rich_el" ] && [ -n "$_god_menu_rich_cuu1" ] || return 1
  _god_menu_rich_civis="$(tput civis 2>/dev/null)" || return 1
  _god_menu_rich_cnorm="$(tput cnorm 2>/dev/null)" || return 1
  _god_menu_rich_tty_state="$(stty -g <&3 2>/dev/null)" || return 1
  [ -n "$_god_menu_rich_civis" ] && [ -n "$_god_menu_rich_cnorm" ] && \
    [ -n "$_god_menu_rich_tty_state" ] || return 1
  stty -icanon -echo min 1 time 0 <&3 2>/dev/null || return 1
  _god_menu_rich_anchor=0
  printf '%s' "$_god_menu_rich_civis" >&3
}

_god_menu_rich_cursor_finish() {
  [ -z "${_god_menu_rich_tty_state:-}" ] || stty "$_god_menu_rich_tty_state" <&3 2>/dev/null || :
  printf '%s' "${_god_menu_rich_cnorm:-}" >&3
  unset _god_menu_rich_sc _god_menu_rich_rc _god_menu_rich_el _god_menu_rich_cuu1
  unset _god_menu_rich_civis _god_menu_rich_cnorm _god_menu_rich_tty_state _god_menu_rich_anchor
}

_god_menu_rich_save_anchor() {
  printf '%s' "$_god_menu_rich_sc" >&3
  _god_menu_rich_anchor=1
}

_god_menu_rich_restore_anchor() {
  [ "${_god_menu_rich_anchor:-0}" = 1 ] || return 1
  printf '%s' "$_god_menu_rich_rc" >&3
}

_god_menu_rich_move_up() {
  local count

  count=$1
  while [ "$count" -gt 0 ]; do
    printf '%s' "$_god_menu_rich_cuu1" >&3
    count=$((count - 1))
  done
}

# Restore the terminal before honoring Ctrl-Z. When the job is foregrounded
# again, the main loop notices the interrupted flag and leaves the picker at a
# clean prompt instead of resuming with a stale cursor anchor.
_god_menu_rich_suspend() {
  _god_menu_rich_cursor_finish
  trap - TSTP
  kill -TSTP "$$" 2>/dev/null || :
  _god_menu_rich_interrupted=1
}

_god_menu_rich_install_traps() {
  _god_menu_rich_saved_int="$(trap -p INT)"
  _god_menu_rich_saved_hup="$(trap -p HUP)"
  _god_menu_rich_saved_term="$(trap -p TERM)"
  _god_menu_rich_saved_tstp="$(trap -p TSTP)"
  _god_menu_rich_saved_winch="$(trap -p WINCH)"
  _god_menu_rich_interrupted=0
  # A resize invalidates the fixed cursor offsets used by this compact inline
  # renderer. Treat it like a quick cancel rather than leave a broken panel on
  # screen. Ctrl-Z restores the cursor before actually suspending the job.
  # Bash restarts a blocking `read` after a trap that merely sets a flag. The
  # explicit return breaks the active key-reader call immediately; its caller
  # then performs the normal cursor, tty-state, descriptor, and trap cleanup.
  trap '_god_menu_rich_interrupted=1; return 130' INT HUP TERM WINCH
  trap '_god_menu_rich_suspend' TSTP
}

_god_menu_rich_restore_traps() {
  if [ -n "${_god_menu_rich_saved_int:-}" ]; then
    eval "$_god_menu_rich_saved_int"
  else
    trap - INT
  fi
  if [ -n "${_god_menu_rich_saved_hup:-}" ]; then
    eval "$_god_menu_rich_saved_hup"
  else
    trap - HUP
  fi
  if [ -n "${_god_menu_rich_saved_term:-}" ]; then
    eval "$_god_menu_rich_saved_term"
  else
    trap - TERM
  fi
  if [ -n "${_god_menu_rich_saved_tstp:-}" ]; then
    eval "$_god_menu_rich_saved_tstp"
  else
    trap - TSTP
  fi
  if [ -n "${_god_menu_rich_saved_winch:-}" ]; then
    eval "$_god_menu_rich_saved_winch"
  else
    trap - WINCH
  fi
  unset _god_menu_rich_saved_int _god_menu_rich_saved_hup _god_menu_rich_saved_term
  unset _god_menu_rich_saved_tstp _god_menu_rich_saved_winch
  unset _god_menu_rich_interrupted
}

_god_menu_rich_cleanup() {
  _god_menu_rich_cursor_finish
  _god_menu_rich_restore_traps
}

_god_menu_nth_line() {
  local rows wanted line index

  rows=$1
  wanted=$2
  index=0
  while IFS= read -r line; do
    index=$((index + 1))
    if [ "$index" -eq "$wanted" ]; then
      printf '%s\n' "$line"
      return 0
    fi
  done <<< "$rows"
}

# Wrap TEXT on word boundaries into exactly LINES rows. Long individual tokens
# still split, so every character of the selected command remains visible.
_god_menu_wrap() {
  printf '%s\n' "$1" | LC_ALL=C awk -v width="$2" -v lines="$3" '
    function emit(value) {
      print value
      emitted++
    }

    {
      word_count = split($0, words, /[[:space:]]+/)
      current = ""
      for (i = 1; i <= word_count; i++) {
        word = words[i]
        if (word == "") continue

        while (length(word) > width) {
          if (current != "") {
            emit(current)
            current = ""
          }
          # Prefer a useful shell-token boundary before hard-cutting a long
          # absolute path, URL, or flag value. Keep the delimiter at the end
          # of the visible line so the next line reads naturally.
          break_at = 0
          for (position = width; position > 1; position--) {
            if (index("/:=?&,_", substr(word, position, 1)) > 0) {
              break_at = position
              break
            }
          }
          if (break_at == 0) break_at = width
          emit(substr(word, 1, break_at))
          word = substr(word, break_at + 1)
        }

        if (current == "") {
          current = word
        } else if (length(current) + 1 + length(word) <= width) {
          current = current " " word
        } else {
          emit(current)
          current = word
        }
      }
    }

    END {
      if (current != "") emit(current)
      if (emitted == 0) emit("")
      while (lines > emitted) emit("")
    }
  '
}

_god_menu_detail_line_count() {
  _god_menu_wrap "$1" "$2" 0 | LC_ALL=C awk 'END { print (NR > 0 ? NR : 1) }'
}

_god_menu_repeat() {
  local character count output

  character=$1
  count=$2
  output=''
  while [ "$count" -gt 0 ]; do
    output="${output}${character}"
    count=$((count - 1))
  done
  printf '%s' "$output"
}

_god_menu_draw_rich_header() {
  local title subtitle width content_width text_width

  title=$1
  subtitle=$2
  width=$3
  content_width=72
  if [ "$((width - 2))" -lt "$content_width" ]; then
    content_width=$((width - 2))
  fi
  [ "$content_width" -ge 20 ] || content_width=20
  text_width=$((content_width - 2))

  printf '%s%s' "$_god_menu_brand" "$_god_menu_top_left" >&3
  _god_menu_repeat "$_god_menu_horizontal" "$content_width" >&3
  printf '%s%s\n' "$_god_menu_top_right" "$_god_menu_reset" >&3
  printf '%s%s%s %-*.*s %s%s\n' \
    "$_god_menu_brand" "$_god_menu_vertical" "$_god_menu_reset$_god_menu_bold" \
    "$text_width" "$text_width" "$title" "$_god_menu_brand$_god_menu_vertical" "$_god_menu_reset" >&3
  [ -z "$subtitle" ] || printf '%s%s%s %-*.*s %s%s\n' \
    "$_god_menu_brand" "$_god_menu_vertical" "$_god_menu_reset$_god_menu_dim" \
    "$text_width" "$text_width" "$subtitle" "$_god_menu_brand$_god_menu_vertical" "$_god_menu_reset" >&3
  printf '%s%s' "$_god_menu_brand" "$_god_menu_bottom_left" >&3
  _god_menu_repeat "$_god_menu_horizontal" "$content_width" >&3
  printf '%s%s\n' "$_god_menu_bottom_right" "$_god_menu_reset" >&3
  printf '\n' >&3
}

_god_menu_draw_rich_row() {
  local rows index selected width label compatibility risk style marker_style prefix risk_width compatibility_width compatibility_label_width label_width

  rows=$1
  index=$2
  selected=$3
  width=$4
  label="$(_god_menu_field "$rows" "$index" 1)"
  compatibility="$(_god_menu_field "$rows" "$index" 2)"
  risk="$(_god_menu_field "$rows" "$index" 3)"
  style=$_god_menu_dim
  marker_style=$_god_menu_dim
  prefix='    '
  if [ "$selected" = 1 ]; then
    style=$_god_menu_accent
    marker_style=$_god_menu_accent
    [ -z "$risk$compatibility" ] || marker_style=$_god_menu_warning
    prefix="  $_god_menu_marker "
  fi

  # Leave two cells unused so neither a truncated title nor a status tag can touch
  # the terminal's autowrap column.
  risk_width=0
  [ -z "$risk" ] || risk_width=$((${#risk} + 3))
  compatibility_width=0
  compatibility_label_width=${#compatibility}
  if [ "$compatibility_label_width" -gt 0 ]; then
    [ "$compatibility_label_width" -le $((width - 4 - risk_width - 2 - 12 - 3)) ] || \
      compatibility_label_width=$((width - 4 - risk_width - 2 - 12 - 3))
    [ "$compatibility_label_width" -ge 8 ] || compatibility_label_width=8
    compatibility_width=$((compatibility_label_width + 3))
  fi
  label_width=$((width - 4 - risk_width - compatibility_width - 2))
  [ "$label_width" -ge 12 ] || label_width=12
  printf '\r%s%s%s%s%s%.*s%s' \
    "${_god_menu_rich_el:-\033[2K}" "$marker_style" "$prefix" "$_god_menu_reset" "$style" \
    "$label_width" "$label" "$_god_menu_reset" >&3
  [ -z "$compatibility" ] || printf ' %s[%.*s]%s' "$_god_menu_warning" "$compatibility_label_width" "$compatibility" "$_god_menu_reset" >&3
  [ -z "$risk" ] || printf ' %s[%s]%s' "$_god_menu_warning" "$risk" "$_god_menu_reset" >&3
  printf '\n' >&3
}

_god_menu_draw_rich_static() {
  local rows visible selected width header_title header_subtitle index

  rows=$1
  visible=$2
  selected=$3
  width=$4
  header_title=${5:-}
  header_subtitle=${6:-}

  if [ -n "$header_title" ]; then
    _god_menu_draw_rich_header "$header_title" "$header_subtitle" "$width"
  else
    printf '\n' >&3
  fi
  index=1
  while [ "$index" -le "$visible" ]; do
    _god_menu_draw_rich_row "$rows" "$index" "$([ "$index" -eq "$selected" ] && printf 1 || printf 0)" "$width"
    index=$((index + 1))
  done
  printf '\n' >&3
}

_god_menu_draw_rich_detail() {
  local rows selected detail width capacity display_mode label compatibility runnable command_width keys_width line index
  local status_width status_label_width label_width keys

  rows=$1
  selected=$2
  detail=$3
  width=$4
  capacity=$5
  # Retain the historic display-mode slot for sourced callers without adding a
  # second variable-height detail section below the command.
  display_mode=${6:-view}
  label="$(_god_menu_field "$rows" "$selected" 1)"
  compatibility="$(_god_menu_field "$rows" "$selected" 2)"
  runnable="$(_god_menu_field "$rows" "$selected" 4)"
  command_width=$((width - 6))
  keys_width=$((width - 4))

  status_width=0
  status_label_width=${#compatibility}
  if [ "$status_label_width" -gt 0 ]; then
    [ "$status_label_width" -le $((keys_width - 12 - 3)) ] || status_label_width=$((keys_width - 12 - 3))
    [ "$status_label_width" -ge 8 ] || status_label_width=8
    status_width=$((status_label_width + 3))
  fi
  label_width=$((keys_width - status_width))
  [ "$label_width" -ge 12 ] || label_width=12
  printf '\r%s  %s%.*s%s' \
    "$_god_menu_rich_el" "$_god_menu_accent" "$label_width" "$label" "$_god_menu_reset" >&3
  [ -z "$compatibility" ] || printf ' %s[%.*s]%s' "$_god_menu_warning" "$status_label_width" "$compatibility" "$_god_menu_reset" >&3
  printf '\n' >&3
  index=1
  while IFS= read -r line; do
    if [ "$index" -eq 1 ]; then
      printf '\r%s  %s$%s %s%s%s\n' \
        "$_god_menu_rich_el" "$_god_menu_command" "$_god_menu_reset" "$_god_menu_command" "$line" "$_god_menu_reset" >&3
    else
      printf '\r%s    %s%s%s\n' \
        "$_god_menu_rich_el" "$_god_menu_command" "$line" "$_god_menu_reset" >&3
    fi
    index=$((index + 1))
  done < <(_god_menu_wrap "$detail" "$command_width" "$capacity")
  if [ "$runnable" = 0 ]; then
    keys=$_god_menu_keys_rich_unavailable
  else
    keys=$_god_menu_keys_rich
  fi
  printf '\r%s  %s%-*.*s%s\n' \
    "$_god_menu_rich_el" "$_god_menu_dim" "$keys_width" "$keys_width" "$keys" "$_god_menu_reset" >&3
}

# Uses the picker state maintained by _god_menu_select_rich. The detail region
# never shrinks during a session; that makes every cursor movement deterministic
# even when a newly selected command wraps to more lines than the last one.
_god_menu_rich_render_current() {
  local detail_lines

  detail_lines="$(_god_menu_detail_line_count "$_god_menu_rich_detail" "$_god_menu_rich_command_width")"
  if [ "$detail_lines" -gt "$_god_menu_rich_capacity" ]; then
    _god_menu_rich_capacity=$detail_lines
  fi
  if [ "${_god_menu_rich_anchor:-0}" = 1 ]; then
    _god_menu_rich_restore_anchor
    _god_menu_rich_move_up "$_god_menu_rich_dynamic_lines"
  fi
  _god_menu_draw_rich_detail \
    "$_god_menu_rich_rows" "$_god_menu_rich_selected" "$_god_menu_rich_detail" \
    "$_god_menu_rich_width" "$_god_menu_rich_capacity" view
  _god_menu_rich_dynamic_lines=$((_god_menu_rich_capacity + 2))
  _god_menu_rich_save_anchor
}

_god_menu_rich_redraw_selection() {
  local old_selected new_selected distance

  old_selected=$1
  new_selected=$2
  [ "$old_selected" -eq "$new_selected" ] && return 0

  _god_menu_rich_restore_anchor
  distance=$((_god_menu_rich_visible + _god_menu_rich_dynamic_lines + 2 - old_selected))
  _god_menu_rich_move_up "$distance"
  _god_menu_draw_rich_row "$_god_menu_rich_rows" "$old_selected" 0 "$_god_menu_rich_width"

  _god_menu_rich_restore_anchor
  distance=$((_god_menu_rich_visible + _god_menu_rich_dynamic_lines + 2 - new_selected))
  _god_menu_rich_move_up "$distance"
  _god_menu_draw_rich_row "$_god_menu_rich_rows" "$new_selected" 1 "$_god_menu_rich_width"
}

# Read one complete keyboard sequence through one reader. Bash 3.2 can buffer
# an arrow tail after its `read -n 1` consumes ESC; handing that tail to a Perl
# child then races and can leave literal "[B" at the caller prompt. Let Perl
# own both the first byte and the optional ESC tail, then return hex so shell
# variables never have to carry a control byte.
_god_menu_rich_read_sequence() {
  perl -MFcntl=F_GETFL,F_SETFL,O_NONBLOCK -MTime::HiRes=time -e '
    my $flags = fcntl(STDIN, F_GETFL, 0);
    my $count = sysread(STDIN, my $first, 1);
    exit 1 unless defined $count && $count == 1;
    # An arrow key is normally delivered atomically, but a busy terminal,
    # serial console, or SSH hop can expose ESC before its tail. Keep reading
    # here so the sequence cannot be split across two input buffers.
    my $deadline = time + 0.25;
    sub read_byte {
      my $remaining = $deadline - time;
      return undef if $remaining <= 0;
      my $ready = q{};
      vec($ready, fileno(STDIN), 1) = 1;
      return undef unless select(my $out = $ready, undef, undef, $remaining);
      fcntl(STDIN, F_SETFL, $flags | O_NONBLOCK);
      my $count = sysread(STDIN, my $byte, 1);
      fcntl(STDIN, F_SETFL, $flags);
      return undef unless defined $count && $count == 1;
      return $byte;
    }
    my $bytes = $first;
    if ($first eq "\e") {
      my $prefix = read_byte();
      if (defined $prefix) {
        $bytes .= $prefix;
        if ($prefix eq q{[}) {
          for (1 .. 14) {
            my $next = read_byte();
            last unless defined $next;
            $bytes .= $next;
            last if $next =~ /[\x40-\x7e]/;
          }
        } elsif ($prefix eq q{O}) {
          my $next = read_byte();
          $bytes .= $next if defined $next;
        }
      }
    }
    print unpack(q{H*}, $bytes);
  ' <&3 2>/dev/null
}

# Normalise the one-reader key sequence into names rather than making every
# picker caller carry terminal escape parsing. A bare Escape cancels in roughly
# 250ms; a delayed arrow tail remains inside the same reader.
_god_menu_rich_read_key() {
  local sequence

  _god_menu_rich_key=''
  sequence="$(_god_menu_rich_read_sequence)" || return 1
  case "$sequence" in
    0a|0d) _god_menu_rich_key=enter ;;
    7f|08) _god_menu_rich_key=backspace ;;
    01) _god_menu_rich_key=home ;;
    05) _god_menu_rich_key=end ;;
    15) _god_menu_rich_key=clear ;;
    17) _god_menu_rich_key=word_backspace ;;
    1b) _god_menu_rich_key=escape ;;
    1b5b41|1b4f41) _god_menu_rich_key=up ;;
    1b5b42|1b4f42) _god_menu_rich_key=down ;;
    1b5b43|1b4f43) _god_menu_rich_key=right ;;
    1b5b44|1b4f44) _god_menu_rich_key=left ;;
    1b5b313b3343|1b5b313b3543|1b5b313b3943|1b5b3543|66) _god_menu_rich_key=word_right ;;
    1b5b313b3344|1b5b313b3544|1b5b313b3944|1b5b3544|62) _god_menu_rich_key=word_left ;;
    1b5b333b337e|1b5b333b357e|64) _god_menu_rich_key=word_delete ;;
    1b5b48|1b5b317e|1b5b377e|1b4f48) _god_menu_rich_key=home ;;
    1b5b46|1b5b347e|1b5b387e|1b4f46) _god_menu_rich_key=end ;;
    1b5b337e) _god_menu_rich_key=delete ;;
    31) _god_menu_rich_key=1 ;;
    32) _god_menu_rich_key=2 ;;
    33) _god_menu_rich_key=3 ;;
    34) _god_menu_rich_key=4 ;;
    35) _god_menu_rich_key=5 ;;
    36) _god_menu_rich_key=6 ;;
    37) _god_menu_rich_key=7 ;;
    38) _god_menu_rich_key=8 ;;
    39) _god_menu_rich_key=9 ;;
    65) _god_menu_rich_key=e ;;
    45) _god_menu_rich_key=E ;;
    6a) _god_menu_rich_key=j ;;
    4a) _god_menu_rich_key=J ;;
    6b) _god_menu_rich_key=k ;;
    4b) _god_menu_rich_key=K ;;
    71) _god_menu_rich_key=q ;;
    51) _god_menu_rich_key=Q ;;
    *) _god_menu_rich_key=unknown ;;
  esac
}

_god_menu_readline_edit() {
  local initial result_file prompt status marker_start marker_end

  initial=$1
  _god_menu_edited_command=''

  result_file="$(mktemp "${TMPDIR:-/tmp}/bash-god-edit.XXXXXX" 2>/dev/null)" || return 1

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
    rm -f "$result_file"
    return "$status"
  fi

  if help read 2>/dev/null | LC_ALL=C grep -q -- '-i'; then
    IFS= read -r -e -i "$initial" -p '  $ ' _god_menu_edited_command <&3 >&3 2>&3
    status=$?
    rm -f "$result_file"
    return "$status"
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    printf '  BASH_GOD: command editing needs zsh, bash read -i, or python3 readline on this terminal.\n' >&3
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
  rm -f "$result_file"
  return "$status"
}

# _god_menu_select_rich ROWS DETAILS [SELECTED] [DETAIL_PROVIDER] [HEADER_TITLE] [HEADER_SUBTITLE] [DETAIL_CACHED]
#
# ROWS is LABEL<TAB>[COMPATIBILITY]<TAB>[RISK]<TAB>RUNNABLE(0/1). RUNNABLE is
# zero only for a per-command compatibility or missing-tool block; catalogs do
# not define a separate non-executable state.
# DETAILS is newline-delimited, line N holding the full command preview for row N.
# DETAIL_PROVIDER is an optional function that receives the 1-based selected
# row and sets _god_menu_provider_detail. It lets a caller lazily produce a
# slow detail panel only when that row is highlighted.
# DETAIL_CACHED is retained for callers using the earlier function shape. Row
# transitions now resolve quickly enough to keep the current detail in place
# for that brief interval and repaint only once, avoiding a transient frame.
# Enter means the operator has reviewed this panel and chooses the row.
_god_menu_select_rich() {
  local rows details selected provider header_title header_subtitle cache_probe total visible width key panel_width detail_status
  local sel_runnable current_detail next_selected old_selected interrupted edit_status

  rows=$1
  details=$2
  selected=${3:-1}
  provider=${4:-}
  header_title=${5:-}
  header_subtitle=${6:-}
  cache_probe=${7:-}
  _god_menu_choice=-1
  _god_menu_edited_command=''

  total="$(_god_menu_row_count "$rows")"
  [ "$total" -gt 0 ] || return 1

  visible=$total
  [ "$visible" -le 9 ] || visible=9
  [ "$selected" -ge 1 ] || selected=1
  [ "$selected" -le "$visible" ] || selected=1

  _god_menu_open_tty || return 2
  width="$(_god_menu_width)"
  [ "$width" -ge 60 ] || { _god_menu_close_tty; return 2; }
  panel_width=$((width - 8))
  [ "$panel_width" -ge 20 ] || panel_width=20

  if [ "${TERM:-}" = dumb ]; then
    _god_menu_dumb_select "$rows" "$visible" "$total"
    _god_menu_close_tty
    return 0
  fi

  _god_menu_rich_install_traps
  _god_menu_rich_cursor_start || {
    _god_menu_rich_cleanup
    _god_menu_close_tty
    return 2
  }

  _god_menu_rich_rows=$rows
  _god_menu_rich_visible=$visible
  _god_menu_rich_selected=$selected
  _god_menu_rich_width=$width
  _god_menu_rich_command_width=$((width - 6))
  if [ -n "$provider" ]; then
    _god_menu_provider_detail=''
    "$provider" "$selected"
    detail_status=$?
    if [ "${_god_menu_rich_interrupted:-0}" = 1 ]; then
      _god_menu_rich_cleanup
      printf '\n' >&3
      _god_menu_close_tty
      return 130
    fi
    if [ "$detail_status" -ne 0 ] || [ -z "${_god_menu_provider_detail:-}" ]; then
      _god_menu_rich_cleanup
      printf '\n  BASH_GOD: unable to resolve the selected command.\n' >&3
      _god_menu_close_tty
      return 3
    fi
    current_detail=$_god_menu_provider_detail
  else
    current_detail="$(_god_menu_nth_line "$details" "$selected")"
  fi
  _god_menu_rich_detail=$current_detail
  _god_menu_rich_capacity="$(_god_menu_detail_line_count "$_god_menu_rich_detail" "$_god_menu_rich_command_width")"
  _god_menu_rich_dynamic_lines=0
  _god_menu_draw_rich_static "$rows" "$visible" "$selected" "$width" "$header_title" "$header_subtitle"
  _god_menu_rich_render_current

  while :; do
    _god_menu_rich_read_key || {
      interrupted=${_god_menu_rich_interrupted:-0}
      _god_menu_rich_cleanup
      printf '\n' >&3
      _god_menu_close_tty
      [ "$interrupted" = 1 ] && return 130
      return 0
    }
    [ "${_god_menu_rich_interrupted:-0}" != 1 ] || {
      interrupted=$_god_menu_rich_interrupted
      _god_menu_rich_cleanup
      printf '\n' >&3
      _god_menu_close_tty
      [ "$interrupted" = 1 ] && return 130
      return 0
    }
    key=$_god_menu_rich_key
    sel_runnable="$(_god_menu_field "$rows" "$selected" 4)"

    case "$key" in
      enter)
        [ "$sel_runnable" = 1 ] || continue
        _god_menu_choice=$((selected - 1))
        _god_menu_edited_command=$current_detail
        _god_menu_rich_cleanup
        printf '\n' >&3
        _god_menu_close_tty
        return 0
        ;;
      e|E)
        [ "$sel_runnable" = 1 ] || continue
        _god_menu_rich_cleanup
        printf '\n' >&3
        _god_menu_readline_edit "$current_detail"
        edit_status=$?
        if [ "$edit_status" -eq 0 ] && [ -n "$_god_menu_edited_command" ]; then
          _god_menu_choice=$((selected - 1))
        fi
        _god_menu_close_tty
        [ "$edit_status" -eq 0 ] || return "$edit_status"
        return 0
        ;;
      [1-9])
        [ "$key" -le "$visible" ] && next_selected=$key || next_selected=$selected
        ;;
      up|k|K) [ "$selected" -gt 1 ] && next_selected=$((selected - 1)) || next_selected=$selected ;;
      down|j|J) [ "$selected" -lt "$visible" ] && next_selected=$((selected + 1)) || next_selected=$selected ;;
      q|Q|escape)
        _god_menu_rich_cleanup
        printf '\n' >&3
        _god_menu_close_tty
        return 0
        ;;
      *) continue ;;
    esac
    [ "$next_selected" -eq "$selected" ] && continue

    old_selected=$selected
    selected=$next_selected
    _god_menu_rich_redraw_selection "$old_selected" "$selected"
    _god_menu_rich_selected=$selected
    # Highlight immediately, keep the existing command panel stable during
    # the short provider lookup, then repaint the detail once. A transient
    # "Resolving…" frame made rapid navigation look like a full refresh.
    if [ -n "$provider" ]; then
      _god_menu_provider_detail=''
      "$provider" "$next_selected"
      detail_status=$?
      if [ "${_god_menu_rich_interrupted:-0}" = 1 ]; then
        _god_menu_rich_cleanup
        printf '\n' >&3
        _god_menu_close_tty
        return 130
      fi
      if [ "$detail_status" -ne 0 ] || [ -z "${_god_menu_provider_detail:-}" ]; then
        _god_menu_rich_cleanup
        printf '\n  BASH_GOD: unable to resolve the selected command.\n' >&3
        _god_menu_close_tty
        return 3
      fi
      current_detail=$_god_menu_provider_detail
    else
      current_detail="$(_god_menu_nth_line "$details" "$next_selected")"
    fi
    _god_menu_rich_detail=$current_detail
    _god_menu_rich_render_current
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
