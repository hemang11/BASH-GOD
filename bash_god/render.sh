# shellcheck shell=bash

# Normal root, service, group, and command rendering for BASH_GOD.

_god_print_available_services() {
  local file service_name found command_count catalog_files

  found=1
  catalog_files="$(_god_catalog_files)" || return 2
  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    found=0
    service_name="$(_god_service_name_for_catalog "$file")" || continue
    command_count="$(LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$file")" || return 2
    printf '  %s%-16s%s %8s   %sgod %s%s\n' \
      "$_GOD_ACCENT" "$service_name" "$_GOD_RESET" "$command_count" \
      "$_GOD_COMMAND" "$service_name" "$_GOD_RESET"
  done <<< "$catalog_files"

  if [ "$found" -ne 0 ]; then
    printf '  (no catalog files found in %s)\n' "$_BASH_GOD_CATALOG_DIR"
  fi
}

_god_print_view_key_rows() {
  printf '  %s%-15s%s %sExplain one displayed row%s\n' "$_GOD_ACCENT" '<number>' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-15s%s %sExpand every command below the current scope%s\n' "$_GOD_ACCENT" '--details' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-15s%s %sShow titles and summaries%s\n' "$_GOD_ACCENT" '--help' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-15s%s %sShow the compact hierarchy%s\n' "$_GOD_ACCENT" '--tree' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-15s%s %sInclude every title and native command line%s\n' "$_GOD_ACCENT" '--tree --full' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-15s%s %sSmart search; use --any, --all, --exact, or --regex%s\n' "$_GOD_ACCENT" 'q | -q' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-15s%s %sHide decorative home artwork; accepted everywhere%s\n' "$_GOD_ACCENT" '--quiet' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
}

_god_print_view_keys() {
  local service group

  service="${1:-}"
  group="${2:-}"
  _god_banner 'VIEW KEYS' 'The same navigation language at every level.'
  _god_section 'KEYS'
  _god_print_view_key_rows

  _god_section 'AT THIS LEVEL'
  if [ -n "$group" ]; then
    printf '  %s%-38s%s %sCopy-ready rows%s\n' "$_GOD_COMMAND" "god $service $group" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sExplain one row%s\n' "$_GOD_COMMAND" "god $service $group <number>" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sExplain every row in this group%s\n' "$_GOD_COMMAND" "god $service $group --details" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sFull branch, including command lines%s\n' "$_GOD_COMMAND" "god $service $group --tree --full" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sSearch only this group%s\n' "$_GOD_COMMAND" "god $service $group q WORDS" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  elif [ -n "$service" ]; then
    printf '  %s%-38s%s %sOpen one group%s\n' "$_GOD_COMMAND" "god $service GROUP" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sExplain every command in this service%s\n' "$_GOD_COMMAND" "god $service --details" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sCompact service tree%s\n' "$_GOD_COMMAND" "god $service --tree" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sFull service, including command lines%s\n' "$_GOD_COMMAND" "god $service --tree --full" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sSearch only this service%s\n' "$_GOD_COMMAND" "god $service q WORDS" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  else
    printf '  %s%-38s%s %sOpen one service%s\n' "$_GOD_COMMAND" 'god SERVICE' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sExplain every catalog command%s\n' "$_GOD_COMMAND" 'god --details' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sSearch every catalog%s\n' "$_GOD_COMMAND" 'god q WORDS' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sSearch help and examples%s\n' "$_GOD_COMMAND" 'god q --help' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
    printf '  %s%-38s%s %sShow BASH_GOD version and license%s\n' "$_GOD_COMMAND" 'god --version' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  fi
}

