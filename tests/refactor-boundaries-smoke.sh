#!/usr/bin/env bash

set -o nounset
set -o pipefail

test_file="${BASH_SOURCE[0]}"
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
project_dir="$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd -P)" || exit 1

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

has_exact_line() {
  printf '%s\n' "$1" | LC_ALL=C grep -Fqx "$2"
}

if [ -f "$project_dir/src/interaction.sh" ] && \
   [ -f "$project_dir/src/ui/input.sh" ] && \
   [ -f "$project_dir/src/ui/tui.sh" ] && \
   ! LC_ALL=C grep -q '^_god_interaction_' "$project_dir/src/search.sh" && \
   ! LC_ALL=C grep -q '^_god_tui_' "$project_dir/src/interaction.sh" && \
   ! LC_ALL=C grep -q '^_god_menu_\(open_tty\|rich_read_sequence\|readline_edit\)()' "$project_dir/src/ui/menu.sh" && \
   ! LC_ALL=C grep -q '_god_resolve_' "$project_dir/src/execute.sh"; then
  pass 'interaction, terminal input, resolution, and execution have dedicated owners'
else
  fail 'interaction, terminal input, resolution, and execution have dedicated owners'
fi

model_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  _god_catalog_command_export() { printf "RUN\tfake-command\nRISK\tWARN\n"; }
  _god_catalog_execution_mode() { printf "PATH\n"; }
  _god_catalog_connection_kind() { printf "NONE\n"; }
  _god_resolve_command() {
    local template
    template="printf '\''%s\\n'\'' \"\$1\" \"\$2\" \"\$3\" \"\$4\" \"\$5\""
    printf "DISPLAY\tprepared display\n"
    printf "TEMPLATE\t%s\n" "$template"
    printf "VALUE\t%s\n" "alpha beta" "O'\''Reilly" "https://host/path?q=\"two words\"&x=1" "\$HOME" "semi;colon | pipe & amp"
  }
  model="$(_god_resolve_reviewed_model demo /fake/catalog group 7 "" query runnable "")" || exit
  printf "%s\n" "$model"
  _god_execute_run() {
    [ "$1" = "printf '\''%s\\n'\'' \"\$1\" \"\$2\" \"\$3\" \"\$4\" \"\$5\"" ] || return 91
    [ "$2" = "alpha beta" ] || return 92
    [ "$3" = "O'\''Reilly" ] || return 93
    [ "$4" = "https://host/path?q=\"two words\"&x=1" ] || return 94
    [ "$5" = "\$HOME" ] || return 95
    [ "$6" = "semi;colon | pipe & amp" ] || return 96
    printf "MODEL RUN OK\n"
  }
  _god_execute_reviewed_model "$model" 1
' _ "$project_dir" 2>&1)"

if has_exact_line "$model_output" $'MODEL\t1' && \
   has_exact_line "$model_output" $'IDENTITY\tdemo\tgroup\t7' && \
   has_exact_line "$model_output" $'CONTEXT\tPATH\tNONE' && \
   has_exact_line "$model_output" $'ELIGIBILITY\trunnable' && \
   has_exact_line "$model_output" $'RISK\tWARN' && \
   has_exact_line "$model_output" $'VALUE\talpha beta' && \
   has_exact_line "$model_output" $'VALUE\tO'\''Reilly' && \
   has_exact_line "$model_output" $'VALUE\thttps://host/path?q="two words"&x=1' && \
   has_exact_line "$model_output" $'VALUE\t$HOME' && \
   has_exact_line "$model_output" $'VALUE\tsemi;colon | pipe & amp' && \
   has_exact_line "$model_output" 'MODEL RUN OK'; then
  pass 'reviewed model preserves identity, context, risk, template, and literal argument values'
else
  fail 'reviewed model preserves identity, context, risk, template, and literal argument values'
  printf '%s\n' "$model_output"
fi

