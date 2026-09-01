# shellcheck shell=bash

# Search parsing, matching, ranking, and rendering for BASH_GOD.

_god_print_search_help() {
  local scope_service scope_group search_route banner_title

  scope_service="${1:-}"
  scope_group="${2:-}"
  search_route='god'
  banner_title='SEARCH'
  if [ -n "$scope_service" ]; then
    search_route="$search_route $scope_service"
    banner_title="$(_god_upper "$scope_service") SEARCH"
  fi
  if [ -n "$scope_group" ]; then
    search_route="$search_route $scope_group"
    banner_title="$(_god_upper "$scope_service") / $(_god_upper "$scope_group") SEARCH"
  fi
  search_route="$search_route q"

  _god_banner "$banner_title" 'Find commands by anything you remember.'

  _god_section 'SEARCH MODES'
  printf '  %s%-48s%s %sBroad, forgiving, relevance-ranked search%s\n' "$_GOD_COMMAND" "$search_route WORDS" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-48s%s %sReturn every row matching any remembered word%s\n' "$_GOD_COMMAND" "$search_route --any WORDS" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-48s%s %sRequire every meaningful word%s\n' "$_GOD_COMMAND" "$search_route --all WORDS" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-48s%s %sMatch one exact phrase%s\n' "$_GOD_COMMAND" "$search_route --exact 'PHRASE'" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-48s%s %sUse a POSIX extended regular expression%s\n' "$_GOD_COMMAND" "$search_route --regex 'PATTERN'" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"

  _god_section 'SEARCH VIEWS'
  printf '  %s%-48s%s %sGroup matching rows as a hierarchy%s\n' "$_GOD_COMMAND" "$search_route WORDS --tree" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-48s%s %sInclude each matching native command line%s\n' "$_GOD_COMMAND" "$search_route WORDS --tree --full" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-48s%s %sExpand every matching operation%s\n' "$_GOD_COMMAND" "$search_route WORDS --details" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  printf '  %s%-48s%s %sShow these search keys from any query%s\n' "$_GOD_COMMAND" "$search_route WORDS --keys" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"

  _god_section 'EXAMPLES'
  printf '  %s%s%s\n' "$_GOD_COMMAND" "$search_route \"describe topic\"" "$_GOD_RESET"
  printf '  %s%s%s\n' "$_GOD_COMMAND" "$search_route \"describe topic\" --tree --full" "$_GOD_RESET"
  printf '  %s%s%s\n' "$_GOD_COMMAND" "$search_route consumer lag" "$_GOD_RESET"
  printf '  %s%s%s\n' "$_GOD_COMMAND" "$search_route --regex 'offset|lag'" "$_GOD_RESET"

  printf '\n%s  Search is case-insensitive and checks service/group names, titles, descriptions,%s\n' "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  native commands, parameters, optional flags, notes, modes, and risk labels.%s\n' "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  Smart mode ignores filler words, tolerates word variants, and keeps the best coverage.%s\n' "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  Search runs a command only from the reviewed interactive picker; every other view is copy-ready text.%s\n' "$_GOD_DIM" "$_GOD_RESET"
}

_god_validate_regex() {
  GOD_SEARCH_PATTERN="$1" LC_ALL=C awk 'BEGIN {
    pattern = ENVIRON["GOD_SEARCH_PATTERN"]
    ignored = ("" ~ pattern)
    exit 0
  }' </dev/null 2>/dev/null
}

_god_validate_query_text() {
  GOD_QUERY_TEXT="$1" LC_ALL=C awk 'BEGIN {
    value = ENVIRON["GOD_QUERY_TEXT"]
    valid = value != "" && value !~ /[[:cntrl:]]/ && value ~ /[^[:space:]]/
    exit(valid ? 0 : 1)
  }' </dev/null
}