_god_print_root_help() {
  printf '%sSERVICES%s\n' "$_GOD_BOLD" "$_GOD_RESET"
  printf '%s  %-16s %8s   %s%s\n' "$_GOD_DIM" 'SERVICE' 'COMMANDS' 'OPEN' "$_GOD_RESET"
  printf '%s  %-16s %8s   %s%s\n' "$_GOD_DIM" '----------------' '--------' '------------------------' "$_GOD_RESET"
  _god_print_available_services || return $?

  printf '\n%sQUICK START%s\n' "$_GOD_BOLD" "$_GOD_RESET"
  printf '  %s%-28s%s %sBrowse Kafka groups%s\n' "$_GOD_COMMAND" 'god kafka' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-28s%s %sView copy-ready commands%s\n' "$_GOD_COMMAND" 'god kafka offset' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-28s%s %sExplain one displayed row%s\n' "$_GOD_COMMAND" 'god kafka health <number>' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-28s%s %sFind a command from remembered words%s\n' "$_GOD_COMMAND" 'god q unavailable leader' "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-28s%s %sUse an explicit regular expression%s\n' "$_GOD_COMMAND" "god q --regex 'offset|lag'" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"

  printf '\n%sVIEW KEYS%s\n' "$_GOD_BOLD" "$_GOD_RESET"
  _god_print_view_key_rows

  printf '\n%s  Case-insensitive and display-only. Replace <placeholders> before copying.%s\n' "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  Keys: %sgod --keys%s%s    Version: %sgod --version%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_COMMAND" "$_GOD_RESET"
}


_god_print_service_help() {
  local catalog service banner_title group_count command_count counts

  catalog="$1"
  service="$2"
  banner_title="$(_god_upper "$service") COMMANDS"
  counts="$(LC_ALL=C awk '
    /^@group[[:space:]]+/ { groups++ }
    /^@command[[:space:]]+/ { commands++ }
    END { print groups + 0, commands + 0 }
  ' "$catalog")" || return 2
  group_count="${counts%% *}"
  command_count="${counts#* }"

  _god_banner "$banner_title" "$command_count commands across $group_count groups - curated, searchable, never executed."
  _god_section 'GROUP MAP'
  printf '%s  %-32s %5s  %s%s\n' "$_GOD_DIM" 'OPEN' 'COUNT' 'START WITH' "$_GOD_RESET"
  printf '%s  %-32s %5s  %s%s\n' "$_GOD_DIM" '--------------------------------' '-----' '----------------------------------------' "$_GOD_RESET"

  LC_ALL=C awk -v service="$service" -v command_color="$_GOD_COMMAND" -v bold="$_GOD_BOLD" -v dim="$_GOD_DIM" -v reset="$_GOD_RESET" '
    function flush_group(more) {
      if (current == "") return
      more = current_count - 1
      route = "god " service " " current
      printf "  %s%-32s%s %5d  %s%s%s", command_color, route, reset, current_count, bold, first_title, reset
      if (more > 0) printf " %s+%d more%s", dim, more, reset
      print ""
      groups++
      total += current_count
    }

    /^@group[[:space:]]+/ {
      flush_group()
      name = $0
      sub(/^@group[[:space:]]+/, "", name)
      current = name
      current_count = 0
      first_title = ""
      next
    }

    /^@command[[:space:]]+/ {
      title = $0
      sub(/^@command[[:space:]]+/, "", title)
      current_count++
      if (first_title == "") first_title = title
      next
    }

    END {
      flush_group()
      printf "\n  %-32s %d groups / %d operations\n", "TOTAL", groups, total
    }
  ' "$catalog" || return 2

  printf '\n%s  Run an OPEN route for copy-ready native commands.%s\n' "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  Tree: %sgod %s --tree%s %s(add --full only when needed)%s\n' \
    "$_GOD_DIM" "$_GOD_COMMAND" "$service" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  Full explanations: %sgod %s --details%s %s(or add GROUP to narrow)%s\n' \
    "$_GOD_DIM" "$_GOD_COMMAND" "$service" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  Search here: %sgod %s q WORDS%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "$service" "$_GOD_RESET"
  if LC_ALL=C awk '$0 == "@mode LEGACY-ZK" { found = 1 } END { exit(found ? 0 : 1) }' "$catalog"; then
    printf '%s  Badge: %s[LEGACY]%s%s = older/ZooKeeper-era syntax; unmarked = normal.%s\n' \
      "$_GOD_DIM" "$_GOD_WARNING" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  fi
}

