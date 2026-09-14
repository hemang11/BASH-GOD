#!/usr/bin/env bash

# Real-PTY acceptance checks for a staged, installed BASH_GOD artifact.  This
# suite deliberately uses only fixture-local executables: it never contacts a
# service or invokes a host catalog command.  The package builder produces the
# native helper, the installer verifies its checksum into a temporary prefix,
# and expect drives that installed prefix through a controlling terminal.

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1

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

host_platform() {
  case "$(uname -s):$(uname -m)" in
    Darwin:x86_64|Darwin:amd64) printf '%s\n' darwin-amd64 ;;
    Darwin:arm64|Darwin:aarch64) printf '%s\n' darwin-arm64 ;;
    Linux:x86_64|Linux:amd64) printf '%s\n' linux-amd64 ;;
    Linux:arm64|Linux:aarch64) printf '%s\n' linux-arm64 ;;
    *) return 1 ;;
  esac
}

finish() {
  if [ "$failures" -eq 0 ]; then
    printf '\n%d installed-artifact PTY checks passed.\n' "$checks"
    return 0
  fi
  printf '\n%d of %d installed-artifact PTY checks failed.\n' "$failures" "$checks" >&2
  return 1
}

# R14 is a real-terminal evidence cell.  A missing dependency is not a skip:
# it means this host cannot claim the cell as covered.
if ! command -v go >/dev/null 2>&1; then
  fail 'installed PTY coverage requires Go to build the native release helper'
  finish
  exit 1
fi
if ! command -v expect >/dev/null 2>&1; then
  fail 'installed PTY coverage requires expect for a controlling terminal'
  finish
  exit 1
fi
expect_bin="$(command -v expect)"

platform="$(host_platform)" || {
  fail 'installed PTY coverage requires a host in the declared release target matrix'
  finish
  exit 1
}

version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$repo_dir/src/core.sh")"
protocol="$(LC_ALL=C awk -F= '
  /^_GOD_TUI_PROTOCOL_VERSION=/ {
    count++
    value=$2
    gsub(/[[:space:]]/, "", value)
  }
  END { if (count == 1 && value ~ /^[1-9][0-9]*$/) print value; else exit 1 }
' "$repo_dir/src/ui/tui.sh")" || {
  fail 'package protocol metadata is readable before staging an installed artifact'
  finish
  exit 1
}
case "$version" in
  ''|*[!0-9.]*)
    fail 'package version metadata is readable before staging an installed artifact'
    finish
    exit 1
    ;;
esac

fixture="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-installed-tui-pty.XXXXXX")" || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

assets="$fixture/assets"
prefix="$fixture/prefix"
fake_bin="$fixture/fake-bin"
fake_home="$fixture/home"
fake_log="$fixture/fake.log"
driver="$fixture/installed-driver"
workdir="$fixture/workdir"
manifest="$prefix/lib/bash-god/tui-manifest"
helper="$prefix/libexec/bash-god/god-tui"
mkdir -p "$assets" "$fake_bin" "$fake_home" "$workdir" \
  "$fixture/config" "$fixture/cache" "$fixture/state" "$fixture/data"
: > "$fake_log"

# No catalog operation in this suite can reach a real client.  `curl` is also
# inert so an accidental maintenance/discovery path cannot leave the fixture.
cat > "$fake_bin/curl" <<'CURL_STUB'
#!/usr/bin/env bash
printf 'unexpected-curl|%s\n' "$*" >> "${BASH_GOD_FAKE_LOG:?}"
exit 97
CURL_STUB

# A PATH-visible god-tui must never be used when the installed runtime has a
# valid helper, and must not become a fallback when its manifest is invalid.
cat > "$fake_bin/god-tui" <<'PATH_HELPER'
#!/usr/bin/env bash
printf 'path-helper|%s\n' "$*" >> "${BASH_GOD_FAKE_LOG:?}"
printf '99\n'
exit 0
PATH_HELPER