_god_search_catalog() {
  local catalog service pattern search_mode wanted_group

  catalog="$1"
  service="$2"
  pattern="$3"
  search_mode="$4"
  wanted_group="${5:-}"

  GOD_SEARCH_PATTERN="$pattern" GOD_SEARCH_MODE="$search_mode" LC_ALL=C awk \
    -v service="$service" \
    -v wanted_group="$wanted_group" '
    function append(existing, line) {
      return existing (existing == "" ? "" : separator) line
    }

    function canonical_word(word) {
      word = tolower(word)
      gsub(/^[^[:alnum:]_]+/, "", word)
      gsub(/[^[:alnum:]_]+$/, "", word)
      if (length(word) > 4 && word ~ /ies$/) {
        sub(/ies$/, "y", word)
      } else if (length(word) > 4 && word ~ /s$/ && word !~ /(ss|us|is)$/) {
        sub(/s$/, "", word)
      }
      return word
    }

    function is_filler(word) {
      return word ~ /^(a|an|and|or|the|of|for|to|from|in|on|with|about|how|do|does|did|can|could|would|should|i|we|you|me|my|our|please|want|need|get|all|no|such|god|command|commands)$/
    }

    function add_query_word(word) {
      word = canonical_word(word)
      if (word == "" || seen_query_word[word]) return
      seen_query_word[word] = 1
      query_words[++query_count] = word
    }

    function build_query(query, count, words, i, word) {
      query = tolower(query)
      gsub(/[^[:alnum:]_]+/, " ", query)
      count = split(query, words, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        word = canonical_word(words[i])
        if (word != "" && !is_filler(word)) add_query_word(word)
      }

      # A query made only of filler words should still be searchable.
      if (query_count == 0) {
        for (i = 1; i <= count; i++) add_query_word(words[i])
      }
    }

    function word_matches(candidate, wanted, shortest) {
      if (candidate == wanted) return 1
      shortest = length(candidate) < length(wanted) ? length(candidate) : length(wanted)
      return shortest >= 3 && (index(candidate, wanted) == 1 || index(wanted, candidate) == 1)
    }

    function text_has_word(text, wanted, count, words, i, candidate) {
      text = tolower(text)
      gsub(/[^[:alnum:]_]+/, " ", text)
      count = split(text, words, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        candidate = canonical_word(words[i])
        if (candidate != "" && word_matches(candidate, wanted)) return 1
      }
      return 0
    }

    function smart_score(matched, score, i, word, word_score) {
      matched = 0
      score = 0
      for (i = 1; i <= query_count; i++) {
        word = query_words[i]
        word_score = 0
        if (text_has_word(command_title, word)) word_score += 40
        if (text_has_word(service " " group, word)) word_score += 24
        if (text_has_word(command_body, word)) word_score += 10
        if (word_score > 0) {
          matched++
          score += word_score
        }
      }

      if (matched == 0) return -1
      if (search_mode == "all" && matched != query_count) return -1
      match_coverage = matched
      if (matched == query_count) score += 50 + (query_count * 5)
      return score
    }

    function flush() {
      if (!in_command) return
      command_body = metadata separator details
      search_text = service separator group separator command_title separator command_body

      if (search_mode == "regex") {
        score = tolower(search_text) ~ pattern ? 100 : -1
        match_coverage = score >= 0 ? 1 : 0
      } else if (search_mode == "exact") {
        score = index(tolower(search_text), pattern) ? 100 : -1
        match_coverage = score >= 0 ? 1 : 0
      } else {
        score = smart_score()
      }

      if (score >= 0) {
        printf "%d\t%d\t%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t0\t%s\n", \
          score, match_coverage, service, group, entry_number, command_title, run_command, risk, since, until_version, intent, mode
        hits++
      }
      in_command = 0
    }

    BEGIN {
      separator = sprintf("%c", 28)
      pattern = tolower(ENVIRON["GOD_SEARCH_PATTERN"])
      search_mode = ENVIRON["GOD_SEARCH_MODE"]
      if (search_mode == "smart" || search_mode == "any" || search_mode == "all") build_query(pattern)
    }

    /^@group[[:space:]]+/ {
      group = $0
      sub(/^@group[[:space:]]+/, "", group)
      group_index = 0
      next
    }

    /^@command[[:space:]]+/ {
      flush()
      group_index++
      in_command = wanted_group == "" || tolower(group) == tolower(wanted_group)
      if (!in_command) {
        field = ""
        next
      }
      entry_number = group_index
      command_title = $0
      sub(/^@command[[:space:]]+/, "", command_title)
      risk = ""
      since = ""
      until_version = ""
      intent = ""
      mode = ""
      field = ""
      metadata = ""
      details = ""
      run_command = ""
      next
    }

    in_command && /^@mode[[:space:]]+/ {
      value = $0
      sub(/^@mode[[:space:]]+/, "", value)
      mode = value
      metadata = append(metadata, value)
      field = ""
      next
    }

    in_command && /^@risk[[:space:]]+/ {
      risk = $0
      sub(/^@risk[[:space:]]+/, "", risk)
      metadata = append(metadata, risk)
      field = ""
      next
    }

    in_command && /^@since[[:space:]]+/ {
      since = $0
      sub(/^@since[[:space:]]+/, "", since)
      field = ""
      next
    }

    in_command && /^@until[[:space:]]+/ {
      until_version = $0
      sub(/^@until[[:space:]]+/, "", until_version)
      field = ""
      next
    }

    in_command && /^@intent[[:space:]]+/ {
      intent = $0
      sub(/^@intent[[:space:]]+/, "", intent)
      field = ""
      next
    }

    in_command && $0 == "@description" { field = "description"; next }
    in_command && $0 == "@run" { field = "run"; next }
    in_command && $0 == "@params" { field = "params"; next }
    in_command && $0 == "@optional" { field = "optional"; next }
    in_command && $0 == "@notes" { field = "notes"; next }

    $0 == "@end" {
      flush()
      next
    }

    in_command && field != "" && $0 != "" {
      if (field == "run") run_command = $0
      details = append(details, $0)
    }

    END {
      flush()
      exit(hits ? 0 : 1)
    }
  ' "$catalog"
}

