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

    # Dotted numeric comparison. Missing components count as zero, so 3.9 and
    # 3.9.0 are equal and neither is treated as the newer release.
    function version_compare(left, right, left_parts, right_parts, left_count, right_count, position, total, left_value, right_value) {
      left_count = split(left, left_parts, /\./)
      right_count = split(right, right_parts, /\./)
      total = left_count > right_count ? left_count : right_count
      for (position = 1; position <= total; position++) {
        left_value = position <= left_count ? left_parts[position] + 0 : 0
        right_value = position <= right_count ? right_parts[position] + 0 : 0
        if (left_value > right_value) return 1
        if (left_value < right_value) return -1
      }
      return 0
    }

    function validate_discover_row(line, count, parts, key, value, head) {
      count = split(line, parts, /\|/)
      if (count != 3 || trim(parts[1]) == "" || trim(parts[2]) == "" || trim(parts[3]) == "") {
        fail("invalid @discover row on line " NR "; expected KEY | VALUE | MEANING")
        return
      }

      key = trim(parts[1])
      value = trim(parts[2])
      if (key !~ /^(probe|root|scan|version)$/) {
        fail("unknown @discover key \"" key "\" on line " NR "; expected probe, root, scan, or version")
        return
      }

      if (key == "probe") {
        # Probe rows are an ordered tool family. The first available tool wins,
        # which lets one catalog explicitly support a legacy CLI without any
        # service-name branch in discovery.
        if (seen_discover_probe[value]++) {
          fail("@discover has a duplicate probe \"" value "\"")
        } else {
          discover_probe_count++
        }
        # The probe is looked up inside a resolved directory, so a path here
        # would silently escape that directory.
        if (value !~ /^[A-Za-z0-9._-]+$/) fail("@discover probe \"" value "\" must be a bare file name")
      } else if (key == "root") {
        discover_root++
        if (value !~ /^\//) fail("@discover root \"" value "\" must be an absolute path")
      } else if (key == "scan") {
        discover_scan++
        if (value !~ /^\//) fail("@discover scan \"" value "\" must be an absolute path")
      } else {
        if (discover_version++) fail("@discover has a duplicate version row")
        head = value
        sub(/[[:space:]].*$/, "", head)
        if (head != "<probe>" && head !~ /^[A-Za-z0-9._-]+$/) {
          fail("@discover version must start with a bare file name or <probe>")
        }
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
      in_discover = 0
      next
    }

    !in_command && $0 == "@description" {
      if (group_count > 0) fail("catalog @description must appear before all groups")
      if (seen_catalog_description) fail("duplicate catalog @description")
      seen_catalog_description = 1
      catalog_description_has_content = 0
      in_catalog_description = 1
      in_discover = 0
      next
    }

    !in_command && $0 == "@discover" {
      if (group_count > 0) fail("@discover must appear before all groups")
      if (seen_discover) fail("duplicate @discover")
      if (seen_execution) fail("@discover and @execution PATH cannot appear in the same catalog")
      seen_discover = 1
      in_catalog_description = 0
      in_discover = 1
      next
    }

    !in_command && /^@execution([[:space:]]|$)/ {
      if (group_count > 0) fail("@execution must appear before all groups")
      if (seen_execution) fail("duplicate @execution")
      execution = $0
      sub(/^@execution[[:space:]]*/, "", execution)
      if (execution != "PATH") fail("@execution must be exactly PATH")
      if (seen_discover) fail("@discover and @execution PATH cannot appear in the same catalog")
      seen_execution = 1
      in_catalog_description = 0
      in_discover = 0
      next
    }

    !in_command && /^@synced[[:space:]]+/ {
      if (group_count > 0) fail("@synced must appear before all groups")
      if (seen_synced) fail("duplicate @synced")
      synced = $0
      sub(/^@synced[[:space:]]+/, "", synced)
      if (synced !~ /^[0-9]+(\.[0-9]+)*$/) fail("@synced must be a dotted numeric version")
      seen_synced = 1
      in_catalog_description = 0
      in_discover = 0
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
      in_discover = 0
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
      has_since = 0
      has_until = 0
      has_intent = 0
      since_value = ""
      until_value = ""
      description_has_content = 0
      notes_has_content = 0
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

    in_command && /^@since[[:space:]]+/ {
      if (has_since) fail("command \"" command_name "\" has duplicate @since")
      since_value = $0
      sub(/^@since[[:space:]]+/, "", since_value)
      if (since_value !~ /^[0-9]+(\.[0-9]+)*$/) fail("command \"" command_name "\" has invalid @since; expected a dotted numeric version")
      has_since = 1
      field = ""
      next
    }

    in_command && /^@until[[:space:]]+/ {
      if (has_until) fail("command \"" command_name "\" has duplicate @until")
      until_value = $0
      sub(/^@until[[:space:]]+/, "", until_value)
      if (until_value !~ /^[0-9]+(\.[0-9]+)*$/) fail("command \"" command_name "\" has invalid @until; expected a dotted numeric version")
      has_until = 1
      field = ""
      next
    }

    in_command && /^@intent[[:space:]]+/ {
      if (has_intent) fail("command \"" command_name "\" has duplicate @intent")
      intent = $0
      sub(/^@intent[[:space:]]+/, "", intent)
      if (intent !~ /^[a-z0-9-]+$/) fail("command \"" command_name "\" has invalid @intent; expected a lowercase kebab-case slug")
      has_intent = 1
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
      if (seen_discover && !has_since) {
        fail("command \"" command_name "\" has no @since; every command in an executable catalog must declare its compatibility floor")
      }
      if (!has_run) fail("command \"" command_name "\" has no @run")
      else if (!run_has_content) fail("command \"" command_name "\" has an empty @run")
      else if (run_lines != 1) fail("command \"" command_name "\" must contain exactly one physical @run line")
      if (has_since && has_until && version_compare(since_value, until_value) > 0) {
        fail("command \"" command_name "\" has @since " since_value " after @until " until_value)
      }
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
    in_command && field == "notes" && /[^[:space:]]/ { notes_has_content = 1 }
    in_command && field == "run" && /[^[:space:]]/ {
      run_has_content = 1
      run_lines++
    }
    in_command && (field == "params" || field == "optional") && /[^[:space:]]/ {
      validate_parameter_row($0)
    }

    !in_command && in_catalog_description && /[^[:space:]]/ { catalog_description_has_content = 1 }

    !in_command && in_discover && /[^[:space:]]/ { validate_discover_row($0) }

    !in_command && /^@/ {
      fail("unknown top-level directive \"" $0 "\"")
      in_catalog_description = 0
      in_discover = 0
      next
    }

    !in_command && /[^[:space:]]/ && !in_catalog_description && !in_discover {
      fail("unscoped text on line " NR)
      next
    }

    END {
      if (in_command) fail("command \"" command_name "\" has no closing @end")
      if (!seen_title) fail("missing @title")
      if (!seen_catalog_description) fail("missing catalog @description")
      else if (!catalog_description_has_content) fail("empty catalog @description")
      if (seen_discover && !discover_probe_count) fail("@discover has no probe row")
      if (seen_discover && !discover_root) fail("@discover has no root row")
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

# Service-level version metadata. Absent on a catalog that has no @discover
# block, which is how the resolver tells a display-only service from one it
# can execute against.

_god_catalog_has_discover() {
  LC_ALL=C awk '
    /^@discover$/ { found = 1; exit }
    /^@group[[:space:]]+/ { exit }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# _god_catalog_execution_mode FILE
#
# Prints DISCOVER for a catalog with an installed-tool-family discovery block,
# PATH for an intentional collection of commands resolved through PATH, or
# nothing for a display-only catalog. Validation owns the mutual-exclusion
# rule, so callers never need a service-name branch.
_god_catalog_execution_mode() {
  LC_ALL=C awk '
    /^@discover$/ { print "DISCOVER"; exit }
    /^@execution[[:space:]]+PATH$/ { print "PATH"; exit }
    /^@group[[:space:]]+/ { exit }
  ' "$1"
}

_god_catalog_has_execution() {
  [ -n "$(_god_catalog_execution_mode "$1")" ]
}

# _god_catalog_discover_value FILE KEY
#
# KEY is one of probe, root, scan, version. Prints the first matching VALUE
# column inside the @discover block, or nothing when absent. Use
# _god_catalog_discover_probes when a catalog declares an ordered probe family.
_god_catalog_discover_value() {
  LC_ALL=C awk -v want="$2" '
    /^@discover$/ { in_block = 1; next }
    in_block && /^@/ { in_block = 0 }
    in_block && /[^[:space:]]/ {
      count = split($0, parts, /\|/)
      if (count == 3) {
        key = parts[1]
        sub(/^[[:space:]]+/, "", key)
        sub(/[[:space:]]+$/, "", key)
        if (key == want) {
          value = parts[2]
          sub(/^[[:space:]]+/, "", value)
          sub(/[[:space:]]+$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$1"
}

# _god_catalog_discover_probes FILE
#
# Prints each catalog-declared probe in declaration order. Most catalogs have
# one; a catalog can declare a primary modern tool and one or more legacy
# fallbacks. The discovery engine owns selection so no service name is ever
# special-cased.
_god_catalog_discover_probes() {
  LC_ALL=C awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    /^@discover$/ { in_block = 1; next }
    in_block && /^@/ { in_block = 0 }
    in_block && /[^[:space:]]/ {
      count = split($0, parts, /\|/)
      if (count == 3 && trim(parts[1]) == "probe") print trim(parts[2])
    }
  ' "$1"
}

# _god_catalog_command_export FILE GROUP ENTRY_INDEX
#
# Structured, machine-readable dump of one command record: the fields
# resolve.sh and execute.sh need without re-parsing the grammar themselves.
# One tab-separated row per line:
#   MODE\t<mode>
#   RISK\t<risk>              (absent when the record has no @risk)
#   RUN\t<run>
#   SINCE\t<since>            (absent when the record has no @since)
#   UNTIL\t<until>            (absent when the record has no @until)
#   INTENT\t<intent>          (absent when the record has no @intent)
#   RUNNABLE\t1                (catalog records are always executable when
#                                their service is resolved; the picker may
#                                still disable a version-incompatible row)
#   NOTES\t<notes>             (present when the record has @notes)
#   PARAM\t<name>\t<example>\t<meaning>\t<keyword>:<value-class>
#   OPTIONAL\t<name>\t<example>\t<meaning>\t<keyword>:<value-class>
#   TITLE\t<command title>
_god_catalog_command_export() {
  LC_ALL=C awk \
    -v wanted="$2" \
    -v wanted_index="$3" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function words(value) {
      value = tolower(value)
      gsub(/[^a-z0-9]+/, " ", value)
      return " " value " "
    }

    # Resolution used to rediscover this classification with several tr
    # processes every time a row was highlighted. It is catalog metadata, so
    # derive it once inside the export parse already walking the record.
    function slot_class(name, meaning, name_words, meaning_words) {
      name_words = words(name)
      meaning_words = words(meaning)

      if (index(name_words, " topic ")) return "topic:name"
      if (index(name_words, " group ")) return "group:name"
      if (index(name_words, " host ")) return "host:name"
      if (index(name_words, " index ")) return "index:name"
      if (index(name_words, " collection ")) return "collection:name"
      if (index(name_words, " offset ")) return "offset:num"
      if (index(name_words, " partition ")) return "partition:num"
      if (index(name_words, " port ")) return "port:num"
      if (index(name_words, " count ")) return "count:num"

      if (index(meaning_words, " topic ")) return "topic:name"
      if (index(meaning_words, " group ")) return "group:name"
      if (index(meaning_words, " host ")) return "host:name"
      if (index(meaning_words, " index ")) return "index:name"
      if (index(meaning_words, " collection ")) return "collection:name"
      if (index(meaning_words, " offset ")) return "offset:num"
      if (index(meaning_words, " partition ")) return "partition:num"
      if (index(meaning_words, " port ")) return "port:num"
      if (index(meaning_words, " count ")) return "count:num"
      return ""
    }

    /^@group[[:space:]]+/ {
      current = $0
      sub(/^@group[[:space:]]+/, "", current)
      in_wanted_group = tolower(current) == tolower(wanted)
      if (in_wanted_group) group_position = 0
      next
    }

    /^@command[[:space:]]+/ {
      if (in_wanted_group) group_position++
      selected = in_wanted_group && group_position == wanted_index
      command_title = $0
      sub(/^@command[[:space:]]+/, "", command_title)
      command_runnable = 1
      notes = ""
      field = ""
      next
    }

    selected && /^@mode[[:space:]]+/ {
      value = $0
      sub(/^@mode[[:space:]]+/, "", value)
      print "MODE\t" value
      field = ""
      next
    }

    selected && /^@risk[[:space:]]+/ {
      value = $0
      sub(/^@risk[[:space:]]+/, "", value)
      print "RISK\t" value
      field = ""
      next
    }

    selected && /^@since[[:space:]]+/ {
      value = $0
      sub(/^@since[[:space:]]+/, "", value)
      print "SINCE\t" value
      field = ""
      next
    }

    selected && /^@until[[:space:]]+/ {
      value = $0
      sub(/^@until[[:space:]]+/, "", value)
      print "UNTIL\t" value
      field = ""
      next
    }

    selected && /^@intent[[:space:]]+/ {
      value = $0
      sub(/^@intent[[:space:]]+/, "", value)
      print "INTENT\t" value
      field = ""
      next
    }

    selected && $0 == "@description" { field = "description"; next }
    selected && $0 == "@run" { field = "run"; next }
    selected && $0 == "@params" { field = "params"; next }
    selected && $0 == "@optional" { field = "optional"; next }
    selected && $0 == "@notes" { field = "notes"; next }

    $0 == "@end" {
      if (selected) {
        print "RUNNABLE\t" command_runnable
        if (notes != "") print "NOTES\t" notes
        print "TITLE\t" command_title
      }
      selected = 0
      field = ""
      next
    }

    selected && field == "run" && /[^[:space:]]/ { print "RUN\t" $0 }

    selected && field == "notes" && /[^[:space:]]/ {
      notes = notes (notes == "" ? "" : " ") $0
      next
    }

    selected && (field == "params" || field == "optional") && /[^[:space:]]/ {
      columns = split($0, parts, /\|/)
      if (columns == 3) {
        tag = field == "params" ? "PARAM" : "OPTIONAL"
        name = trim(parts[1])
        example = trim(parts[2])
        meaning = trim(parts[3])
        print tag "\t" name "\t" example "\t" meaning "\t" slot_class(name, meaning)
      }
    }
  ' "$1"
}

_god_catalog_synced() {
  LC_ALL=C awk '
    /^@synced[[:space:]]+/ {
      value = $0
      sub(/^@synced[[:space:]]+/, "", value)
      print value
      exit
    }
  ' "$1"
}