_god_print_group_help() {
  local catalog service group command_count banner_title

  catalog="$1"
  service="$2"
  group="$3"
  command_count="$(_god_group_count "$catalog" "$group")" || return 2
  banner_title="$(_god_upper "$service") / $(_god_upper "$group")"

  _god_banner "$banner_title" "$command_count operations available"
  _god_section 'OPERATIONS'

  LC_ALL=C awk -v wanted="$group" -v bullet="$_GOD_BULLET" -v accent="$_GOD_ACCENT" -v dim="$_GOD_DIM" -v reset="$_GOD_RESET" '
    function print_text(value, prefix, max_width, count, words, i, current, candidate) {
      max_width = 82
      count = split(value, words, /[[:space:]]+/)
      current = ""
      for (i = 1; i <= count; i++) {
        candidate = current (current == "" ? "" : " ") words[i]
        if (current != "" && length(candidate) > max_width) {
          print prefix dim current reset
          current = words[i]
        } else {
          current = candidate
        }
      }
      if (current != "") print prefix dim current reset
    }

    function flush() {
      if (!selected) return
      printf "  %s%s%s  %s\n", accent, bullet, reset, command_title
      if (description != "") print_text(description, "      ")
      print ""
    }

    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      in_wanted_group = tolower(current) == tolower(wanted)
      next
    }

    /^@command[[:space:]]+/ {
      selected = in_wanted_group
      command_title = $0
      sub(/^@command[[:space:]]+/, "", command_title)
      description = ""
      field = ""
      next
    }

    selected && $0 == "@description" { field = "description"; next }
    selected && /^@/ && $0 != "@end" { field = ""; next }

    $0 == "@end" {
      flush()
      selected = 0
      field = ""
      next
    }

    selected && field == "description" && $0 != "" {
      description = description (description == "" ? "" : " ") $0
    }
  ' "$catalog" || return 2

  printf '%s  Open commands:     %s%s%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "god $service $group" "$_GOD_RESET"
  printf '%s  Explain one entry: %s%s <number>%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "god $service $group" "$_GOD_RESET"
  printf '%s  Explain all:       %s%s --details%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "god $service $group" "$_GOD_RESET"
  printf '%s  Search here:       %s%s q WORDS%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "god $service $group" "$_GOD_RESET"
}