_god_render_search_list() {
  local sorted_results tab search_mode

  sorted_results="$1"
  tab="$2"
  search_mode="$3"

  _god_section 'MATCHING OPERATIONS'
  printf '%s  %-32s %s%s\n' "$_GOD_DIM" 'OPEN' 'OPERATION' "$_GOD_RESET"
  printf '%s  %-32s %s%s\n' "$_GOD_DIM" '--------------------------------' '----------------------------------------------' "$_GOD_RESET"

  # Rows are consumed with awk's field splitting, not a bash `read`, because a
  # tab stays IFS whitespace to `read` even when it is the only IFS
  # character: runs of it collapse, so an empty RISK or TWIN field in the
  # middle of the row would silently shift every field after it.
  LC_ALL=C awk \
    -F "$tab" \
    -v accent="$_GOD_ACCENT" \
    -v bold="$_GOD_BOLD" \
    -v dim="$_GOD_DIM" \
    -v warning_color="$_GOD_WARNING" \
    -v reset="$_GOD_RESET" '
    NF < 8 || $3 == "" { next }
    {
      result_route = "god " $3 " " $4 " " $5
      printf "  %s%-32s%s %s%s%s", accent, result_route, reset, bold, $6, reset
      if ($8 != "") printf " %s[%s]%s", warning_color, $8, reset
      if ($15 != "") printf " %s[%s]%s", warning_color, $15, reset
      if ($16 == "1") printf " %s(older variant hidden)%s", dim, reset
      print ""
    }
  ' <<< "$sorted_results"

  printf '\n%s  Run an OPEN path to see its copy-ready native commands.%s\n' "$_GOD_DIM" "$_GOD_RESET"
  if [ "$search_mode" = "smart" ]; then
    printf '%s  Smart search shows the rows matching the most remembered words, then ranks them by relevance.%s\n' "$_GOD_DIM" "$_GOD_RESET"
  fi
  printf '%s  Views: --tree | --tree --full | --details | --keys%s\n' "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  Modes: --any | --all | --exact '\''PHRASE'\'' | --regex '\''PATTERN'\''%s\n' "$_GOD_DIM" "$_GOD_RESET"
  printf '%s  WRITE, WARN, and DELETE mark state-changing or high-impact operations.%s\n' "$_GOD_DIM" "$_GOD_RESET"
}

_god_render_search_tree() {
  local sorted_results tab search_title search_label full tree_results match_count

  sorted_results="$1"
  tab="$2"
  search_title="$3"
  search_label="$4"
  full="$5"
  tree_results="$(printf '%s\n' "$sorted_results" | LC_ALL=C sort -t "$tab" -k3,3 -k4,4 -k5,5n)" || return 2
  match_count="$(printf '%s\n' "$tree_results" | LC_ALL=C awk 'END { print NR + 0 }')" || return 2

  _god_banner "$search_title TREE" "$search_label"
  printf '%sresults%s %s(%s matching operations)%s\n' \
    "$_GOD_ACCENT" "$_GOD_RESET" "$_GOD_DIM" "$match_count" "$_GOD_RESET"

  LC_ALL=C awk \
    -F "$tab" \
    -v full="$full" \
    -v branch="$_GOD_TREE_BRANCH" \
    -v last="$_GOD_TREE_LAST" \
    -v pipe="$_GOD_TREE_PIPE" \
    -v space="$_GOD_TREE_SPACE" \
    -v accent="$_GOD_ACCENT" \
    -v bold="$_GOD_BOLD" \
    -v dim="$_GOD_DIM" \
    -v warning_color="$_GOD_WARNING" \
    -v reset="$_GOD_RESET" '
    {
      service = $3
      group = $4
      group_key = service SUBSEP group

      if (!seen_service[service]++) service_order[++service_count] = service
      if (!seen_group[group_key]++) {
        group_order[service, ++group_count[service]] = group
      }

      position = ++entry_count[group_key]
      entries[group_key, position] = $5
      titles[group_key, position] = $6
      runs[group_key, position] = $7
      risks[group_key, position] = $8
      compatibility[group_key, position] = $15
      service_entries[service]++
    }

    END {
      for (i = 1; i <= service_count; i++) {
        service = service_order[i]
        service_is_last = i == service_count
        service_connector = service_is_last ? last : branch
        printf "%s %s%s%s %s(%d)%s\n", service_connector, accent, service, reset, dim, service_entries[service], reset
        service_prefix = service_is_last ? space : pipe

        for (j = 1; j <= group_count[service]; j++) {
          group = group_order[service, j]
          group_key = service SUBSEP group
          group_is_last = j == group_count[service]
          group_connector = group_is_last ? last : branch
          printf "%s%s %s%s%s %s(%d)%s\n", service_prefix, group_connector, bold, group, reset, dim, entry_count[group_key], reset
          group_prefix = service_prefix (group_is_last ? space : pipe)

          for (k = 1; k <= entry_count[group_key]; k++) {
            entry_is_last = k == entry_count[group_key]
            entry_connector = entry_is_last ? last : branch
            printf "%s%s %s%02d%s %s%s%s", group_prefix, entry_connector, accent, entries[group_key, k], reset, dim, titles[group_key, k], reset
            if (risks[group_key, k] != "") printf " %s[%s]%s", warning_color, risks[group_key, k], reset
            if (compatibility[group_key, k] != "") printf " %s[%s]%s", warning_color, compatibility[group_key, k], reset
            print ""

            if (full == "1") {
              entry_prefix = group_prefix (entry_is_last ? space : pipe)
              printf "%s%s %s$ %s%s\n", entry_prefix, last, dim, runs[group_key, k], reset
            }
          }
        }
      }
    }
  ' <<< "$tree_results" || return 2

  if [ "$full" != "1" ]; then
    printf '\n%s  Add %s--full%s%s after --tree to include every native command line.%s\n' \
      "$_GOD_DIM" "$_GOD_ACCENT" "$_GOD_RESET" "$_GOD_DIM" "$_GOD_RESET"
  fi
}

