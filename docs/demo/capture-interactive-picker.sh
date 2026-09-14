#!/usr/bin/env bash

# Verify the public picker walkthrough with a real PTY and only fixture-local
# executables. The SVG uses the same deliberately small catalog and fake child;
# this script keeps the documentation frame tied to actual picker/editor/prompt
# behavior without reaching a service or depending on a private machine.

set -o nounset
set -o pipefail

script_file=${BASH_SOURCE[0]}
demo_dir="$(CDPATH= cd "$(dirname "$script_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$demo_dir/../.." 2>/dev/null && pwd -P)" || exit 1

die() {
  printf 'BASH_GOD demo: %s\n' "$1" >&2
  exit 1
}

for requirement in go expect; do
  command -v "$requirement" >/dev/null 2>&1 || die "$requirement is required to verify the interactive demo."
done

fixture="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-demo.XXXXXX")" || exit 1
cleanup() {
  if [ "${BASH_GOD_DEMO_KEEP:-0}" = 1 ]; then
    printf 'BASH_GOD demo fixture retained at %s\n' "$fixture" >&2
    return
  fi
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

helper="$fixture/god-tui"
go_build_cache="$fixture/go-build-cache"
catalog_root="$fixture/catalog"
catalog="$catalog_root/demo/service.god"
fake_bin="$fixture/bin"
driver="$fixture/demo-driver"
raw="$fixture/session.raw"
mkdir -p "$go_build_cache" "$(dirname "$catalog")" "$fake_bin" || exit 1

if ! (
  CDPATH= cd "$repo_dir"
  GOTOOLCHAIN=auto GOCACHE="$go_build_cache" go build -o "$helper" ./cmd/god-tui
); then
  die 'could not build the fixture terminal helper.'
fi

printf '%s\n' \
  '@title Demo commands' \
  '' \
  '@description' \
  'A fixture-only executable catalog used to verify the public picker walkthrough.' \
  '' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  'context | execution | local' \
  'shell | local | none' \
  '' \
  '@group inspect' \
  '' \
  '@command Inspect a demo resource' \
  '@mode LOCAL' \
  '@requires' \
  'tool | local:democtl | present' \
  '@description' \
  'Inspects one fixture resource in a namespace.' \
  '@run' \
  'democtl inspect --namespace <namespace>' \
  '@params' \
  '--namespace | <namespace> | Namespace to inspect' \
  '@end' \
  '' \
  '@command Show demo resource status' \
  '@mode LOCAL' \
  '@requires' \
  'tool | local:democtl | present' \
  '@description' \
  'Shows a resource status before an inspection.' \
  '@run' \
  'democtl status --namespace <namespace>' \
  '@params' \
  '--namespace | <namespace> | Namespace to inspect' \
  '@end' > "$catalog"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -o nounset' \
  'set -o pipefail' \
  'case "${1:-}" in' \
  '  inspect)' \
  '    [ "${2:-}" = --namespace ] && [ -n "${3:-}" ] || exit 64' \
  '    printf "NAMESPACE   RESOURCE      STATUS\\n%s  example-api   ready\\n" "$3"' \
  '    ;;' \
  '  status)' \
  '    [ "${2:-}" = --namespace ] && [ -n "${3:-}" ] || exit 64' \
  '    printf "DEMO CHILD STDERR: status query\\n" >&2' \
  '    printf "NAMESPACE   RESOURCE      STATUS\\n%s  example-api   ready\\n" "$3"' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' > "$fake_bin/democtl"
chmod 0755 "$fake_bin/democtl"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -o nounset' \
  'set -o pipefail' \
  '. "$BASH_GOD_DEMO_REPO/BASH_GOD.sh"' \
  'export TERM=xterm-256color' \
  'export GOD_COLOR=never' \
  'export NO_COLOR=1' \
  'export PATH="$BASH_GOD_DEMO_BIN:$PATH"' \
  '_BASH_GOD_CATALOG_DIR=$BASH_GOD_DEMO_CATALOG' \
  '_BASH_GOD_TUI_HELPER_OVERRIDE=$BASH_GOD_DEMO_HELPER' \
  '_god_tui_reset_cache' \
  'stty rows 34 columns 94 </dev/tty' \
  'status=0' \
  'god demo -q "inspect resource" || status=$?' \
  'printf "DEMO DRIVER STATUS|%s\\n" "$status"' \
  'exit "$status"' > "$driver"
chmod 0755 "$driver"

export BASH_GOD_DEMO_REPO="$repo_dir"
export BASH_GOD_DEMO_CATALOG="$catalog_root"
export BASH_GOD_DEMO_HELPER="$helper"
export BASH_GOD_DEMO_BIN="$fake_bin"
export BASH_GOD_DEMO_RAW="$raw"
export BASH_GOD_DEMO_DRIVER="$driver"

expect -c '
  set timeout 10
  log_user 0
  log_file -noappend $env(BASH_GOD_DEMO_RAW)
  spawn -noecho /bin/bash $env(BASH_GOD_DEMO_DRIVER)
  expect {
    -re {esc cancel} {}
    timeout { puts stderr "initial picker frame did not render"; exit 10 }
    eof { puts stderr "picker exited before rendering"; exit 11 }
  }
  send -- "\033\[B"
  # Bubble Tea patches only the changed bytes while the picker remains inline,
  # so this is the second command change. The following native-editor
  # assertion verifies the complete selected command after the helper exits.
  expect {
    -re {status[[:space:]]} {}
    timeout { puts stderr "picker did not redraw the second selected command"; exit 12 }
    eof { puts stderr "picker exited before second selection"; exit 13 }
  }
  send -- "e"
  expect {
    -re {  \$ democtl status --namespace <namespace>} {}
    timeout { puts stderr "native command editor did not receive the selected reviewed command"; exit 14 }
    eof { puts stderr "picker did not release the terminal for native editing"; exit 15 }
  }
  send -- "\r"
  expect {
    -re {Namespace to inspect \[<namespace>\]:} {}
    timeout { puts stderr "placeholder prompt did not follow editor submission"; exit 16 }
    eof { puts stderr "editor did not reach placeholder prompt"; exit 17 }
  }
  send -- "demo-team\r"
  expect {
    -re {DEMO CHILD STDERR: status query} {}
    timeout { puts stderr "fixture native stderr did not reach the terminal"; exit 18 }
    eof { puts stderr "fixture child exited before stderr"; exit 19 }
  }
  expect {
    -re {example-api[[:space:]]+ready} {}
    timeout { puts stderr "fixture native output did not reach the terminal"; exit 20 }
    eof { puts stderr "fixture child exited before output"; exit 21 }
  }
  expect {
    -re {DEMO DRIVER STATUS\|0} {}
    timeout { puts stderr "fixture driver did not report successful completion"; exit 22 }
    eof { puts stderr "fixture driver exited before reporting completion"; exit 23 }
  }
  expect eof
' || die 'fixture walkthrough did not complete.'

printf 'Verified interactive picker walkthrough with fixture-only democtl output.\n'
