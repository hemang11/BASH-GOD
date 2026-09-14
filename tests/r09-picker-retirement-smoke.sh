#!/usr/bin/env bash

# Focused R09 retirement checks. This suite is fake-only: it verifies that the
# old rich raw-key picker is gone while basic maintenance selection, native
# editing ownership, shared row parsing, and static search remain safe.

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

fixture=$(mktemp -d /tmp/bash-god-r09-retirement.XXXXXX) || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

input_file=$project_dir/src/ui/input.sh
menu_file=$project_dir/src/ui/menu.sh
fake_bin=$fixture/fake-bin
native_log=$fixture/native.log
mkdir -p "$fake_bin"
: > "$native_log"

legacy_found=0
for legacy_symbol in \
  _god_menu_select_rich \
  _god_menu_rich_ \
  _god_menu_draw_rich_ \
  _god_menu_nth_line \
  _god_menu_wrap \
  _god_menu_detail_line_count \
  _god_menu_repeat; do
  if LC_ALL=C grep -Fq "$legacy_symbol" "$input_file" "$menu_file"; then
    legacy_found=1
  fi
done

if [ "$legacy_found" -eq 0 ] && \
   ! LC_ALL=C grep -Fq 'perl' "$input_file" && \
   ! LC_ALL=C grep -Fq 'tput' "$input_file"; then
  pass 'legacy rich raw-key, redraw, cursor, and Perl dependencies are absent from runtime UI modules'
else
  fail 'legacy rich raw-key, redraw, cursor, and Perl dependencies are absent from runtime UI modules'
fi

runtime_symbols=$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh" || exit 1
  rows=$(printf "First\tone\nSecond\ttwo\n")
  printf "%s|%s|%s|%s|%s\n" \
    "$(type -t _god_menu_readline_edit)" \
    "$(type -t _god_menu_row_count)" \
    "$(type -t _god_menu_field)" \
    "$(_god_menu_row_count "$rows")" \
    "$(_god_menu_field "$rows" 2 1)"
' _ "$project_dir")

if [ "$runtime_symbols" = 'function|function|function|2|Second' ]; then
  pass 'native editor and shared adapter row helpers remain available after retirement'
else
  fail 'native editor and shared adapter row helpers remain available after retirement'
  printf '%s\n' "$runtime_symbols"
fi

basic_selection=$(TERM=dumb GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh" || exit 1
  _god_menu_open_tty() {
    exec 3>/dev/null
    _god_menu_tty_fd=3
  }
  _god_menu_close_tty() {
    { exec 3>&-; } 2>/dev/null || :
    _god_menu_tty_fd=""
  }
  _god_menu_read_reply() {
    _god_menu_reply=2
  }
  rows=$(printf "First maintenance choice\tfirst\nSecond maintenance choice\tsecond\n")
  _god_menu_style_init
  _god_menu_select "$rows" 1 || exit 2
  printf "CHOICE=%s\n" "$_god_menu_choice"
' _ "$project_dir")

if [ "$basic_selection" = 'CHOICE=1' ]; then
  pass 'the helper-independent basic selector remains usable for maintenance'
else
  fail 'the helper-independent basic selector remains usable for maintenance'
  printf '%s\n' "$basic_selection"
fi

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "hostname invoked\n" >> "$BASH_GOD_R09_NATIVE_LOG"' \
  'exit 99' > "$fake_bin/hostname"
chmod 0755 "$fake_bin/hostname"
escape=$(printf '\033')
static_output=$(PATH="$fake_bin:$PATH" \
  BASH_GOD_R09_NATIVE_LOG="$native_log" \
  BASH_GOD_SKIP_INITIAL_RESYNC=1 \
  GOD_COLOR=never TERM=dumb \
  bash "$project_dir/god" general -q 'current hostname' 2>&1)

if contains "$static_output" 'GENERAL SEARCH RESULTS' && \
   contains "$static_output" 'MATCHING OPERATIONS' && \
   contains "$static_output" 'Show the current hostname' && \
   ! contains "$static_output" "$escape" && \
   [ ! -s "$native_log" ]; then
  pass 'missing rich eligibility remains a static non-executing search path'
else
  fail 'missing rich eligibility remains a static non-executing search path'
  printf '%s\n' "$static_output"
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d R09 retirement checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d R09 retirement checks failed.\n' "$failures" "$checks" >&2
exit 1