_god_render_search_details() {
  local sorted_results tab search_title search_label line row_fields separator service group entry compatibility catalog

  sorted_results="$1"
  tab="$2"
  search_title="$3"
  search_label="$4"

  _god_banner "$search_title DETAILS" "$search_label"
  printf '%s  Every matching operation is expanded below; catalog commands remain inert.%s\n' "$_GOD_DIM" "$_GOD_RESET"

  separator="$(printf '\034')"
  while IFS= read -r line; do
    row_fields="$(printf '%s' "$line" | LC_ALL=C awk -F "$tab" -v separator="$separator" '{ printf "%s%s%s%s%s%s%s", $3, separator, $4, separator, $5, separator, $15 }')"
    IFS="$separator" read -r service group entry compatibility <<< "$row_fields"
    [ -n "$service" ] || continue
    catalog="$(_god_catalog_for "$service")" || return 2
    printf '\n'
    [ -z "$compatibility" ] || printf '%s  Compatibility: %s%s\n' "$_GOD_WARNING" "$compatibility" "$_GOD_RESET"
    _god_print_catalog_entry "$catalog" "$service" "$group" "$entry" 1 || return $?
  done <<< "$sorted_results"
}

# _god_search_detected_versions SORTED_RESULTS TAB
#
# One SERVICE\tVERSION\tSYNCED line per distinct service appearing in the
# results, from discover.sh's cache and the catalog header. A service that has
# never resolved (or has no @discover block at all) is absent from the map.
_god_search_detected_versions() {
  local sorted_results tab service version seen catalog synced

  sorted_results="$1"
  tab="$2"
  seen=''
  while IFS="$tab" read -r _ _ service _; do
    [ -n "$service" ] || continue
    case " $seen " in *" $service "*) continue ;; esac
    seen="$seen $service"
    version="$(_god_discover_version "$service" 2>/dev/null)"
    [ -n "$version" ] || continue
    catalog="$(_god_catalog_for "$service" 2>/dev/null)" || continue
    synced="$(_god_catalog_synced "$catalog")"
    printf '%s\t%s\t%s\n' "$service" "$version" "$synced"
  done <<< "$sorted_results"
}

# _god_search_apply_policy SORTED_RESULTS TAB VERSION_MAP [ALL_VERSIONS]
#
# Applied once after scoring, before rendering, and never reorders results.
#
#   - @since/@until annotate an out-of-range row against its service's
#     detected version. The row remains visible but cannot be executed.
#   - A catalog older than the detected service version annotates each normal
#     command as not verified. It remains runnable because @synced is a
#     caution, not a compatibility boundary.
#   - Same (service, @intent) rows collapse to the single member with the
#     best compatibility and then highest @since unless ALL_VERSIONS is 1.
#
# Appends COMPATIBILITY_KIND, COMPATIBILITY_LABEL, and TWIN_DISPLAY fields.
_god_search_apply_policy() {
  local sorted_results tab version_map all_versions

  sorted_results="$1"
  tab="$2"
  version_map="$3"
  all_versions="${4:-0}"

  LC_ALL=C awk -F "$tab" -v OFS="$tab" -v version_map="$version_map" -v all_versions="$all_versions" '
    function version_compare(left, right, l, r, lc, rc, n, i, lv, rv) {
      lc = split(left, l, ".")
      rc = split(right, r, ".")
      n = lc > rc ? lc : rc
      for (i = 1; i <= n; i++) {
        lv = i <= lc ? l[i] + 0 : 0
        rv = i <= rc ? r[i] + 0 : 0
        if (lv > rv) return 1
        if (lv < rv) return -1
      }
      return 0
    }

    BEGIN {
      map_count = split(version_map, map_lines, "\n")
      for (i = 1; i <= map_count; i++) {
        if (map_lines[i] == "") continue
        split(map_lines[i], kv, "\t")
        detected[kv[1]] = kv[2]
        synced[kv[1]] = kv[3]
      }
    }

    NF < 8 { next }

    {
      service = $3
      since = $9
      until_version = $10
      intent = $11
      mode = $13
      version = (service in detected) ? detected[service] : ""
      numeric_version = version ~ /^[0-9]+([.][0-9]+)*$/
      kind = ""
      label = ""

      if (mode != "LOCAL" && version != "") {
        if (numeric_version && since != "" && version_compare(version, since) < 0) {
          kind = "blocked"
          label = "needs v" since "+ (have v" version ")"
        } else if (numeric_version && until_version != "" && version_compare(version, until_version) > 0) {
          kind = "blocked"
          label = "works through v" until_version " (have v" version ")"
        } else if (numeric_version && synced[service] ~ /^[0-9]+([.][0-9]+)*$/ && version_compare(version, synced[service]) > 0) {
          kind = "warning"
          label = "not verified on v" version
        } else if (!numeric_version && (since != "" || until_version != "")) {
          kind = "warning"
          label = "version could not be detected"
        }
      }

      row_count++
      rows[row_count] = $0 OFS kind OFS label
      blocked[row_count] = kind == "blocked"

      # Collapse only makes sense against a trustworthy detected version.
      if (all_versions != "1" && intent != "" && numeric_version) {
        key = service SUBSEP intent
        candidate_since = (since == "") ? "0" : since
        candidate_rank = blocked[row_count] ? 0 : 1
        key_count[key]++
        if (!(key in best_rank) || candidate_rank > best_rank[key] || \
            (candidate_rank == best_rank[key] && version_compare(candidate_since, best_since[key]) > 0)) {
          best_rank[key] = candidate_rank
          best_since[key] = candidate_since
          best_row[key] = row_count
        }
        row_intent[row_count] = key
      }
    }

    END {
      for (i = 1; i <= row_count; i++) {
        key = row_intent[i]
        if (key != "" && best_row[key] != i) continue
        twin_display = (key != "" && key_count[key] > 1) ? 1 : 0
        print rows[i] OFS twin_display
      }
    }
  ' <<< "$sorted_results"
}

