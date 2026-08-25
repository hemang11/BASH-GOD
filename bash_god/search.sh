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
  printf '%s  Results are always commands; BASH_GOD never executes them.%s\n' "$_GOD_DIM" "$_GOD_RESET"
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
        printf "%d\t%d\t%s\t%s\t%d\t%s\t%s\t%s\n", score, match_coverage, service, group, entry_number, command_title, run_command, risk
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
      field = ""
      metadata = ""
      details = ""
      run_command = ""
      next
    }

    in_command && /^@mode[[:space:]]+/ {
      value = $0
      sub(/^@mode[[:space:]]+/, "", value)
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
  local sorted_results tab search_mode score coverage service group entry title run_command risk result_route

  sorted_results="$1"
  tab="$2"
  search_mode="$3"

  _god_section 'MATCHING OPERATIONS'
  printf '%s  %-32s %s%s\n' "$_GOD_DIM" 'OPEN' 'OPERATION' "$_GOD_RESET"
  printf '%s  %-32s %s%s\n' "$_GOD_DIM" '--------------------------------' '----------------------------------------------' "$_GOD_RESET"

  while IFS="$tab" read -r score coverage service group entry title run_command risk; do
    [ -n "$service" ] || continue
    result_route="god $service $group $entry"
    printf '  %s%-32s%s %s%s%s' "$_GOD_ACCENT" "$result_route" "$_GOD_RESET" "$_GOD_BOLD" "$title" "$_GOD_RESET"
    [ -z "$risk" ] || printf ' %s[%s]%s' "$_GOD_WARNING" "$risk" "$_GOD_RESET"
    printf '\n'
  done <<< "$sorted_results"

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
  local sorted_results tab search_title search_label score coverage service group entry title run_command risk catalog

  sorted_results="$1"
  tab="$2"
  search_title="$3"
  search_label="$4"

  _god_banner "$search_title DETAILS" "$search_label"
  printf '%s  Every matching operation is expanded below; catalog commands remain inert.%s\n' "$_GOD_DIM" "$_GOD_RESET"

  while IFS="$tab" read -r score coverage service group entry title run_command risk; do
    [ -n "$service" ] || continue
    catalog="$(_god_catalog_for "$service")" || return 2
    printf '\n'
    _god_print_catalog_entry "$catalog" "$service" "$group" "$entry" 1 || return $?
  done <<< "$sorted_results"
}

_god_search() {
  local pattern search_mode search_view scope_service scope_group scope_description file service found search_status catalog_output search_title search_label catalog_files
  local search_results sorted_results tab max_coverage

  pattern="$1"
  search_mode="$2"
  search_view="${3:-list}"
  scope_service="${4:-}"
  scope_group="${5:-}"
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
      _god_banner "$search_title RESULTS" "$search_label"
      _god_render_search_list "$sorted_results" "$tab" "$search_mode"
      ;;
  esac
}

_god_dispatch_search() {
  local scope_service scope_group search_mode search_view pattern query_arg_count token token_lower options_ended

  scope_service="$1"
  scope_group="$2"
  shift 2

  search_mode="smart"
  search_view="list"
  pattern=""
  query_arg_count=0
  options_ended=0

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

  _god_search "$pattern" "$search_mode" "$search_view" "$scope_service" "$scope_group"
}