_god_print_catalog_entry() {
  local catalog service group entry_index embedded entry_label command_count banner_title banner_subtitle section_title

  catalog="$1"
  service="$2"
  group="$3"
  entry_index="$4"
  embedded="${5:-0}"
  command_count="$(_god_group_count "$catalog" "$group")" || return 2
  if [ "$entry_index" = "all" ]; then
    entry_label="DETAILS"
    banner_subtitle="$command_count commands with descriptions, parameters, optional flags, and notes."
    if [ "$embedded" = "1" ]; then
      section_title="$(_god_upper "$service") / $(_god_upper "$group")"
    else
      section_title="FULL DETAILS"
    fi
  else
    case "$entry_index" in
      ''|*[!0-9]*) return 2 ;;
    esac
    if [ "$entry_index" -lt 1 ] || [ "$entry_index" -gt "$command_count" ]; then
      printf 'BASH_GOD: entry number must be between 1 and %s for %s %s.\n' "$command_count" "$service" "$group" >&2
      return 2
    fi
    entry_label="$(printf '%02d' "$entry_index")"
    banner_subtitle="One command with its description, parameters, optional flags, and notes."
    if [ "$embedded" = "1" ]; then
      section_title="$(_god_upper "$service") / $(_god_upper "$group") / $entry_label"
    else
      section_title="COMMAND"
    fi
  fi
  banner_title="$(_god_upper "$service") / $(_god_upper "$group") / $entry_label"

  if [ "$embedded" != "1" ]; then
    _god_banner "$banner_title" "$banner_subtitle"
  fi
  _god_section "$section_title"

  LC_ALL=C awk \
    -v wanted="$group" \
    -v wanted_index="$entry_index" \
    -v accent="$_GOD_ACCENT" \
    -v bold="$_GOD_BOLD" \
    -v dim="$_GOD_DIM" \
    -v command_color="$_GOD_COMMAND" \
    -v warning_color="$_GOD_WARNING" \
    -v reset="$_GOD_RESET" '
    function append(existing, line) {
      return existing (existing == "" ? "" : separator) line
    }

    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function one_line(value) {
      gsub(separator, " ", value)
      gsub(/[[:space:]]+/, " ", value)
      return trim(value)
    }

    function print_parameter_table(value, heading, count, rows, columns, i, parts) {
      if (value == "") return
      print ""
      printf "      %s%-34s  %-38s  %s%s\n", dim, heading, "EXAMPLE", "MEANING", reset
      printf "      %s%-34s  %-38s  %s%s\n", dim, "----------------------------------", "--------------------------------------", "----------------------------------------", reset
      count = split(value, rows, separator)
      for (i = 1; i <= count; i++) {
        columns = split(rows[i], parts, /\|/)
        if (columns == 3) {
          printf "      %-34s  %-38s  %s\n", trim(parts[1]), trim(parts[2]), trim(parts[3])
        }
      }
    }

    function flush() {
      if (!selected) return
      printf "  %s%02d%s  ", accent, entry_number, reset
      if (mode == "LEGACY-ZK") printf "%s[LEGACY]%s ", warning_color, reset
      printf "%s%s%s", bold, command_title, reset
      if (risk != "") printf "  %s[%s]%s", warning_color, risk, reset
      print ""
      if (description != "") printf "      %s%s%s\n", dim, one_line(description), reset
      printf "      %s$%s %s\n", command_color, reset, run
      print_parameter_table(params, "PARAMETER")
      print_parameter_table(optional, "OPTIONAL")
      if (notes != "") printf "\n      %sNOTE%s  %s\n", dim, reset, one_line(notes)
      print ""
    }

    BEGIN { separator = sprintf("%c", 28) }

    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      in_wanted_group = tolower(current) == tolower(wanted)
      if (in_wanted_group) group_position = 0
      next
    }

    /^@command[[:space:]]+/ {
      if (in_wanted_group) group_position++
      selected = in_wanted_group && (wanted_index == "all" || group_position == wanted_index)
      entry_number = group_position
      command_title = $0
      sub(/^@command[[:space:]]+/, "", command_title)
      mode = risk = description = run = params = optional = notes = ""
      field = ""
      next
    }

    selected && /^@mode[[:space:]]+/ {
      mode = $0
      sub(/^@mode[[:space:]]+/, "", mode)
      field = ""
      next
    }

    selected && /^@risk[[:space:]]+/ {
      risk = $0
      sub(/^@risk[[:space:]]+/, "", risk)
      field = ""
      next
    }

    selected && $0 == "@description" { field = "description"; next }
    selected && $0 == "@run" { field = "run"; next }
    selected && $0 == "@params" { field = "params"; next }
    selected && $0 == "@optional" { field = "optional"; next }
    selected && $0 == "@notes" { field = "notes"; next }

    $0 == "@end" {
      flush()
      selected = 0
      field = ""
      next
    }

    selected && field != "" && $0 != "" {
      if (field == "description") description = append(description, $0)
      else if (field == "run") run = $0
      else if (field == "params") params = append(params, $0)
      else if (field == "optional") optional = append(optional, $0)
      else if (field == "notes") notes = append(notes, $0)
    }
  ' "$catalog" || return 2

  if [ "$embedded" != "1" ]; then
    printf '%s  BACK%s  %sgod %s %s%s\n' "$_GOD_DIM" "$_GOD_RESET" "$_GOD_COMMAND" "$service" "$group" "$_GOD_RESET"
  fi
}