# _god_search_rich_available SORTED_RESULTS TAB
#
# Returns true only when the entire result set can use the rich picker. A
# mixed result set stays in the normal table: it is better to show every route
# than to render one runnable command beside a pretend command for another
# service. The TTY probe prevents a banner-only result when /dev/tty is absent.
_god_search_rich_available() {
  local sorted_results tab service catalog execution_mode path has_results previous_service

  sorted_results="$1"
  tab="$2"
  # The key reader is Bash-specific; a sourced zsh remains on the safe static
  # result table until it has a native rich picker implementation.
  [ -n "${BASH_VERSION:-}" ] || return 1
  _god_stdout_is_terminal || return 1
  [ "${TERM:-}" != dumb ] || return 1
  [ -n "$(type -t _god_catalog_execution_mode 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_menu_select_rich 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_menu_rich_available 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_resolve_command 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_execute_command 2>/dev/null)" ] || return 1
  _god_menu_rich_available || return 1

  previous_service=''
  while IFS="$tab" read -r _ _ service _; do
    [ -n "$service" ] || continue
    has_results=1
    [ "$service" = "$previous_service" ] && continue
    catalog="$(_god_catalog_for "$service" 2>/dev/null)" || return 1
    [ -n "$catalog" ] || return 1
    execution_mode="$(_god_catalog_execution_mode "$catalog")"
    case "$execution_mode" in
      DISCOVER)
        [ -n "$(type -t _god_discover_is_stale 2>/dev/null)" ] || return 1
        [ -n "$(type -t _god_discover_path 2>/dev/null)" ] || return 1
        _god_discover_is_stale "$service" "$catalog" && return 1
        path="$(_god_discover_path "$service" 2>/dev/null)"
        [ -n "$path" ] || return 1
        ;;
      PATH)
        # PATH services deliberately have no product directory or version
        # probe. The rich picker keeps their command text unchanged.
        ;;
      *) return 1 ;;
    esac
    previous_service=$service
  done <<< "$sorted_results"
  [ "${has_results:-0}" = 1 ]
}

_god_search() {
  local pattern search_mode search_view scope_service scope_group all_versions scope_description file service found search_status catalog_output search_title search_label catalog_files
  local search_results sorted_results tab max_coverage version_map rich_mode

  pattern="$1"
  search_mode="$2"
  search_view="${3:-list}"
  scope_service="${4:-}"
  scope_group="${5:-}"
  all_versions="${6:-0}"
  scope_description=""
  if [ -n "$scope_service" ]; then
    scope_description=" in $scope_service"
  fi
  if [ -n "$scope_group" ]; then
    scope_description="$scope_description/$scope_group"
  fi
  if [ "$search_mode" = "regex" ] && ! _god_validate_regex "$pattern"; then
    printf 'BASH_GOD: invalid POSIX extended regular expression: %s\n' "$pattern" >&2
    return 2
  fi

  found=1
  search_results=""
  if [ -n "$scope_service" ]; then
    catalog_files="$(_god_catalog_for "$scope_service")" || return 2
  else
    catalog_files="$(_god_catalog_files)" || return 2
  fi
  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    if ! _god_validate_catalog "$file"; then
      return 2
    fi
    service="$(_god_service_name_for_catalog "$file")" || return 2
    catalog_output="$(_god_search_catalog "$file" "$service" "$pattern" "$search_mode" "$scope_group")"
    search_status=$?
    if [ "$search_status" -eq 0 ]; then
      found=0
      if [ -n "$search_results" ]; then
        search_results="$search_results
$catalog_output"
      else
        search_results="$catalog_output"
      fi
    elif [ "$search_status" -gt 1 ]; then
      return 2
    fi
  done <<< "$catalog_files"

  if [ "$found" -ne 0 ]; then
    if [ "$search_mode" = "regex" ]; then
      printf 'BASH_GOD: no commands matched regex%s: %s\n' "$scope_description" "$pattern" >&2
    else
      printf 'BASH_GOD: no commands matched text%s: %s\n' "$scope_description" "$pattern" >&2
    fi
    return 1
  fi

  case "$search_mode" in
    regex) search_label="Regex: $pattern" ;;
    exact) search_label="Exact phrase: $pattern" ;;
    all) search_label="Every word: $pattern" ;;
    any) search_label="Any word: $pattern" ;;
    *) search_label="Smart search: $pattern" ;;
  esac

  search_title='SEARCH'
  if [ -n "$scope_service" ]; then
    search_title="$(_god_upper "$scope_service") SEARCH"
  fi
  if [ -n "$scope_group" ]; then
    search_title="$(_god_upper "$scope_service") / $(_god_upper "$scope_group") SEARCH"
  fi

  tab="$(printf '\t')"
  if [ "$search_mode" = "smart" ]; then
    max_coverage="$(printf '%s\n' "$search_results" | LC_ALL=C awk -F "$tab" '$2 + 0 > maximum { maximum = $2 + 0 } END { print maximum + 0 }')" || return 2
    search_results="$(printf '%s\n' "$search_results" | LC_ALL=C awk -F "$tab" -v wanted="$max_coverage" '$2 + 0 == wanted')" || return 2
  fi
  sorted_results="$(printf '%s\n' "$search_results" | LC_ALL=C sort -t "$tab" -k1,1nr -k3,3 -k4,4 -k5,5n)" || return 2

  version_map="$(_god_search_detected_versions "$sorted_results" "$tab")"
  sorted_results="$(_god_search_apply_policy "$sorted_results" "$tab" "$version_map" "$all_versions")" || return 2

  rich_mode=0
  if [ "$search_view" = "list" ] && _god_search_rich_available "$sorted_results" "$tab"; then
    rich_mode=1
  fi

  case "$search_view" in
    tree)
      _god_render_search_tree "$sorted_results" "$tab" "$search_title" "$search_label" 0
      ;;
    tree-full)
      _god_render_search_tree "$sorted_results" "$tab" "$search_title" "$search_label" 1
      ;;
    details)
      _god_render_search_details "$sorted_results" "$tab" "$search_title" "$search_label"
      ;;
    *)
      if [ "$rich_mode" = 1 ]; then
        _god_search_offer_execution_rich "$sorted_results" "$tab" "$pattern" "$search_title RESULTS" "$search_label"
        search_status=$?
        # The rich picker is an action, not merely another renderer. Once it
        # returns, preserve the selected process's exit status and do not
        # append search-policy captions underneath its terminal output.
        return "$search_status"
      else
        _god_banner "$search_title RESULTS" "$search_label"
        _god_render_search_list "$sorted_results" "$tab" "$search_mode"
      fi
      ;;
  esac
}

