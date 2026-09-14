#!/usr/bin/env bash

# R12 regression coverage. Every executable below lives in the temporary
# fixture. The picker and child boundary are stubs: no catalog @run command,
# service probe, SSH call, or network request can reach the host.

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
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

write_lines() {
  local path

  path=$1
  shift
  printf '%s\n' "$@" > "$path"
}

fixture=$(mktemp -d "${TMPDIR:-/tmp}/bash-god-r12.XXXXXX") || exit 1
cleanup() {
  command rm -rf -- "$fixture"
}
trap cleanup EXIT HUP INT TERM

catalog_root=$fixture/catalog
fake_bin=$fixture/fake-bin
system_path=$PATH
mkdir -p "$catalog_root/demo" "$catalog_root/legacy" "$fake_bin" || exit 1

write_lines "$fake_bin/r12-ready" \
  '#!/usr/bin/env bash' \
  'exit 97'
write_lines "$fake_bin/r12-legacy" \
  '#!/usr/bin/env bash' \
  'exit 97'
chmod 0700 "$fake_bin/r12-ready" "$fake_bin/r12-legacy" || exit 1

write_lines "$catalog_root/demo/service.god" \
  '@title R12 schema-one fixture' \
  '@description' \
  'Reviewed eligibility fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@environment 1' \
  'os | local | any' \
  'context | execution | local' \
  'shell | local | none' \
  '@group inspect' \
  '@command Review an eligible local command' \
  '@mode LOCAL' \
  '@requires' \
  'tool | local:r12-ready | present' \
  '@description' \
  'Uses an installed fixture tool.' \
  '@run' \
  'r12-ready inspect eligible' \
  '@end' \
  '@command Review a missing local command' \
  '@mode LOCAL' \
  '@requires' \
  'tool | local:r12-missing | present' \
  '@description' \
  'Requires a deliberately absent fixture tool.' \
  '@run' \
  'r12-missing inspect missing' \
  '@end' \
  '@command Review an unverified remote command' \
  '@mode LOCAL' \
  '@requires' \
  'context | execution | remote' \
  'tool | local:r12-ready | present' \
  'os | remote | linux' \
  'tool | remote:r12-systemctl | present' \
  '@description' \
  'Needs remote facts that BASH_GOD must not probe.' \
  '@run' \
  "r12-ready remote '<host>'" \
  '@end' \
  '@command Choose an older intent variant' \
  '@mode LOCAL' \
  '@since 1.0' \
  '@intent r12-variant' \
  '@requires' \
  'tool | local:r12-ready | present' \
  '@description' \
  'A compatible older reviewed variant.' \
  '@run' \
  'r12-ready inspect older-variant' \
  '@end' \
  '@command Choose a newer intent variant' \
  '@mode LOCAL' \
  '@since 2.0' \
  '@intent r12-variant' \
  '@requires' \
  'tool | local:r12-ready | present' \
  '@description' \
  'A compatible newer reviewed variant.' \
  '@run' \
  'r12-ready inspect newer-variant' \
  '@end' \
  '@command Compare tied intent variant one' \
  '@mode LOCAL' \
  '@since 3.0' \
  '@intent r12-tie' \
  '@requires' \
  'tool | local:r12-ready | present' \
  '@description' \
  'One intentionally tied reviewed variant.' \
  '@run' \
  'r12-ready inspect tied-one' \
  '@end' \
  '@command Compare tied intent variant two' \
  '@mode LOCAL' \
  '@since 3.0' \
  '@intent r12-tie' \
  '@requires' \
  'tool | local:r12-ready | present' \
  '@description' \
  'Another intentionally tied reviewed variant.' \
  '@run' \
  'r12-ready inspect tied-two' \
  '@end'

write_lines "$catalog_root/legacy/service.god" \
  '@title R12 schema-zero fixture' \
  '@description' \
  'Legacy transitional execution fixture.' \
  '@execution PATH' \
  '@connection NONE' \
  '@group inspect' \
  '@command Review a schema-zero command' \
  '@mode LOCAL' \
  '@description' \
  'Retains the current reviewed-picker behavior during migration.' \
  '@run' \
  'r12-legacy inspect legacy' \
  '@end'

# shellcheck source=../BASH_GOD.sh
. "$project_dir/BASH_GOD.sh" || exit 1

_BASH_GOD_CATALOG_DIR=$catalog_root
GOD_COLOR=never
export TERM=xterm-256color
_god_style_init
_god_stdout_is_terminal() { return 0; }
_god_tui_available() { return 0; }

picker_calls=0
picker_log=$fixture/picker.log
picker_mode=cancel
child_calls=0
child_identity=''
: > "$picker_log"

