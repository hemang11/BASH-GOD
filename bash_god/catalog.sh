# shellcheck shell=bash

# Catalog discovery, route resolution, and grammar validation for BASH_GOD.

_god_is_catalog_file() {
  local file_name service_dir service_name

  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  file_name="${1##*/}"
  [ "$file_name" = "service.god" ] || return 1

  service_dir="${1%/*}"
  [ ! -L "$service_dir" ] || return 1
  [ "${service_dir%/*}" = "$_BASH_GOD_CATALOG_DIR" ] || return 1
  service_name="${service_dir##*/}"
  case "$service_name" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
  esac

  return 0
}

_god_service_name_for_catalog() {
  local service_dir

  _god_is_catalog_file "$1" || return 1
  service_dir="${1%/*}"
  printf '%s\n' "${service_dir##*/}"
}

_god_is_route_token() {
  case "$1" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
    *) return 0 ;;
  esac
}

_god_catalog_files() {
  local catalog_files

  if [ ! -d "$_BASH_GOD_CATALOG_DIR" ]; then
    printf 'BASH_GOD: catalog directory is unavailable.\n' >&2
    return 2
  fi

  catalog_files="$(command find "$_BASH_GOD_CATALOG_DIR" -type f -name 'service.god' -print 2>/dev/null)" || {
    printf 'BASH_GOD: could not enumerate the catalog directory.\n' >&2
    return 2
  }

  [ -z "$catalog_files" ] || printf '%s\n' "$catalog_files" | LC_ALL=C sort
}

_god_catalog_for() {
  local requested requested_lower file service_name catalog_files

  requested="$1"
  requested_lower="$(_god_lower "$requested")"
  catalog_files="$(_god_catalog_files)" || return 2

  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    service_name="$(_god_service_name_for_catalog "$file")" || continue
    if [ "$(_god_lower "$service_name")" = "$requested_lower" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  done <<< "$catalog_files"

  return 1
}

_god_group_count() {
  LC_ALL=C awk -v wanted="$2" '
    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      selected = tolower(current) == tolower(wanted)
      next
    }
    selected && /^@command[[:space:]]+/ { count++ }
    END { print count + 0 }
  ' "$1"
}

