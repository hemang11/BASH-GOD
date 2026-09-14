#!/usr/bin/env bash

# End-to-end terminal ownership checks for the optional Go picker. Every
# process below is a fixture: this suite never opens a service connection or
# invokes a catalog command. `expect` gives each driver a controlling PTY, so
# assertions observe the same boundary an SSH user sees rather than mocking
# /dev/tty in-process.

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

fixture="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-tui-pty.XXXXXX")" || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

# CI installs Go as part of the existing helper contract. `expect` is the
# small PTY driver used for this real terminal boundary; without it the
# required R07 coverage is absent, not silently passed as a fake /dev/tty
# substitute.
if ! command -v go >/dev/null 2>&1; then
  fail 'PTY coverage requires the approved Go toolchain'
  printf '\n%d PTY checks passed.\n' "$((checks - failures))"
  exit 1
fi
if ! command -v expect >/dev/null 2>&1; then
  fail 'PTY coverage requires expect'
  printf '\n%d PTY checks passed.\n' "$((checks - failures))"
  exit 1
fi

helper="$fixture/god-tui"
go_build_cache="$fixture/go-build-cache"
# The build cache must be writable because it is transient test output. Keep
# the module cache unchanged: it is the verified dependency source used by the
# repository's normal offline Go checks, and replacing it would force a network
# download during a local PTY test.
mkdir -p "$go_build_cache"
if ! GOTOOLCHAIN=auto GOCACHE="$go_build_cache" \
  go build -o "$helper" ./cmd/god-tui || [ ! -x "$helper" ]; then
  fail 'the temporary terminal helper builds for PTY coverage'
  printf '\n%d PTY checks passed.\n' "$((checks - failures))"
  exit 1
fi

picker_driver="$fixture/picker-driver"
editor_driver="$fixture/editor-driver"
placeholder_driver="$fixture/placeholder-driver"
child_driver="$fixture/child-driver"
fake_child="$fixture/fake-child"

cat > "$picker_driver" <<'PICKER_DRIVER'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

. "$BASH_GOD_PROJECT/BASH_GOD.sh"
export TERM=xterm-256color
export GOD_COLOR=never
export NO_COLOR=1
stty rows 40 columns 100 </dev/tty
_BASH_GOD_TUI_HELPER_OVERRIDE="$BASH_GOD_HELPER"
_god_tui_reset_cache

rows=$'First operation\t\t\t1\t\nSecond operation — 世界\t\t\t1\t\nThird operation\t\tWARN\t1\t'
detail() {
  case "$1" in
    1) _god_menu_provider_detail='printf FIRST-DETAIL' ;;
    2) _god_menu_provider_detail='printf SECOND-DETAIL -- a deliberately long command with unicode 世界 and many reviewed positional arguments one two three four five six seven eight' ;;
    3) _god_menu_provider_detail='printf THIRD-DETAIL' ;;
    *) return 1 ;;
  esac
}

tty_mode() {
  stty -a </dev/tty | LC_ALL=C tr ' ' '\n' | \
    LC_ALL=C awk '/^(icanon|-icanon|echo|-echo|isig|-isig)$/ { printf "%s,", $0 }'
}
before="$(tty_mode)"
result=0
_god_tui_select "$rows" 1 'KAFKA SEARCH RESULTS' 'PTY fixture' detail || result=$?
after="$(tty_mode)"
printf 'PICKER RESULT|%s|%s|%s\n' "$result" "${_god_tui_action:-}" "${_god_tui_index:-}"
printf 'PICKER TTY MODES|%s\n' "$([ "$before" = "$after" ] && printf yes || printf no)"
PICKER_DRIVER

cat > "$editor_driver" <<'EDITOR_DRIVER'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