# _god_search_rich_detail_provider SELECTED
#
# Called directly by _god_menu_select_rich while _god_search_offer_execution_rich
# is still on the stack. Bash and zsh function locals are dynamically scoped,
# so this can lazily resolve and cache only the highlighted row. That keeps the
# first picker frame quick even when a search finds many operations.
_god_search_rich_detail_provider() {
  local selected storage_index service group entry catalog execution_path model model_tag model_value display

  selected=$1
  if [ -n "${BASH_VERSION:-}" ]; then
    storage_index=$((selected - 1))
  else
    storage_index=$selected
  fi

  model="${models[$storage_index]:-}"
  if [ -z "$model" ]; then
    service="${rich_services[$storage_index]:-}"
    group="${rich_groups[$storage_index]:-}"
    entry="${rich_entries[$storage_index]:-}"
    catalog="${rich_catalogs[$storage_index]:-}"
    execution_path="${rich_execution_paths[$storage_index]:-}"
    [ -n "$service" ] && [ -n "$group" ] && [ -n "$entry" ] && [ -n "$catalog" ] || return 1
    model="$(_god_resolve_command "$service" "$catalog" "$group" "$entry" "$execution_path" "$query")" || return 1
    models[$storage_index]=$model
  fi

  display=''
  while IFS="$tab" read -r model_tag model_value; do
    [ "$model_tag" = DISPLAY ] && { display=$model_value; break; }
  done <<< "$model"
  [ -n "$display" ] || return 1
  _god_menu_provider_detail=$display
}

# _god_search_rich_detail_cached SELECTED
#
# Kept separate from the provider so navigation can skip the transient
# resolving frame for a command that the operator has already visited.
_god_search_rich_detail_cached() {
  local selected storage_index

  selected=$1
  if [ -n "${BASH_VERSION:-}" ]; then
    storage_index=$((selected - 1))
  else
    storage_index=$selected
  fi
  [ -n "${models[$storage_index]:-}" ]
}

# _god_search_discovered_tool_missing EXECUTION_PATH RUN DISCOVER_PROBES SELECTED_TOOL
#
# A catalog may declare several interchangeable discovery tools, such as a
# modern client and an explicitly supported legacy fallback. Only a command
# whose first word is one of those declared tools is tied to the resolved
# directory. The discovered member is the family runner for every such row,
# so a modern spelling can safely use the catalog-declared legacy fallback.
# Return the missing selected runner only when the cache/path is inconsistent.
_god_search_discovered_tool_missing() {
  local execution_path run discover_probes selected_tool first probe

  execution_path=$1
  run=$2
  discover_probes=$3
  selected_tool=${4:-}
  [ -n "$execution_path" ] || return 1
  first="${run#"${run%%[![:space:]]*}"}"
  first="${first%%[[:space:]]*}"
  [ -n "$first" ] || return 1

  while IFS= read -r probe; do
    [ -n "$probe" ] || continue
    [ "$first" = "$probe" ] || continue
    [ -n "$selected_tool" ] || selected_tool=$probe
    [ -x "$execution_path/$selected_tool" ] || { printf '%s\n' "$selected_tool"; return 0; }
    return 1
  done <<< "$discover_probes"
  return 1
}