picker_call_count() {
  LC_ALL=C awk '$0 == "CALL" { count++ } END { print count + 0 }' "$picker_log"
}

picker_rows() {
  command cat "$picker_log"
}

_god_tui_select() {
  printf 'CALL\n%s\nEND\n' "$1" >> "$picker_log"
  case "$picker_mode" in
    cancel)
      _god_tui_action=CANCEL
      _god_tui_index=-1
      ;;
    select-second)
      _god_tui_action=RUN
      _god_tui_index=1
      ;;
    remove-then-run)
      command rm -f -- "$fake_bin/r12-ready"
      _god_tui_action=RUN
      _god_tui_index=0
      ;;
    *) return 3 ;;
  esac
}

_god_execute_reviewed_model() {
  local model tab tag a b c

  model=$1
  tab=$(printf '\t')
  child_calls=$((child_calls + 1))
  while IFS="$tab" read -r tag a b c; do
    [ "$tag" = IDENTITY ] || continue
    child_identity="$a/$b/$c"
    break
  done <<< "$model"
}

# A rich search must only send the known-eligible schema-one record to the
# helper. The missing and remote rows remain browse knowledge, not disabled
# or selectable picker rows.
PATH="$fake_bin:$system_path"
picker_mode=cancel
: > "$picker_log"
child_calls=0
search_status=0
_god_search review smart list demo '' 0 > "$fixture/eligible.out" 2>&1 || search_status=$?
captured_rows=$(picker_rows)
picker_calls=$(picker_call_count)
if [ "$search_status" -eq 0 ] && [ "$picker_calls" -eq 1 ] && \
   contains "$captured_rows" 'Review an eligible local command' && \
   ! contains "$captured_rows" 'Review a missing local command' && \
   ! contains "$captured_rows" 'Review an unverified remote command' && \
   [ "$child_calls" -eq 0 ]; then
  pass 'schema-one picker candidates contain only eligible reviewed rows'
else
  fail 'schema-one picker candidates contain only eligible reviewed rows'
  printf '%s\n' "$(command cat "$fixture/eligible.out")" >&2
  printf 'rows:\n%s\n' "$captured_rows" >&2
fi

# A detected service version must not collapse a Schema-1 intent family before
# the shared eligibility filter has an opportunity to retain a viable sibling.
tab=$(printf '\t')
policy_fixture=$(printf '100\t1\tdemo\tinspect\t4\tOlder schema-one variant\tr12-ready old\t\t1.0\t\tr12-versioned\t1\tMODERN\n100\t1\tdemo\tinspect\t5\tNewer schema-one variant\tr12-ready new\t\t2.0\t\tr12-versioned\t1\tMODERN')
policy_output=$(_god_search_apply_policy "$policy_fixture" "$tab" $'demo\t3.0' 0)
policy_count=$(printf '%s\n' "$policy_output" | LC_ALL=C awk 'END { print NR + 0 }')
if [ "$policy_count" -eq 2 ] && \
   contains "$policy_output" 'Older schema-one variant' && \
   contains "$policy_output" 'Newer schema-one variant'; then
  pass 'schema-one intent families survive version policy until eligibility selection'
else
  fail 'schema-one intent families survive version policy until eligibility selection'
  printf '%s\n' "$policy_output" >&2
fi

# Eligible Schema-1 alternatives are evaluated before intent choice. The
# newest unambiguous reviewed variant wins; equal viable variants never get a
# hidden default selection.
PATH="$fake_bin:$system_path"
picker_mode=cancel
: > "$picker_log"
variant_status=0
_god_search variant smart list demo '' 0 > "$fixture/variant.out" 2>&1 || variant_status=$?
variant_rows=$(picker_rows)
variant_calls=$(picker_call_count)
if [ "$variant_status" -eq 0 ] && [ "$variant_calls" -eq 1 ] && \
   contains "$variant_rows" 'Choose a newer intent variant' && \
   ! contains "$variant_rows" 'Choose an older intent variant'; then
  pass 'eligible schema-one intent variants choose the newest reviewed record'
else
  fail 'eligible schema-one intent variants choose the newest reviewed record'
  printf '%s\nrows:\n%s\n' "$(command cat "$fixture/variant.out")" "$variant_rows" >&2
fi

: > "$picker_log"
tied_status=0
_god_search tied smart list demo '' 0 > "$fixture/tied.out" 2>&1 || tied_status=$?
tied_output=$(command cat "$fixture/tied.out")
tied_calls=$(picker_call_count)
if [ "$tied_status" -eq 0 ] && [ "$tied_calls" -eq 0 ] && \
   contains "$tied_output" 'MATCHING OPERATIONS' && \
   contains "$tied_output" 'Compare tied intent variant one' && \
   contains "$tied_output" 'Compare tied intent variant two' && \
   contains "$tied_output" 'No reviewed command is executable in this environment.' && \
   contains "$tied_output" 'several equally compatible reviewed variants are eligible'; then
  pass 'equally eligible schema-one intent variants never receive a hidden default'