cat > "$fake_bin/hostname" <<'HOSTNAME_STUB'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

printf 'hostname-pid|%s\n' "$$" >> "${BASH_GOD_FAKE_LOG:?}"
printf 'hostname-argc|%s\n' "$#" >> "$BASH_GOD_FAKE_LOG"
for argument in "$@"; do
  printf 'hostname-arg|%s\n' "$argument" >> "$BASH_GOD_FAKE_LOG"
done

case "${BASH_GOD_FAKE_CASE:-}" in
  handoff)
    printf 'FAKE HOSTNAME STDERR READY\n' >&2
    printf 'FAKE HOSTNAME WAITING FOR INPUT\n'
    IFS= read -r value || exit 71
    printf 'hostname-stdin|%s\n' "$value" >> "$BASH_GOD_FAKE_LOG"
    printf 'FAKE HOSTNAME GOT|%s\n' "$value"
    printf 'FAKE HOSTNAME STDERR COMPLETE\n' >&2
    ;;
  nonzero)
    printf 'FAKE HOSTNAME STDERR READY\n' >&2
    printf 'FAKE HOSTNAME NONZERO\n'
    exit 73
    ;;
  *)
    printf 'FAKE HOSTNAME ARGV'
    for argument in "$@"; do
      printf '|%s' "$argument"
    done
    printf '\n'
    ;;
esac
HOSTNAME_STUB

cat > "$fake_bin/du" <<'DU_STUB'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

printf 'du-pid|%s\n' "$$" >> "${BASH_GOD_FAKE_LOG:?}"
printf 'du-argc|%s\n' "$#" >> "$BASH_GOD_FAKE_LOG"
for argument in "$@"; do
  printf 'du-arg|%s\n' "$argument" >> "$BASH_GOD_FAKE_LOG"
done
printf 'FAKE DU COMPLETE\n'
DU_STUB

cat > "$fixture/bad-helper" <<'BAD_HELPER'
#!/usr/bin/env bash
case "${1:-}" in
  --protocol-version) printf '99\n' ;;
  *) printf 'unexpected private helper invocation\n' >&2; exit 2 ;;
esac
BAD_HELPER

cat > "$driver" <<'INSTALLED_DRIVER'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

# This process starts outside the repository.  The PATH-visible helper is a
# sentinel, so the only route to rich UI is the staged prefix's libexec helper.
#
# Do not use raw `stty -g` as this PTY oracle.  On BSD/macOS, Expect's own
# raw-to-cooked boundary sets the deferred-reprint PENDIN bit after an ESC
# cycle even in a no-BASH_GOD control.  That bit is a harness artifact, not a
# changed usable terminal mode.  Compare every stable stty -a token exactly,
# excluding only pendin/-pendin, so canonical input, echo, signals, flow
# control, output mappings, special characters, and dimensions still restore.
tty_semantics() {
  LC_ALL=C stty -a </dev/tty | LC_ALL=C awk '
    {
      for (index = 1; index <= NF; index++) {
        if ($index == "pendin" || $index == "-pendin") continue
        printf "%s ", $index
      }
    }
  '
}

unset _BASH_GOD_TUI_HELPER_OVERRIDE BASH_GOD_TUI_HELPER BASH_GOD_PROJECT 2>/dev/null || :
cd "${BASH_GOD_WORKDIR:?}"
stty rows 40 columns 100 </dev/tty

tty_before="$(tty_semantics)"
traps_before="$(trap -p INT; trap -p HUP; trap -p TERM)"
status=0
"${BASH_GOD_INSTALLED:?}" general -q "${BASH_GOD_QUERY:?}" || status=$?
tty_after="$(tty_semantics)"
traps_after="$(trap -p INT; trap -p HUP; trap -p TERM)"