# _god_search_offer_execution_rich SORTED_RESULTS TAB QUERY [HEADER_TITLE] [HEADER_SUBTITLE]
#
# The caller has already established that every result has a fresh resolved
# path and a usable TTY. Build one clean picker: titles in the list and the
# selected, complete command in the detail panel. Details are resolved only
# when highlighted and are then cached; there is intentionally no second
# compact list or legacy command picker underneath it.
_god_search_offer_execution_rich() {
  local sorted_results tab query header_title header_subtitle menu_rows picker_status row_fields separator
  local line svc grp ent title risk native_run mode remaining_run native_tool missing_probe compatibility_kind compatibility_label runnable display original service catalog execution_path execution_mode
  local previous_service previous_catalog previous_execution_path previous_execution_mode previous_discover_probes previous_discover_tool
  local model model_tag model_value template pending selected_index storage_index row_index initial_selected first_row_runnable
  local -a values models rich_services rich_groups rich_entries rich_catalogs rich_execution_paths rich_risks

  sorted_results="$1"
  tab="$2"
  query="$3"
  header_title="${4:-SEARCH RESULTS}"
  header_subtitle="${5:-}"

  _god_stdout_is_terminal || return 1
  [ -n "$(type -t _god_menu_select_rich 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_execute_command 2>/dev/null)" ] || return 1
  [ -n "$(type -t _god_menu_style_init 2>/dev/null)" ] && _god_menu_style_init

  menu_rows=''
  separator="$(printf '\034')"
  models=()
  rich_services=()
  rich_groups=()
  rich_entries=()
  rich_catalogs=()
  rich_execution_paths=()
  rich_risks=()
  previous_service=''
  previous_catalog=''
  previous_execution_path=''
  previous_execution_mode=''
  previous_discover_probes=''
  previous_discover_tool=''
  row_index=0
  initial_selected=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    row_fields="$(printf '%s' "$line" | LC_ALL=C awk -F "$tab" -v separator="$separator" '{ printf "%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s", $3, separator, $4, separator, $5, separator, $6, separator, $8, separator, $7, separator, $13, separator, $14, separator, $15 }')"
    IFS="$separator" read -r svc grp ent title risk native_run mode compatibility_kind compatibility_label <<< "$row_fields"
    [ -n "$svc" ] || continue

    if [ "$svc" != "$previous_service" ]; then
      previous_catalog="$(_god_catalog_for "$svc" 2>/dev/null)" || return 1
      previous_execution_mode="$(_god_catalog_execution_mode "$previous_catalog")"
      case "$previous_execution_mode" in
        DISCOVER)
          previous_execution_path="$(_god_discover_path "$svc" 2>/dev/null)"
          previous_discover_probes="$(_god_catalog_discover_probes "$previous_catalog")"
          previous_discover_tool="$(_god_discover_tool "$svc" 2>/dev/null)"
          [ -n "$previous_discover_tool" ] || previous_discover_tool="$(_god_catalog_discover_value "$previous_catalog" probe)"
          ;;
        PATH)
          previous_execution_path=''
          previous_discover_probes=''
          previous_discover_tool=''
          ;;
        *) return 1 ;;
      esac
      previous_service=$svc
    fi
    [ -n "$previous_catalog" ] || return 1
    [ "$previous_execution_mode" != DISCOVER ] || [ -n "$previous_execution_path" ] || return 1

    # Version metadata is the human explanation, but a resolved discovery
    # directory is still the final authority. Check generic leading ./tools
    # once before the picker starts; navigation remains filesystem-free. PATH
    # services intentionally skip this because no one directory owns them.
    if [ "$previous_execution_mode" = DISCOVER ] && [ "$mode" != LOCAL ] && [ "$compatibility_kind" != blocked ]; then
      missing_probe="$(_god_search_discovered_tool_missing "$previous_execution_path" "$native_run" "$previous_discover_probes" "$previous_discover_tool")" || missing_probe=''
      if [ -n "$missing_probe" ]; then
        compatibility_kind=blocked
        compatibility_label="$missing_probe is not installed"
      else
        remaining_run=$native_run
        while [[ "$remaining_run" =~ (^|[[:space:]\|\;\&\(])\.\/([A-Za-z0-9._-]+) ]]; do
          native_tool=${BASH_REMATCH[2]}
          if [ ! -x "$previous_execution_path/$native_tool" ]; then
            compatibility_kind=blocked
            compatibility_label="$native_tool is not installed"
            break
          fi
          remaining_run=${remaining_run#*"./$native_tool"}
        done
      fi
    fi

    runnable=1
    [ "$compatibility_kind" = blocked ] && runnable=0

    row_index=$((row_index + 1))
    if [ "$runnable" = 1 ] && [ "$initial_selected" = 1 ] && [ "$row_index" -gt 1 ]; then
      # Prefer the first runnable row when higher-ranked results are visible
      # only for compatibility context.
      first_row_runnable="$(printf '%s' "$menu_rows" | LC_ALL=C awk -F "$tab" 'NR == 1 { print $4; exit }')"
      [ "$first_row_runnable" = 1 ] || initial_selected=$row_index
    fi
    menu_rows="${menu_rows:+$menu_rows
}$(printf '%s\t%s\t%s\t%s\t%s' "$title" "$compatibility_label" "$risk" "$runnable" '')"
    rich_services+=("$svc")
    rich_groups+=("$grp")
    rich_entries+=("$ent")
    rich_catalogs+=("$previous_catalog")
    rich_execution_paths+=("$previous_execution_path")
    rich_risks+=("$risk")
  done <<< "$sorted_results"
  [ -n "$menu_rows" ] || return 1

  _god_menu_select_rich "$menu_rows" '' "$initial_selected" _god_search_rich_detail_provider "$header_title" "$header_subtitle" _god_search_rich_detail_cached
  picker_status=$?
  [ "$picker_status" -eq 0 ] || return "$picker_status"
  [ "$_god_menu_choice" -ge 0 ] || return 0

  selected_index=$((_god_menu_choice + 1))
  _god_search_rich_detail_provider "$selected_index" || return 1
  if [ -n "${BASH_VERSION:-}" ]; then
    storage_index=$_god_menu_choice
  else
    storage_index=$selected_index
  fi
  service="${rich_services[$storage_index]:-}"
  catalog="${rich_catalogs[$storage_index]:-}"
  execution_path="${rich_execution_paths[$storage_index]:-}"
  group="${rich_groups[$storage_index]:-}"
  entry="${rich_entries[$storage_index]:-}"
  risk="${rich_risks[$storage_index]:-}"
  model="${models[$storage_index]:-}"
  [ -n "$service" ] && [ -n "$catalog" ] && [ -n "$group" ] && [ -n "$entry" ] && [ -n "$model" ] || return 1

  original=$_god_menu_provider_detail
  if [ -n "$_god_menu_edited_command" ] && [ "$_god_menu_edited_command" != "$original" ] && \
     [ -n "$(type -t _god_execute_edited 2>/dev/null)" ]; then
    _god_execute_edited "$_god_menu_edited_command" "$risk" 1
    return $?
  fi

  display=''
  template=''
  pending=0
  values=()
  while IFS="$tab" read -r model_tag model_value; do
    case "$model_tag" in
      DISPLAY) display=$model_value ;;
      TEMPLATE) template=$model_value ;;
      VALUE) values+=("$model_value") ;;
      PENDING) pending=1 ;;
    esac
  done <<< "$model"

  # Placeholder prompts happen only after the operator picks that row. A
  # fully prepared command takes the fast path and executes the exact safe
  # template that was already previewed, without another catalog parse.
  if [ "$pending" = 1 ] || [ -z "$template" ] || [ -z "$(type -t _god_execute_resolved 2>/dev/null)" ]; then
    _god_execute_command "$service" "$catalog" "$group" "$entry" "$execution_path" "$query" 1
  else
    _god_execute_resolved "$display" "$template" "$risk" 1 "${values[@]}"
  fi
}