_god_print_service_details() {
  local catalog service embedded command_count groups group

  catalog="$1"
  service="$2"
  embedded="${3:-0}"
  command_count="$(LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$catalog")" || return 2
  groups="$(_god_catalog_group_names "$catalog")" || return 2

  if [ "$embedded" != "1" ]; then
    _god_banner "$(_god_upper "$service") / DETAILS" "$command_count commands with full explanations across every group."
  fi

  while IFS= read -r group; do
    [ -n "$group" ] || continue
    _god_print_catalog_entry "$catalog" "$service" "$group" all 1 || return $?
  done <<< "$groups"

  if [ "$embedded" != "1" ]; then
    printf '%s  BACK%s  %sgod %s%s\n' "$_GOD_DIM" "$_GOD_RESET" "$_GOD_COMMAND" "$service" "$_GOD_RESET"
  fi
}

_god_print_root_details() {
  local catalog_files file service command_count total

  catalog_files="$(_god_catalog_files)" || return 2
  total=0
  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    command_count="$(LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$file")" || return 2
    total=$((total + command_count))
  done <<< "$catalog_files"

  _god_banner 'BASH_GOD / DETAILS' "$total catalog commands with full explanations; nothing is executed."
  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    service="$(_god_service_name_for_catalog "$file")" || return 2
    _god_print_service_details "$file" "$service" 1 || return $?
  done <<< "$catalog_files"

  printf '%s  BACK%s  %sgod%s\n' "$_GOD_DIM" "$_GOD_RESET" "$_GOD_COMMAND" "$_GOD_RESET"
}

_god_print_catalog_compact() {
  local catalog service group command_count banner_title

  catalog="$1"
  service="$2"
  group="$3"
  command_count="$(_god_group_count "$catalog" "$group")" || return 2
  banner_title="$(_god_upper "$service") / $(_god_upper "$group")"

  _god_banner "$banner_title" "$command_count one-line commands - choose a number for parameter meanings"
  _god_section 'COMMANDS'

  LC_ALL=C awk \
    -v wanted="$group" \
    -v accent="$_GOD_ACCENT" \
    -v bold="$_GOD_BOLD" \
    -v dim="$_GOD_DIM" \
    -v command_color="$_GOD_COMMAND" \
    -v warning_color="$_GOD_WARNING" \
    -v reset="$_GOD_RESET" '
    function flush() {
      if (!selected) return
      command_number++
      printf "  %s%02d%s  ", accent, command_number, reset
      if (mode == "LEGACY-ZK") printf "%s[LEGACY]%s ", warning_color, reset
      printf "%s%s%s", bold, command_title, reset
      if (risk != "") printf "  %s[%s]%s", warning_color, risk, reset
      print ""
      printf "      %s$%s %s\n\n", command_color, reset, run
    }

    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      in_wanted_group = tolower(current) == tolower(wanted)
      next
    }

    /^@command[[:space:]]+/ {
      selected = in_wanted_group
      command_title = $0
      sub(/^@command[[:space:]]+/, "", command_title)
      mode = risk = run = ""
      field = ""
      next
    }

    selected && /^@mode[[:space:]]+/ {
      mode = $0
      sub(/^@mode[[:space:]]+/, "", mode)
      field = ""
      next
    }

    selected && /^@risk[[:space:]]+/ {
      risk = $0
      sub(/^@risk[[:space:]]+/, "", risk)
      field = ""
      next
    }

    selected && $0 == "@run" { field = "run"; next }
    selected && /^@/ && $0 != "@end" { field = ""; next }

    $0 == "@end" {
      flush()
      selected = 0
      field = ""
      next
    }

    selected && field == "run" && $0 != "" { run = $0 }
  ' "$catalog" || return 2

  printf '%s  EXPLAIN%s  %sgod %s %s <number>%s    %sExample: god %s %s 1%s\n' \
    "$_GOD_DIM" "$_GOD_RESET" "$_GOD_COMMAND" "$service" "$group" "$_GOD_RESET" \
    "$_GOD_DIM" "$service" "$group" "$_GOD_RESET"
  printf '%s  DETAILS%s  %sgod %s %s --details%s\n' \
    "$_GOD_DIM" "$_GOD_RESET" "$_GOD_COMMAND" "$service" "$group" "$_GOD_RESET"
}