printf 'DRIVER STATUS|%s\n' "$status"
if [ "$tty_before" != "$tty_after" ]; then
  printf 'DRIVER TTY SEMANTICS BEFORE|%s\n' "$tty_before"
  printf 'DRIVER TTY SEMANTICS AFTER|%s\n' "$tty_after"
fi
printf 'DRIVER TTY|%s\n' "$([ "$tty_before" = "$tty_after" ] && printf yes || printf no)"
printf 'DRIVER TRAPS|%s\n' "$([ "$traps_before" = "$traps_after" ] && printf yes || printf no)"
exit "$status"
INSTALLED_DRIVER

chmod 0755 "$fake_bin/curl" "$fake_bin/god-tui" "$fake_bin/hostname" \
  "$fake_bin/du" "$fixture/bad-helper" "$driver"

if "$repo_dir/packaging/build-runtime.sh" "$assets" >/dev/null; then
  pass 'local builder creates the current-host native helper artifact'
else
  fail 'local builder creates the current-host native helper artifact'
  finish
  exit 1
fi

archive="$assets/bash-god-$version-$platform.tar.gz"
checksum="$archive.sha256"
install_status=0
HOME="$fake_home" \
XDG_CONFIG_HOME="$fixture/config" \
XDG_CACHE_HOME="$fixture/cache" \
XDG_STATE_HOME="$fixture/state" \
XDG_DATA_HOME="$fixture/data" \
PATH="$fake_bin:/usr/bin:/bin" \
BASH_GOD_FAKE_LOG="$fake_log" \
BASH_GOD_SKIP_INITIAL_RESYNC=1 \
bash "$assets/install-runtime.sh" --prefix "$prefix" "$archive" "$checksum" \
  > "$fixture/install.log" 2>&1 || install_status=$?
expected_manifest="$(printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=%s\nprotocol=%s' \
  "$version" "$platform" "$protocol")"
installed_manifest=''
[ -r "$manifest" ] && installed_manifest="$(command cat "$manifest")"
if [ "$install_status" -eq 0 ] && [ -x "$prefix/bin/god" ] && [ -x "$helper" ] && \
   [ "$installed_manifest" = "$expected_manifest" ] && \
   [ "$("$helper" --protocol-version 2>/dev/null)" = "$protocol" ] && \
   [ "$(GOD_COLOR=never "$prefix/bin/god" --version)" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$version")" ]; then
  pass 'checksum-verified current-host artifact installs offline with its private helper and no Go runtime path'
else
  fail 'checksum-verified current-host artifact installs offline with its private helper and no Go runtime path'
  printf '%s\n' "$(< "$fixture/install.log")" >&2
  finish
  exit 1
fi

# Every spawned run has a fresh fake-only environment.  The test PATH omits
# the repository and Go directories; the absolute installed launcher is the
# only BASH_GOD entry point available to the driver.
export BASH_GOD_INSTALLED="$prefix/bin/god"
export BASH_GOD_WORKDIR="$workdir"
export BASH_GOD_FAKE_LOG="$fake_log"
export HOME="$fake_home"
export XDG_CONFIG_HOME="$fixture/config"
export XDG_CACHE_HOME="$fixture/cache"
export XDG_STATE_HOME="$fixture/state"
export XDG_DATA_HOME="$fixture/data"
export BASH_GOD_SKIP_INITIAL_RESYNC=1
export GOD_NO_UPDATE_CHECK=1
export GOD_COLOR=never
export NO_COLOR=1
export TERM=xterm-256color
export PATH="$fake_bin:/usr/bin:/bin"
export BASH_GOD_DRIVER="$driver"

read_transcript() {
  local file=$1
  if [ -r "$file" ]; then
    command cat "$file"
  fi
}

assert_no_fake_launch() {
  [ ! -s "$fake_log" ]
}