. "$BASH_GOD_PROJECT/BASH_GOD.sh"
export TERM=xterm-256color
export GOD_COLOR=never
initial='printf suffix-with-a-long-reviewed-command --namespace namespace-with-many-characters --field 世界'
_god_menu_open_tty
tty_mode() {
  stty -a <&3 | LC_ALL=C tr ' ' '\n' | \
    LC_ALL=C awk '/^(icanon|-icanon|echo|-echo|isig|-isig)$/ { printf "%s,", $0 }'
}
before="$(tty_mode)"
result=0
_god_menu_readline_edit "$initial" || result=$?
after="$(tty_mode)"
_god_menu_close_tty
printf 'EDITOR RESULT|%s|%s\n' "$result" "${_god_menu_edited_command:-}"
printf 'EDITOR TTY MODES|%s\n' "$([ "$before" = "$after" ] && printf yes || printf no)"
EDITOR_DRIVER

cat > "$placeholder_driver" <<'PLACEHOLDER_DRIVER'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

. "$BASH_GOD_PROJECT/BASH_GOD.sh"
export TERM=xterm-256color
tty_mode() {
  stty -a </dev/tty | LC_ALL=C tr ' ' '\n' | \
    LC_ALL=C awk '/^(icanon|-icanon|echo|-echo|isig|-isig)$/ { printf "%s,", $0 }'
}
before="$(tty_mode)"
answer="$(_god_resolve_prompt_value 'Namespace to inspect' '<namespace>')"
after="$(tty_mode)"
printf 'PLACEHOLDER RESULT|%s\n' "$answer"
printf 'PLACEHOLDER TTY MODES|%s\n' "$([ "$before" = "$after" ] && printf yes || printf no)"
PLACEHOLDER_DRIVER

cat > "$fake_child" <<'FAKE_CHILD'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

trap 'printf "FAKE CHILD INTERRUPTED\n"; exit 130' INT

printf 'FAKE CHILD STDERR READY\n' >&2
printf 'FAKE CHILD WAITING FOR INPUT\n'
IFS= read -r value || exit 71
printf 'FAKE CHILD GOT|%s\n' "$value"
printf 'FAKE CHILD STDERR COMPLETE\n' >&2
FAKE_CHILD

cat > "$child_driver" <<'CHILD_DRIVER'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

. "$BASH_GOD_PROJECT/BASH_GOD.sh"
export TERM=xterm-256color
# The fake child needs to receive Ctrl-C, while this noninteractive driver
# remains alive long enough to record its exit status and restored terminal.
trap ':' INT
tty_mode() {
  stty -a </dev/tty | LC_ALL=C tr ' ' '\n' | \
    LC_ALL=C awk '/^(icanon|-icanon|echo|-echo|isig|-isig)$/ { printf "%s,", $0 }'
}
before="$(tty_mode)"
result=0
_god_execute_run '"$1"' "$BASH_GOD_FAKE_CHILD" || result=$?
after="$(tty_mode)"
printf 'CHILD RESULT|%s\n' "$result"
printf 'CHILD TTY MODES|%s\n' "$([ "$before" = "$after" ] && printf yes || printf no)"
CHILD_DRIVER

chmod 0755 "$picker_driver" "$editor_driver" "$placeholder_driver" "$child_driver" "$fake_child"

export BASH_GOD_PROJECT="$project_dir"
export BASH_GOD_HELPER="$helper"
export BASH_GOD_FAKE_CHILD="$fake_child"
export PICKER_DRIVER="$picker_driver"
export EDITOR_DRIVER="$editor_driver"
export PLACEHOLDER_DRIVER="$placeholder_driver"
export CHILD_DRIVER="$child_driver"