guard_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  launches=0
  _god_execute_run() { launches=$((launches + 1)); }
  blocked=$'"'"'MODEL\t1\nIDENTITY\tdemo\tgroup\t1\nCONTEXT\tPATH\tNONE\nELIGIBILITY\tblocked\nREASON\tmissing tool\nRISK\t\nDISPLAY\tfake\nTEMPLATE\tfake'"'"'
  pending=$'"'"'MODEL\t1\nIDENTITY\tdemo\tgroup\t2\nCONTEXT\tPATH\tNONE\nELIGIBILITY\trunnable\nRISK\t\nDISPLAY\tfake <value>\nTEMPLATE\tfake <value>\nPENDING\tvalue\t<value>\t<value>\tValue'"'"'
  _god_execute_reviewed_model "$blocked" 1
  printf "BLOCKED:%s\n" "$?"
  _god_execute_reviewed_model "$pending" 1
  printf "PENDING:%s\nLAUNCHES:%s\n" "$?" "$launches"
' _ "$project_dir" 2>&1)"

if contains "$guard_output" 'missing tool' && \
   has_exact_line "$guard_output" 'BLOCKED:2' && \
   contains "$guard_output" 'unresolved parameters' && \
   has_exact_line "$guard_output" 'PENDING:2' && \
   has_exact_line "$guard_output" 'LAUNCHES:0'; then
  pass 'reviewed model blocks ineligible and unresolved commands before child launch'
else
  fail 'reviewed model blocks ineligible and unresolved commands before child launch'
  printf '%s\n' "$guard_output"
fi

interaction_result_output="$(GOD_COLOR=never bash -c '
  . "$1/BASH_GOD.sh"
  tab="$(printf "\t")"
  query="demo query"
  models=()
  rich_services=(demo)
  rich_groups=(group)
  rich_entries=(7)
  rich_catalogs=(/fake/catalog)
  rich_execution_paths=(/fake/bin)
  rich_eligibilities=(runnable)
  rich_reasons=("")
  _god_resolve_reviewed_model() {
    printf "MODEL\t1\nIDENTITY\tdemo\tgroup\t7\nCONTEXT\tPATH\tNONE\nELIGIBILITY\trunnable\nRISK\t\nDISPLAY\tfake command\nTEMPLATE\tfake command\n"
  }
  _god_tui_select() {
    "$5" "$2" || return $?
    _god_tui_action=RUN
    _god_tui_index=0
  }
  _god_interaction_select $'"'"'Demo\t\t\t1'"'"' 1 "DEMO" ""
  printf "RUN_RESULT\t%s\t%s\t%s\n" "$_god_interaction_result_version" "$_god_interaction_result_action" "$_god_interaction_result_index"
  printf "RUN_MODEL_BEGIN\n%s\nRUN_MODEL_END\n" "$_god_interaction_result_model"
  _god_tui_select() {
    "$5" "$2" || return $?
    _god_tui_action=CANCEL
    _god_tui_index=-1
  }
  _god_interaction_select $'"'"'Demo\t\t\t1'"'"' 1 "DEMO" ""
  printf "CANCEL_RESULT\t%s\t%s\t%s\n" "$_god_interaction_result_version" "$_god_interaction_result_action" "$_god_interaction_result_index"
' _ "$project_dir" 2>&1)"

if has_exact_line "$interaction_result_output" $'RUN_RESULT\t1\tRUN\t0' && \
   contains "$interaction_result_output" $'IDENTITY\tdemo\tgroup\t7' && \
   contains "$interaction_result_output" 'RUN_MODEL_END' && \
   has_exact_line "$interaction_result_output" $'CANCEL_RESULT\t1\tCANCEL\t-1'; then
  pass 'interaction returns shell-owned run and cancellation results'
else
  fail 'interaction returns shell-owned run and cancellation results'
  printf '%s\n' "$interaction_result_output"
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d refactor-boundary checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d refactor-boundary checks failed.\n' "$failures" "$checks" >&2
exit 1