else
  fail 'equally eligible schema-one intent variants never receive a hidden default'
  printf '%s\n' "$tied_output" >&2
fi

# Browse views remain complete and do not invoke the helper merely to label a
# requirement state.
: > "$picker_log"
tree_status=0
_god_search review smart tree demo '' 0 > "$fixture/tree.out" 2>&1 || tree_status=$?
tree_output=$(command cat "$fixture/tree.out")
picker_calls=$(picker_call_count)
if [ "$tree_status" -eq 0 ] && [ "$picker_calls" -eq 0 ] && \
   contains "$tree_output" 'Review an eligible local command' && \
   contains "$tree_output" 'Review a missing local command' && \
   contains "$tree_output" 'Review an unverified remote command'; then
  pass 'static browsing retains every schema-one knowledge row without a picker'
else
  fail 'static browsing retains every schema-one knowledge row without a picker'
  printf '%s\n' "$tree_output" >&2
fi

# When no candidate survives, ordinary search still succeeds as knowledge,
# renders its complete static list, and says why no picker was opened.
PATH=$system_path
: > "$picker_log"
no_candidate_status=0
_god_search review smart list demo '' 0 > "$fixture/no-candidate.out" 2>&1 || no_candidate_status=$?
no_candidate_output=$(command cat "$fixture/no-candidate.out")
picker_calls=$(picker_call_count)
if [ "$no_candidate_status" -eq 0 ] && [ "$picker_calls" -eq 0 ] && \
   contains "$no_candidate_output" 'MATCHING OPERATIONS' && \
   contains "$no_candidate_output" 'Review an eligible local command' && \
   contains "$no_candidate_output" 'Review a missing local command' && \
   contains "$no_candidate_output" 'Review an unverified remote command' && \
   contains "$no_candidate_output" 'No reviewed command is executable in this environment.'; then
  pass 'all unavailable candidates fall back to an explained static search result'
else
  fail 'all unavailable candidates fall back to an explained static search result'
  printf '%s\n' "$no_candidate_output" >&2
fi

# Schema zero remains transitional until its full service catalog has reviewed
# requirements metadata. Its candidate index stays aligned with its model.
PATH="$fake_bin:$system_path"
picker_mode=select-second
: > "$picker_log"
child_calls=0
child_identity=''
mixed_status=0
_god_search review smart list '' '' 0 > "$fixture/mixed.out" 2>&1 || mixed_status=$?
captured_rows=$(picker_rows)
picker_calls=$(picker_call_count)
if [ "$mixed_status" -eq 0 ] && [ "$picker_calls" -eq 1 ] && \
   contains "$captured_rows" 'Review an eligible local command' && \
   contains "$captured_rows" 'Review a schema-zero command' && \
   [ "$child_calls" -eq 1 ] && [ "$child_identity" = 'demo/inspect/1' ]; then
  pass 'filtered candidate indices still select the correct cross-service record'
else
  fail 'filtered candidate indices still select the correct cross-service record'
  printf '%s\n' "$(command cat "$fixture/mixed.out")" >&2
  printf 'rows:\n%s\nidentity:%s\n' "$captured_rows" "$child_identity" >&2
fi

# The record can become unavailable after it reached the helper. R12 must
# re-evaluate it before the child boundary rather than run the stale model.
write_lines "$fake_bin/r12-ready" \
  '#!/usr/bin/env bash' \
  'exit 97'
chmod 0700 "$fake_bin/r12-ready" || exit 1
PATH="$fake_bin:$system_path"
picker_mode=remove-then-run
: > "$picker_log"
child_calls=0
recheck_status=0
_god_search 'eligible local' smart list demo '' 0 > "$fixture/recheck.out" 2>&1 || recheck_status=$?
recheck_output=$(command cat "$fixture/recheck.out")
picker_calls=$(picker_call_count)
if [ "$picker_calls" -eq 1 ] && [ "$child_calls" -eq 0 ] && \
   [ "$recheck_status" -eq 2 ] && \
   contains "$recheck_output" 'selected command is no longer executable'; then
  pass 'selection is rechecked before execution and a stale candidate cannot run'
else
  fail 'selection is rechecked before execution and a stale candidate cannot run'
  printf '%s\n' "$recheck_output" >&2
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d R12 eligibility-presentation checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d R12 eligibility-presentation checks failed.\n' "$failures" "$checks" >&2
exit 1