# The picker must accept multiple complete arrows in one interaction and
# resolve detail lazily. It exits before reporting RUN, letting the parent own
# execution. We use transcript-driven waits, not sleeps.
picker_navigation_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(PICKER_DRIVER)
  expect {
    -re {FIRST-DETAIL} {}
    timeout { puts "TIMEOUT initial detail"; exit 10 }
    eof { puts "EOF initial detail"; exit 11 }
  }
  send -- "\033\[B"
  expect {
    -re {SECOND-DETAIL} {}
    timeout { puts "TIMEOUT second detail"; exit 12 }
    eof { puts "EOF second detail"; exit 13 }
  }
  send -- "\033\[B"
  expect {
    -re {THIRD-DETAIL} {}
    timeout { puts "TIMEOUT third detail"; exit 14 }
    eof { puts "EOF third detail"; exit 15 }
  }
  send -- "\r"
  expect {
    -re {PICKER RESULT\|0\|RUN\|2} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT picker result"; exit 16 }
    eof { puts "EOF picker result"; exit 17 }
  }
  expect {
    -re {PICKER TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {PICKER TTY MODES\|no} { puts $expect_out(buffer); exit 19 }
    timeout { puts "TIMEOUT picker tty"; exit 18 }
    eof { puts "EOF picker tty"; exit 19 }
  }
' 2>&1)" || picker_navigation_status=$?
picker_navigation_status=${picker_navigation_status:-0}
if [ "$picker_navigation_status" -eq 0 ] && \
   contains "$picker_navigation_output" 'PICKER RESULT|0|RUN|2' && \
   contains "$picker_navigation_output" 'PICKER TTY MODES|yes'; then
  pass 'real PTY picker accepts repeated arrows, Unicode/long detail, and Enter with usable terminal modes restored'
else
  fail 'real PTY picker accepts repeated arrows, Unicode/long detail, and Enter with usable terminal modes restored'
  printf '%s\n' "$picker_navigation_output"
fi
unset picker_navigation_status

# EDIT is an independent helper action: it must return the selected reviewed
# row and release browse ownership without converting into RUN or a terminal
# error. The higher-level interaction test below owns the native line editor.
picker_edit_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(PICKER_DRIVER)
  expect {
    -re {FIRST-DETAIL} {}
    timeout { puts "TIMEOUT edit initial detail"; exit 60 }
    eof { puts "EOF edit initial detail"; exit 61 }
  }
  send -- "e"
  expect {
    -re {PICKER RESULT\|0\|EDIT\|0} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT edit picker result"; exit 62 }
    eof { puts "EOF edit picker result"; exit 63 }
  }
  expect {
    -re {PICKER TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {PICKER TTY MODES\|no} { puts $expect_out(buffer); exit 65 }
    timeout { puts "TIMEOUT edit picker tty"; exit 64 }
    eof { puts "EOF edit picker tty"; exit 65 }
  }
' 2>&1)" || picker_edit_status=$?
picker_edit_status=${picker_edit_status:-0}
if [ "$picker_edit_status" -eq 0 ] && \
   contains "$picker_edit_output" 'PICKER RESULT|0|EDIT|0' && \
   contains "$picker_edit_output" 'PICKER TTY MODES|yes'; then
  pass 'real PTY picker returns EDIT for the selected row and restores usable terminal modes'
else
  fail 'real PTY picker returns EDIT for the selected row and restores usable terminal modes'
  printf '%s\n' "$picker_edit_output"
fi
unset picker_edit_status

# Terminal input is a byte stream, especially over SSH. Send a down-arrow as
# adjacent ESC, [, and B writes rather than one complete escape sequence. The
# helper must wait for the sequence rather than interpreting the first ESC as
# cancellation or leaking the tail into the shell.
picker_split_arrow_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(PICKER_DRIVER)
  expect {
    -re {FIRST-DETAIL} {}
    timeout { puts "TIMEOUT split initial detail"; exit 80 }
    eof { puts "EOF split initial detail"; exit 81 }
  }
  send -- "\033"
  send -- "\["
  send -- "B"
  expect {
    -re {SECOND-DETAIL} {}
    timeout { puts "TIMEOUT split second detail"; exit 82 }
    eof { puts "EOF split second detail"; exit 83 }
  }
  send -- "\r"
  expect {
    -re {PICKER RESULT\|0\|RUN\|1} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT split picker result"; exit 84 }
    eof { puts "EOF split picker result"; exit 85 }
  }
  expect {
    -re {PICKER TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {PICKER TTY MODES\|no} { puts $expect_out(buffer); exit 86 }
    timeout { puts "TIMEOUT split picker tty"; exit 87 }
    eof { puts "EOF split picker tty"; exit 88 }
  }
' 2>&1)" || picker_split_arrow_status=$?
picker_split_arrow_status=${picker_split_arrow_status:-0}
if [ "$picker_split_arrow_status" -eq 0 ] && \
   contains "$picker_split_arrow_output" 'PICKER RESULT|0|RUN|1' && \
   contains "$picker_split_arrow_output" 'PICKER TTY MODES|yes'; then
  pass 'real PTY picker accepts a split down-arrow without cancelling or leaking input'
else
  fail 'real PTY picker accepts a split down-arrow without cancelling or leaking input'
  printf '%s\n' "$picker_split_arrow_output"
fi
unset picker_split_arrow_status

# Escape is cancellation rather than a stale partial arrow sequence. It must
# return control to the same TTY immediately and never synthesize RUN/EDIT.
picker_escape_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(PICKER_DRIVER)
  expect {
    -re {FIRST-DETAIL} {}
    timeout { puts "TIMEOUT initial detail"; exit 20 }
  }
  send -- "\033"
  expect {
    -re {PICKER RESULT\|0\|CANCEL\|-1} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT escape result"; exit 21 }
    eof { puts "EOF escape result"; exit 22 }
  }
  expect {
    -re {PICKER TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {PICKER TTY MODES\|no} { puts $expect_out(buffer); exit 24 }
    timeout { puts "TIMEOUT escape tty"; exit 23 }
    eof { puts "EOF escape tty"; exit 24 }
  }
' 2>&1)" || picker_escape_status=$?
picker_escape_status=${picker_escape_status:-0}
if [ "$picker_escape_status" -eq 0 ] && \
   contains "$picker_escape_output" 'PICKER RESULT|0|CANCEL|-1' && \
   contains "$picker_escape_output" 'PICKER TTY MODES|yes'; then
  pass 'Escape cancels the real PTY picker and restores usable terminal modes'
else
  fail 'Escape cancels the real PTY picker and restores usable terminal modes'
  printf '%s\n' "$picker_escape_output"
fi
unset picker_escape_status

# Ctrl-C is deliberately distinct from Escape: it reports the conventional
# interrupt status to the shell, still releases the terminal, and cannot run a
# selected command.
picker_interrupt_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(PICKER_DRIVER)
  expect {
    -re {FIRST-DETAIL} {}
    timeout { puts "TIMEOUT initial detail"; exit 30 }
  }
  send -- "\003"
  expect {
    -re {PICKER RESULT\|130\|CANCEL\|-1} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT interrupt result"; exit 31 }
    eof { puts "EOF interrupt result"; exit 32 }
  }
  expect {
    -re {PICKER TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {PICKER TTY MODES\|no} { puts $expect_out(buffer); exit 34 }
    timeout { puts "TIMEOUT interrupt tty"; exit 33 }
    eof { puts "EOF interrupt tty"; exit 34 }
  }
' 2>&1)" || picker_interrupt_status=$?
picker_interrupt_status=${picker_interrupt_status:-0}
if [ "$picker_interrupt_status" -eq 0 ] && \
   contains "$picker_interrupt_output" 'PICKER RESULT|130|CANCEL|-1' && \
   contains "$picker_interrupt_output" 'PICKER TTY MODES|yes'; then
  pass 'Ctrl-C interrupts the picker promptly and restores usable terminal modes'
else
  fail 'Ctrl-C interrupts the picker promptly and restores usable terminal modes'
  printf '%s\n' "$picker_interrupt_output"
fi
unset picker_interrupt_status

# A resize below the helper's documented minimum is a terminal failure, not a
# partial selection. The adapter must return to the static path without RUN or
# EDIT, and the same TTY must be usable afterwards.
picker_resize_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(PICKER_DRIVER)
  expect {
    -re {FIRST-DETAIL} {}
    timeout { puts "TIMEOUT initial detail"; exit 35 }
    eof { puts "EOF initial detail"; exit 36 }
  }
  exec stty rows 17 columns 39 < $spawn_out(slave,name)
  expect {
    -re {PICKER RESULT\|125\|CANCEL\|-1} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT resize result"; exit 37 }
    eof { puts "EOF resize result"; exit 38 }
  }
  expect {
    -re {PICKER TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {PICKER TTY MODES\|no} { puts $expect_out(buffer); exit 39 }
    timeout { puts "TIMEOUT resize tty"; exit 39 }
    eof { puts "EOF resize tty"; exit 39 }
  }
' 2>&1)" || picker_resize_status=$?
picker_resize_status=${picker_resize_status:-0}
if [ "$picker_resize_status" -eq 0 ] && \
   contains "$picker_resize_output" 'PICKER RESULT|125|CANCEL|-1' && \
   contains "$picker_resize_output" 'PICKER TTY MODES|yes'; then
  pass 'a too-small terminal resize safely falls back without selecting a command'
else
  fail 'a too-small terminal resize safely falls back without selecting a command'
  printf '%s\n' "$picker_resize_output"
fi
unset picker_resize_status

# The native line editor owns the TTY only after the picker is gone. Ctrl-A
# proves this is a normal line-editing session, while the long command proves
# the complete prefilled command survives that handoff.
editor_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(EDITOR_DRIVER)
  expect {
    -re {suffix-with-a-long-reviewed-command} {}
    timeout { puts "TIMEOUT editor prompt"; exit 40 }
    eof { puts "EOF editor prompt"; exit 41 }
  }
  send -- "\001printf prefix; \r"
  expect {
    -re {EDITOR RESULT\|0\|printf prefix; printf suffix-with-a-long-reviewed-command --namespace namespace-with-many-characters --field 世界} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT editor result"; exit 42 }
    eof { puts "EOF editor result"; exit 43 }
  }
  expect {
    -re {EDITOR TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {EDITOR TTY MODES\|no} { puts $expect_out(buffer); exit 45 }
    timeout { puts "TIMEOUT editor tty"; exit 44 }
    eof { puts "EOF editor tty"; exit 45 }
  }
' 2>&1)" || editor_status=$?
editor_status=${editor_status:-0}
if [ "$editor_status" -eq 0 ] && \
   contains "$editor_output" 'EDITOR RESULT|0|printf prefix; printf suffix-with-a-long-reviewed-command' && \
   contains "$editor_output" 'EDITOR TTY MODES|yes'; then
  pass 'native editor receives a complete long command and normal line editing after picker handoff'
else
  fail 'native editor receives a complete long command and normal line editing after picker handoff'
  printf '%s\n' "$editor_output"
fi
unset editor_status

placeholder_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(PLACEHOLDER_DRIVER)
  expect {
    -re {Namespace to inspect \[<namespace>\]:} {}
    timeout { puts "TIMEOUT placeholder prompt"; exit 50 }
    eof { puts "EOF placeholder prompt"; exit 51 }
  }
  send -- "observed-namespace\r"
  expect {
    -re {PLACEHOLDER RESULT\|observed-namespace} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT placeholder result"; exit 52 }
    eof { puts "EOF placeholder result"; exit 53 }
  }
  expect {
    -re {PLACEHOLDER TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {PLACEHOLDER TTY MODES\|no} { puts $expect_out(buffer); exit 55 }
    timeout { puts "TIMEOUT placeholder tty"; exit 54 }
    eof { puts "EOF placeholder tty"; exit 55 }
  }
' 2>&1)" || placeholder_status=$?
placeholder_status=${placeholder_status:-0}
if [ "$placeholder_status" -eq 0 ] && \
   contains "$placeholder_output" 'PLACEHOLDER RESULT|observed-namespace' && \
   contains "$placeholder_output" 'PLACEHOLDER TTY MODES|yes'; then
  pass 'placeholder prompts inherit the terminal after picker ownership ends'
else
  fail 'placeholder prompts inherit the terminal after picker ownership ends'
  printf '%s\n' "$placeholder_output"
fi
unset placeholder_status

# The fake child writes stderr before it waits for input. Seeing that marker
# before supplying a reply proves that the child, not the picker or a pipe,
# owns the live terminal and that stderr is not deferred until process exit.
child_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(CHILD_DRIVER)
  expect {
    -re {FAKE CHILD STDERR READY} {}
    timeout { puts "TIMEOUT child stderr"; exit 60 }
    eof { puts "EOF child stderr"; exit 61 }
  }
  expect {
    -re {FAKE CHILD WAITING FOR INPUT} {}
    timeout { puts "TIMEOUT child input prompt"; exit 62 }
    eof { puts "EOF child input prompt"; exit 63 }
  }
  send -- "terminal-handoff-value\r"
  expect {
    -re {FAKE CHILD GOT\|terminal-handoff-value} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT child reply"; exit 64 }
    eof { puts "EOF child reply"; exit 65 }
  }
  expect {
    -re {FAKE CHILD STDERR COMPLETE} {}
    timeout { puts "TIMEOUT child completion stderr"; exit 66 }
    eof { puts "EOF child completion stderr"; exit 67 }
  }
  expect {
    -re {CHILD RESULT\|0} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT child status"; exit 68 }
    eof { puts "EOF child status"; exit 69 }
  }
  expect {
    -re {CHILD TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {CHILD TTY MODES\|no} { puts $expect_out(buffer); exit 71 }
    timeout { puts "TIMEOUT child tty"; exit 70 }
    eof { puts "EOF child tty"; exit 71 }
  }
' 2>&1)" || child_status=$?
child_status=${child_status:-0}
if [ "$child_status" -eq 0 ] && \
   contains "$child_output" 'FAKE CHILD GOT|terminal-handoff-value' && \
   contains "$child_output" 'CHILD RESULT|0' && \
   contains "$child_output" 'CHILD TTY MODES|yes'; then
  pass 'fake child receives the live terminal and streams stderr before accepting input'
else
  fail 'fake child receives the live terminal and streams stderr before accepting input'
  printf '%s\n' "$child_output"
fi
unset child_status

# Once the helper has exited, Ctrl-C belongs to the native child, not to a
# stale picker reader. The driver deliberately ignores its own copy of INT so
# it can prove the child observed the signal and report terminal restoration.
child_interrupt_output="$(expect -c '
  set timeout 8
  log_user 0
  spawn -noecho /bin/bash $env(CHILD_DRIVER)
  expect {
    -re {FAKE CHILD STDERR READY} {}
    timeout { puts "TIMEOUT interrupt child stderr"; exit 90 }
    eof { puts "EOF interrupt child stderr"; exit 91 }
  }
  expect {
    -re {FAKE CHILD WAITING FOR INPUT} {}
    timeout { puts "TIMEOUT interrupt child input"; exit 92 }
    eof { puts "EOF interrupt child input"; exit 93 }
  }
  send -- "\003"
  expect {
    -re {FAKE CHILD INTERRUPTED} {}
    timeout { puts "TIMEOUT child interrupt marker"; exit 94 }
    eof { puts "EOF child interrupt marker"; exit 95 }
  }
  expect {
    -re {CHILD RESULT\|130} { puts $expect_out(buffer) }
    timeout { puts "TIMEOUT child interrupt status"; exit 96 }
    eof { puts "EOF child interrupt status"; exit 97 }
  }
  expect {
    -re {CHILD TTY MODES\|yes} { puts $expect_out(buffer); exit 0 }
    -re {CHILD TTY MODES\|no} { puts $expect_out(buffer); exit 98 }
    timeout { puts "TIMEOUT child interrupt tty"; exit 99 }
    eof { puts "EOF child interrupt tty"; exit 100 }
  }
' 2>&1)" || child_interrupt_status=$?
child_interrupt_status=${child_interrupt_status:-0}
if [ "$child_interrupt_status" -eq 0 ] && \
   contains "$child_interrupt_output" 'CHILD RESULT|130' && \
   contains "$child_interrupt_output" 'CHILD TTY MODES|yes'; then
  pass 'Ctrl-C reaches the live fake child after picker handoff and restores the terminal'
else
  fail 'Ctrl-C reaches the live fake child after picker handoff and restores the terminal'
  printf '%s\n' "$child_interrupt_output"
fi
unset child_interrupt_status

printf '\n%d PTY checks passed.\n' "$((checks - failures))"
[ "$failures" -eq 0 ]