_god_validate_catalog() {
  LC_ALL=C awk -v catalog="$1" '
    function fail(message) {
      print "BASH_GOD: invalid catalog " catalog ": " message > "/dev/stderr"
      errors++
    }

    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function validate_parameter_row(line, count, parts) {
      count = split(line, parts, /\|/)
      if (count != 3 || trim(parts[1]) == "" || trim(parts[2]) == "" || trim(parts[3]) == "") {
        fail("invalid parameter row on line " NR "; expected NAME | EXAMPLE | MEANING")
      }
    }

    /[[:cntrl:]]/ {
      fail("control character on line " NR)
      next
    }

    /^@title[[:space:]]+/ {
      if (in_command || group_count > 0) fail("@title must appear before all groups")
      if (seen_title) fail("duplicate @title")
      title = $0
      sub(/^@title[[:space:]]+/, "", title)
      if (title == "") fail("empty @title")
      seen_title = 1
      in_catalog_description = 0
      next
    }

    !in_command && $0 == "@description" {
      if (group_count > 0) fail("catalog @description must appear before all groups")
      if (seen_catalog_description) fail("duplicate catalog @description")
      seen_catalog_description = 1
      catalog_description_has_content = 0
      in_catalog_description = 1
      next
    }

    /^@group[[:space:]]+/ {
      if (in_command) fail("a new group starts before @end")
      if (!seen_title) fail("@group appears before @title")
      if (!seen_catalog_description) fail("@group appears before catalog @description")
      group = $0
      sub(/^@group[[:space:]]+/, "", group)
      if (group == "") fail("empty @group")
      if (group !~ /^[A-Za-z0-9_-]+$/) fail("group names may contain only letters, numbers, hyphens, and underscores")
      if (previous_group != "" && group_command_count == 0) fail("group \"" previous_group "\" has no commands")
      group_key = tolower(group)
      if (seen_group[group_key]++) fail("duplicate group \"" group "\"")
      group_count++
      previous_group = group
      group_command_count = 0
      in_catalog_description = 0
      next
    }

    /^@command[[:space:]]+/ {
      if (in_command) fail("a new command starts before @end")
      if (group == "") fail("@command appears before @group")
      command_name = $0
      sub(/^@command[[:space:]]+/, "", command_name)
      if (command_name == "") fail("empty @command")
      command_key = tolower(group) SUBSEP tolower(command_name)
      if (seen_command[command_key]++) fail("duplicate command \"" command_name "\" in group \"" group "\"")
      in_command = 1
      group_command_count++
      has_description = 0
      has_run = 0
      has_mode = 0
      has_risk = 0
      has_params = 0
      has_optional = 0
      has_notes = 0
      description_has_content = 0
      run_has_content = 0
      run_lines = 0
      field = ""
      next
    }

    in_command && /^@mode[[:space:]]+/ {
      if (has_mode) fail("command \"" command_name "\" has duplicate @mode")
      mode = $0
      sub(/^@mode[[:space:]]+/, "", mode)
      if (mode !~ /^(LOCAL|MODERN|LEGACY-ZK|KRAFT)$/) fail("command \"" command_name "\" has invalid @mode")
      has_mode = 1
      field = ""
      next
    }

    in_command && /^@risk[[:space:]]+/ {
      if (has_risk) fail("command \"" command_name "\" has duplicate @risk")
      risk = $0
      sub(/^@risk[[:space:]]+/, "", risk)
      if (risk !~ /^(WRITE|WARN|DELETE)$/) fail("command \"" command_name "\" has invalid @risk")
      has_risk = 1
      field = ""
      next
    }

    in_command && $0 == "@description" {
      if (has_description) fail("command \"" command_name "\" has duplicate @description")
      has_description = 1
      field = "description"
      next
    }

    in_command && $0 == "@run" {
      if (has_run) fail("command \"" command_name "\" has duplicate @run")
      has_run = 1
      field = "run"
      next
    }

    in_command && $0 == "@params" {
      if (has_params) fail("command \"" command_name "\" has duplicate @params")
      has_params = 1
      field = "params"
      next
    }

    in_command && $0 == "@optional" {
      if (has_optional) fail("command \"" command_name "\" has duplicate @optional")
      has_optional = 1
      field = "optional"
      next
    }

    in_command && $0 == "@notes" {
      if (has_notes) fail("command \"" command_name "\" has duplicate @notes")
      has_notes = 1
      field = "notes"
      next
    }

    $0 == "@end" {
      if (!in_command) {
        fail("stray @end")
        next
      }
      if (!has_description) fail("command \"" command_name "\" has no @description")
      else if (!description_has_content) fail("command \"" command_name "\" has an empty @description")
      if (!has_mode) fail("command \"" command_name "\" has no @mode")
      if (!has_run) fail("command \"" command_name "\" has no @run")
      else if (!run_has_content) fail("command \"" command_name "\" has an empty @run")
      else if (run_lines != 1) fail("command \"" command_name "\" must contain exactly one physical @run line")
      in_command = 0
      field = ""
      command_count++
      has_risk = 0
      next
    }

    in_command && /^@/ {
      fail("unknown directive \"" $0 "\" in command \"" command_name "\"")
      field = ""
      next
    }

    in_command && field == "description" && /[^[:space:]]/ { description_has_content = 1 }
    in_command && field == "run" && /[^[:space:]]/ {
      run_has_content = 1
      run_lines++
    }
    in_command && (field == "params" || field == "optional") && /[^[:space:]]/ {
      validate_parameter_row($0)
    }

    !in_command && in_catalog_description && /[^[:space:]]/ { catalog_description_has_content = 1 }

    !in_command && /^@/ {
      fail("unknown top-level directive \"" $0 "\"")
      in_catalog_description = 0
      next
    }

    !in_command && /[^[:space:]]/ && !in_catalog_description {
      fail("unscoped text on line " NR)
      next
    }

    END {
      if (in_command) fail("command \"" command_name "\" has no closing @end")
      if (!seen_title) fail("missing @title")
      if (!seen_catalog_description) fail("missing catalog @description")
      else if (!catalog_description_has_content) fail("empty catalog @description")
      if (previous_group != "" && group_command_count == 0) fail("group \"" previous_group "\" has no commands")
      if (command_count == 0) fail("no command blocks found")
      exit(errors ? 1 : 0)
    }
  ' "$1"
}

_god_validate_all_catalogs() {
  local file catalog_files

  catalog_files="$(_god_catalog_files)" || return 2

  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    _god_validate_catalog "$file" || return 2
  done <<< "$catalog_files"

  return 0
}

_god_group_name() {
  LC_ALL=C awk -v wanted="$2" '
    /^@group[[:space:]]+/ {
      name = $0
      sub(/^@group[[:space:]]+/, "", name)
      if (tolower(name) == tolower(wanted)) {
        print name
        found = 1
        exit
      }
    }
    END { if (!found) exit 1 }
  ' "$1"
}

_god_catalog_group_names() {
  LC_ALL=C awk '
    /^@group[[:space:]]+/ {
      name = $0
      sub(/^@group[[:space:]]+/, "", name)
      print name
    }
  ' "$1"
}