assert_dead_logged_process() {
  local kind pid

  kind=$1
  pid="$(LC_ALL=C awk -F '|' -v kind="$kind" '$1 == kind "-pid" { print $2; exit }' "$fake_log")"
  [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null
}

# Valid installed helper: its detail confirms browse-time rich rendering, and
# Escape must return control without executing either the catalog fake or the
# PATH sentinel helper.
: > "$fake_log"
export BASH_GOD_QUERY='current hostname'
export BASH_GOD_FAKE_CASE='cancel'
export BASH_GOD_TRANSCRIPT="$fixture/cancel.transcript"
cancel_status=0
cancel_output="$("$expect_bin" -c '
  set timeout 12
  log_user 0
  log_file -noappend $env(BASH_GOD_TRANSCRIPT)
  spawn -noecho /bin/bash $env(BASH_GOD_DRIVER)
  expect {
    -re {\$ hostname} { puts "DETAIL hostname" }
    timeout { puts "TIMEOUT initial installed detail"; exit 10 }
    eof { puts "EOF initial installed detail"; exit 11 }
  }
  send -- "\033"
  expect {
    -re {DRIVER STATUS\|0} { puts "CANCEL status" }
    timeout { puts "TIMEOUT cancel status"; exit 12 }
    eof { puts "EOF cancel status"; exit 13 }
  }
  expect {
    -re {DRIVER TTY\|yes} { puts "CANCEL tty" }
    -re {DRIVER TTY\|no} { puts "BAD cancel tty"; puts $expect_out(buffer); exit 14 }
    timeout { puts "TIMEOUT cancel tty"; exit 15 }
    eof { puts "EOF cancel tty"; exit 16 }
  }
  expect {
    -re {DRIVER TRAPS\|yes} { puts "CANCEL traps"; exit 0 }
    -re {DRIVER TRAPS\|no} { puts "BAD cancel traps"; exit 17 }
    timeout { puts "TIMEOUT cancel traps"; exit 18 }
    eof { puts "EOF cancel traps"; exit 19 }
  }
' 2>&1)" || cancel_status=$?
cancel_transcript="$(read_transcript "$BASH_GOD_TRANSCRIPT")"
if [ "$cancel_status" -eq 0 ] && contains "$cancel_output" 'DETAIL hostname' && \
   contains "$cancel_output" 'CANCEL status' && assert_no_fake_launch && \
   ! contains "$cancel_transcript" 'MATCHING OPERATIONS'; then
  pass 'installed private helper browses and Escape cancels with terminal and traps restored'
else
  fail 'installed private helper browses and Escape cancels with terminal and traps restored'
  printf '%s\n%s\n' "$cancel_output" "$cancel_transcript" >&2
fi
unset cancel_status

run_static_mismatch() {
  local label output status transcript

  label=$1
  : > "$fake_log"
  export BASH_GOD_QUERY='current hostname'
  export BASH_GOD_FAKE_CASE='static'
  export BASH_GOD_TRANSCRIPT="$fixture/$label.transcript"
  status=0
  output="$("$expect_bin" -c '
    set timeout 12
    log_user 0
    log_file -noappend $env(BASH_GOD_TRANSCRIPT)
    spawn -noecho /bin/bash $env(BASH_GOD_DRIVER)
    expect {
      -re {MATCHING OPERATIONS} { puts "STATIC operations" }
      timeout { puts "TIMEOUT static operations"; exit 20 }
      eof { puts "EOF static operations"; exit 21 }
    }
    expect {
      -re {DRIVER STATUS\|0} { puts "STATIC status" }
      timeout { puts "TIMEOUT static status"; exit 22 }
      eof { puts "EOF static status"; exit 23 }
    }
    expect {
      -re {DRIVER TTY\|yes} { puts "STATIC tty" }
      -re {DRIVER TTY\|no} { puts "BAD static tty"; exit 24 }
      timeout { puts "TIMEOUT static tty"; exit 25 }
      eof { puts "EOF static tty"; exit 26 }
    }
    expect {
      -re {DRIVER TRAPS\|yes} { puts "STATIC traps"; exit 0 }
      -re {DRIVER TRAPS\|no} { puts "BAD static traps"; exit 27 }
      timeout { puts "TIMEOUT static traps"; exit 28 }
      eof { puts "EOF static traps"; exit 29 }
    }
  ' 2>&1)" || status=$?
  transcript="$(read_transcript "$BASH_GOD_TRANSCRIPT")"
  if [ "$status" -eq 0 ] && contains "$output" 'STATIC operations' && \
     assert_no_fake_launch && ! contains "$transcript" '↑/↓ move'; then
    return 0
  fi
  printf '%s\n%s\n' "$output" "$transcript" >&2
  return 1
}

# An invalid installed manifest is a static, inert path.  In particular it
# must not fall through to the test PATH's arbitrary god-tui sentinel.
good_manifest="$fixture/good-manifest"
cp "$manifest" "$good_manifest"
printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=wrong-target\nprotocol=%s\n' \
  "$version" "$protocol" > "$manifest"
if run_static_mismatch manifest-mismatch; then
  pass 'mismatched installed manifest falls back to inert static output without PATH helper lookup'
else
  fail 'mismatched installed manifest falls back to inert static output without PATH helper lookup'
fi
cp "$good_manifest" "$manifest"

# A helper whose protocol does not match the signed-in manifest is also a
# static path.  The test restores the real staged helper before later actions.
good_helper="$fixture/good-helper"
cp "$helper" "$good_helper"
cp "$fixture/bad-helper" "$helper"
chmod 0755 "$helper"
if run_static_mismatch helper-mismatch; then
  pass 'mismatched private helper falls back to inert static output without PATH helper lookup'
else
  fail 'mismatched private helper falls back to inert static output without PATH helper lookup'
fi
cp "$good_helper" "$helper"
chmod 0755 "$helper"

# EDIT exits the private picker first, then Bash's native editor receives the
# entire prefixed command.  The sequence includes Ctrl-A, a normal arrow, and
# the emacs-style backward-word escape normally generated by Option/Alt-left.
: > "$fake_log"
export BASH_GOD_QUERY='current hostname'
export BASH_GOD_FAKE_CASE='editor'
export BASH_GOD_TRANSCRIPT="$fixture/editor.transcript"
editor_status=0
editor_output="$("$expect_bin" -c '
  set timeout 12
  log_user 0
  log_file -noappend $env(BASH_GOD_TRANSCRIPT)
  spawn -noecho /bin/bash $env(BASH_GOD_DRIVER)
  expect {
    -re {\$ hostname} { puts "EDITOR initial detail" }
    timeout { puts "TIMEOUT editor initial detail"; exit 30 }
    eof { puts "EOF editor initial detail"; exit 31 }
  }
  send -- "e"
  expect {
    -re {\$ hostname} { puts "EDITOR native prompt" }
    timeout { puts "TIMEOUT native editor prompt"; exit 32 }
    eof { puts "EOF native editor prompt"; exit 33 }
  }
  send -- "\001\033\[C\033b\001\013hostname --edited\r"
  expect {
    -re {FAKE HOSTNAME ARGV\|--edited} { puts "EDITOR child argv" }
    timeout { puts "TIMEOUT editor child argv"; exit 34 }
    eof { puts "EOF editor child argv"; exit 35 }
  }
  expect {
    -re {DRIVER STATUS\|0} { puts "EDITOR status" }
    timeout { puts "TIMEOUT editor status"; exit 36 }
    eof { puts "EOF editor status"; exit 37 }
  }
  expect {
    -re {DRIVER TTY\|yes} { puts "EDITOR tty" }
    -re {DRIVER TTY\|no} { puts "BAD editor tty"; puts $expect_out(buffer); exit 38 }
    timeout { puts "TIMEOUT editor tty"; exit 39 }
    eof { puts "EOF editor tty"; exit 40 }
  }
  expect {
    -re {DRIVER TRAPS\|yes} { puts "EDITOR traps"; exit 0 }
    -re {DRIVER TRAPS\|no} { puts "BAD editor traps"; exit 41 }
    timeout { puts "TIMEOUT editor traps"; exit 42 }
    eof { puts "EOF editor traps"; exit 43 }
  }
' 2>&1)" || editor_status=$?
if [ "$editor_status" -eq 0 ] && contains "$editor_output" 'EDITOR native prompt' && \
   contains "$editor_output" 'EDITOR child argv' && \
   [ "$(LC_ALL=C awk -F '|' '$1 == "hostname-pid" { count++ } END { print count + 0 }' "$fake_log")" = 1 ] && \
   LC_ALL=C grep -Fqx 'hostname-argc|1' "$fake_log" && \
   LC_ALL=C grep -Fqx 'hostname-arg|--edited' "$fake_log" && \
   assert_dead_logged_process hostname; then
  pass 'installed picker hands EDIT to the native editor and launches the exact edited fake command once'
else
  fail 'installed picker hands EDIT to the native editor and launches the exact edited fake command once'
  printf '%s\n%s\n' "$editor_output" "$(read_transcript "$BASH_GOD_TRANSCRIPT")" >&2
fi
unset editor_status

# A placeholder stays unresolved while browsing.  After Enter it is prompted
# by Bash, then carried to the fake as one literal positional argument despite
# spaces, an apostrophe, a dollar sign, URL punctuation, and a semicolon.
: > "$fake_log"
export BASH_GOD_QUERY='size of one directory'
export BASH_GOD_FAKE_CASE='prompt'
export BASH_GOD_TRANSCRIPT="$fixture/prompt.transcript"
prompt_status=0
prompt_output="$("$expect_bin" -c '
  set timeout 12
  log_user 0
  log_file -noappend $env(BASH_GOD_TRANSCRIPT)
  spawn -noecho /bin/bash $env(BASH_GOD_DRIVER)
  expect {
    -re {Directory whose total size should be calculated \[<directory>\]:} { puts "EARLY placeholder prompt"; exit 50 }
    -re {\$ du -sh <directory>} { puts "PROMPT detail" }
    timeout { puts "TIMEOUT prompt detail"; exit 51 }
    eof { puts "EOF prompt detail"; exit 52 }
  }
  send -- "\r"
  expect {
    -re {Directory whose total size should be calculated \[<directory>\]:} { puts "PROMPT native prompt" }
    timeout { puts "TIMEOUT native placeholder prompt"; exit 53 }
    eof { puts "EOF native placeholder prompt"; exit 54 }
  }
  send -- "one directory\047s \$dollar; https://example.invalid/a?x=1\r"
  expect {
    -re {FAKE DU COMPLETE} { puts "PROMPT child argv" }
    timeout { puts "TIMEOUT placeholder child argv"; exit 55 }
    eof { puts "EOF placeholder child argv"; exit 56 }
  }
  expect {
    -re {DRIVER STATUS\|0} { puts "PROMPT status" }
    timeout { puts "TIMEOUT placeholder status"; exit 57 }
    eof { puts "EOF placeholder status"; exit 58 }
  }
  expect {
    -re {DRIVER TTY\|yes} { puts "PROMPT tty" }
    -re {DRIVER TTY\|no} { puts "BAD prompt tty"; exit 59 }
    timeout { puts "TIMEOUT prompt tty"; exit 60 }
    eof { puts "EOF prompt tty"; exit 61 }
  }
  expect {
    -re {DRIVER TRAPS\|yes} { puts "PROMPT traps"; exit 0 }
    -re {DRIVER TRAPS\|no} { puts "BAD prompt traps"; exit 62 }
    timeout { puts "TIMEOUT prompt traps"; exit 63 }
    eof { puts "EOF prompt traps"; exit 64 }
  }
' 2>&1)" || prompt_status=$?
expected_placeholder=$'one directory\'s $dollar; https://example.invalid/a?x=1'
if [ "$prompt_status" -eq 0 ] && contains "$prompt_output" 'PROMPT detail' && \
   contains "$prompt_output" 'PROMPT native prompt' && contains "$prompt_output" 'PROMPT child argv' && \
   [ "$(LC_ALL=C awk -F '|' '$1 == "du-pid" { count++ } END { print count + 0 }' "$fake_log")" = 1 ] && \
   LC_ALL=C grep -Fqx 'du-argc|2' "$fake_log" && \
   LC_ALL=C grep -Fqx 'du-arg|-sh' "$fake_log" && \
   LC_ALL=C grep -Fqx "du-arg|$expected_placeholder" "$fake_log" && \
   assert_dead_logged_process du; then
  pass 'installed picker defers placeholders and preserves one adversarial value as an exact fake argument'
else
  fail 'installed picker defers placeholders and preserves one adversarial value as an exact fake argument'
  printf '%s\n%s\n' "$prompt_output" "$(read_transcript "$BASH_GOD_TRANSCRIPT")" >&2
fi
unset prompt_status

# After RUN, the fake child must receive the same live terminal: stderr is
# observed before we supply stdin, then the reply and terminal restoration are
# checked after the child exits.
: > "$fake_log"
export BASH_GOD_QUERY='current hostname'
export BASH_GOD_FAKE_CASE='handoff'
export BASH_GOD_TRANSCRIPT="$fixture/handoff.transcript"
handoff_status=0
handoff_output="$("$expect_bin" -c '
  set timeout 12
  log_user 0
  log_file -noappend $env(BASH_GOD_TRANSCRIPT)
  spawn -noecho /bin/bash $env(BASH_GOD_DRIVER)
  expect {
    -re {\$ hostname} { puts "HANDOFF detail" }
    timeout { puts "TIMEOUT handoff detail"; exit 70 }
    eof { puts "EOF handoff detail"; exit 71 }
  }
  send -- "\r"
  expect {
    -re {FAKE HOSTNAME STDERR READY} { puts "HANDOFF stderr first" }
    timeout { puts "TIMEOUT handoff stderr"; exit 72 }
    eof { puts "EOF handoff stderr"; exit 73 }
  }
  expect {
    -re {FAKE HOSTNAME WAITING FOR INPUT} { puts "HANDOFF waiting" }
    timeout { puts "TIMEOUT handoff waiting"; exit 74 }
    eof { puts "EOF handoff waiting"; exit 75 }
  }
  send -- "terminal-handoff-value\r"
  expect {
    -re {FAKE HOSTNAME GOT\|terminal-handoff-value} { puts "HANDOFF stdin" }
    timeout { puts "TIMEOUT handoff stdin"; exit 76 }
    eof { puts "EOF handoff stdin"; exit 77 }
  }
  expect {
    -re {FAKE HOSTNAME STDERR COMPLETE} { puts "HANDOFF stderr complete" }
    timeout { puts "TIMEOUT handoff completion stderr"; exit 78 }
    eof { puts "EOF handoff completion stderr"; exit 79 }
  }
  expect {
    -re {DRIVER STATUS\|0} { puts "HANDOFF status" }
    timeout { puts "TIMEOUT handoff status"; exit 80 }
    eof { puts "EOF handoff status"; exit 81 }
  }
  expect {
    -re {DRIVER TTY\|yes} { puts "HANDOFF tty" }
    -re {DRIVER TTY\|no} { puts "BAD handoff tty"; exit 82 }
    timeout { puts "TIMEOUT handoff tty"; exit 83 }
    eof { puts "EOF handoff tty"; exit 84 }
  }
  expect {
    -re {DRIVER TRAPS\|yes} { puts "HANDOFF traps"; exit 0 }
    -re {DRIVER TRAPS\|no} { puts "BAD handoff traps"; exit 85 }
    timeout { puts "TIMEOUT handoff traps"; exit 86 }
    eof { puts "EOF handoff traps"; exit 87 }
  }
' 2>&1)" || handoff_status=$?
if [ "$handoff_status" -eq 0 ] && contains "$handoff_output" 'HANDOFF stderr first' && \
   contains "$handoff_output" 'HANDOFF stdin' && \
   LC_ALL=C grep -Fqx 'hostname-stdin|terminal-handoff-value' "$fake_log" && \
   [ "$(LC_ALL=C awk -F '|' '$1 == "hostname-pid" { count++ } END { print count + 0 }' "$fake_log")" = 1 ] && \
   assert_dead_logged_process hostname; then
  pass 'installed RUN hands stderr and stdin directly to one fake child and restores the terminal'
else
  fail 'installed RUN hands stderr and stdin directly to one fake child and restores the terminal'
  printf '%s\n%s\n' "$handoff_output" "$(read_transcript "$BASH_GOD_TRANSCRIPT")" >&2
fi
unset handoff_status

# Nonzero status is not swallowed by the rich handoff.  The fake has no stdin
# dependency here, so this is an exact child-status propagation check.
: > "$fake_log"
export BASH_GOD_QUERY='current hostname'
export BASH_GOD_FAKE_CASE='nonzero'
export BASH_GOD_TRANSCRIPT="$fixture/nonzero.transcript"
nonzero_status=0
nonzero_output="$("$expect_bin" -c '
  set timeout 12
  log_user 0
  log_file -noappend $env(BASH_GOD_TRANSCRIPT)
  spawn -noecho /bin/bash $env(BASH_GOD_DRIVER)
  expect {
    -re {\$ hostname} { puts "NONZERO detail" }
    timeout { puts "TIMEOUT nonzero detail"; exit 90 }
    eof { puts "EOF nonzero detail"; exit 91 }
  }
  send -- "\r"
  expect {
    -re {FAKE HOSTNAME STDERR READY} { puts "NONZERO stderr" }
    timeout { puts "TIMEOUT nonzero stderr"; exit 92 }
    eof { puts "EOF nonzero stderr"; exit 93 }
  }
  expect {
    -re {DRIVER STATUS\|73} { puts "NONZERO status" }
    timeout { puts "TIMEOUT nonzero status"; exit 94 }
    eof { puts "EOF nonzero status"; exit 95 }
  }
  expect {
    -re {DRIVER TTY\|yes} { puts "NONZERO tty" }
    -re {DRIVER TTY\|no} { puts "BAD nonzero tty"; puts $expect_out(buffer); exit 96 }
    timeout { puts "TIMEOUT nonzero tty"; exit 97 }
    eof { puts "EOF nonzero tty"; exit 98 }
  }
  expect {
    -re {DRIVER TRAPS\|yes} { puts "NONZERO traps"; exit 0 }
    -re {DRIVER TRAPS\|no} { puts "BAD nonzero traps"; exit 99 }
    timeout { puts "TIMEOUT nonzero traps"; exit 100 }
    eof { puts "EOF nonzero traps"; exit 101 }
  }
' 2>&1)" || nonzero_status=$?
if [ "$nonzero_status" -eq 0 ] && contains "$nonzero_output" 'NONZERO status' && \
   [ "$(LC_ALL=C awk -F '|' '$1 == "hostname-pid" { count++ } END { print count + 0 }' "$fake_log")" = 1 ] && \
   assert_dead_logged_process hostname; then
  pass 'installed rich handoff preserves a fake child nonzero exit status and terminal restoration'
else
  fail 'installed rich handoff preserves a fake child nonzero exit status and terminal restoration'
  printf '%s\n%s\n' "$nonzero_output" "$(read_transcript "$BASH_GOD_TRANSCRIPT")" >&2
fi
unset nonzero_status

finish