_god_dispatch_search() {
  local scope_service scope_group search_mode search_view pattern query_arg_count token token_lower options_ended all_versions

  scope_service="$1"
  scope_group="$2"
  shift 2

  search_mode="smart"
  search_view="list"
  pattern=""
  query_arg_count=0
  options_ended=0
  all_versions=0

  case "$(_god_lower "${1:-}")" in
    --all|-a)
      search_mode="all"
      shift
      ;;
    --any|-y)
      search_mode="any"
      shift
      ;;
    --exact|-e)
      search_mode="exact"
      shift
      ;;
    --regex|-r)
      search_mode="regex"
      shift
      ;;
  esac

  if [ "${1:-}" = "--" ]; then
    options_ended=1
    shift
  fi

  while [ "$#" -gt 0 ]; do
    token="$1"
    token_lower="$(_god_lower "$token")"
    shift

    if [ "$options_ended" -eq 0 ]; then
      case "$token_lower" in
        --)
          options_ended=1
          continue
          ;;
        --all-versions)
          if [ "$query_arg_count" -eq 0 ]; then
            printf 'BASH_GOD: --all-versions needs search text before it.\n' >&2
            return 2
          fi
          all_versions=1
          continue
          ;;
        --tree)
          if [ "$query_arg_count" -eq 0 ]; then
            printf 'BASH_GOD: --tree needs search text before it.\n' >&2
            return 2
          fi
          search_view="tree"
          if [ "$#" -gt 0 ]; then
            case "$(_god_lower "$1")" in
              --full|full)
                search_view="tree-full"
                shift
                ;;
            esac
          fi
          if [ "$#" -ne 0 ]; then
            printf 'BASH_GOD: search view keys must be the final arguments.\n' >&2
            return 2
          fi
          break
          ;;
        --details)
          search_view="details"
          if [ "$#" -ne 0 ]; then
            printf 'BASH_GOD: search view keys must be the final arguments.\n' >&2
            return 2
          fi
          break
          ;;
        --keys)
          search_view="keys"
          if [ "$#" -ne 0 ]; then
            printf 'BASH_GOD: search view keys must be the final arguments.\n' >&2
            return 2
          fi
          break
          ;;
        --help|-h)
          search_view="help"
          if [ "$#" -ne 0 ]; then
            printf 'BASH_GOD: search view keys must be the final arguments.\n' >&2
            return 2
          fi
          break
          ;;
        --full|full)
          printf 'BASH_GOD: --full must follow --tree.\n' >&2
          return 2
          ;;
        --all|-a|--any|-y|--exact|-e|--regex|-r)
          printf 'BASH_GOD: search mode must immediately follow q or -q.\n' >&2
          return 2
          ;;
      esac
    fi

    if [ "$query_arg_count" -eq 0 ]; then
      pattern="$token"
    else
      pattern="$pattern $token"
    fi
    query_arg_count=$((query_arg_count + 1))
  done

  case "$search_view" in
    help|keys)
      _god_print_search_help "$scope_service" "$scope_group"
      return $?
      ;;
  esac

  if [ "$query_arg_count" -eq 0 ]; then
    printf "BASH_GOD: search expects text. Examples: god q offset; god q --regex 'offset|lag'\n" >&2
    return 2
  fi

  if { [ "$search_mode" = "regex" ] || [ "$search_mode" = "exact" ]; } && [ "$query_arg_count" -ne 1 ]; then
    printf 'BASH_GOD: %s search expects one quoted value.\n' "$search_mode" >&2
    if [ "$search_mode" = "regex" ]; then
      printf "Example: god q --regex 'offset|lag'\n" >&2
    else
      printf "Example: god q --exact 'consumer lag'\n" >&2
    fi
    return 2
  fi

  if ! _god_validate_query_text "$pattern"; then
    printf 'BASH_GOD: search text must contain visible characters and no control characters.\n' >&2
    return 2
  fi

  _god_search "$pattern" "$search_mode" "$search_view" "$scope_service" "$scope_group" "$all_versions"
}
