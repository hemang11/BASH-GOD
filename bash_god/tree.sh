# shellcheck shell=bash

# Tree rendering for BASH_GOD. This module is sourced by core.sh.

_god_render_tree_groups() {
  local catalog group prefix tree_depth

  catalog="$1"
  group="$2"
  prefix="$3"
  tree_depth="$4"

  LC_ALL=C awk \
    -v wanted="$group" \
    -v prefix="$prefix" \
    -v tree_depth="$tree_depth" \
    -v branch="$_GOD_TREE_BRANCH" \
    -v last="$_GOD_TREE_LAST" \
    -v pipe="$_GOD_TREE_PIPE" \
    -v space="$_GOD_TREE_SPACE" \
    -v accent="$_GOD_ACCENT" \
    -v bold="$_GOD_BOLD" \
    -v dim="$_GOD_DIM" \
    -v reset="$_GOD_RESET" '
    /^@group[[:space:]]+/ {
      group_count++
      groups[group_count] = $0
      sub(/^@group[[:space:]]+/, "", groups[group_count])
      next
    }

    /^@command[[:space:]]+/ {
      counts[group_count]++
      titles[group_count, counts[group_count]] = $0
      sub(/^@command[[:space:]]+/, "", titles[group_count, counts[group_count]])
      field = ""
      next
    }

    $0 == "@run" {
      field = "run"
      next
    }

    /^@/ {
      field = ""
      next
    }

    field == "run" && $0 != "" {
      runs[group_count, counts[group_count]] = $0
      field = ""
    }

    END {
      selected_count = 0
      for (i = 1; i <= group_count; i++) {
        if (wanted == "" || tolower(groups[i]) == tolower(wanted)) selected_count++
      }

      selected_position = 0
      for (i = 1; i <= group_count; i++) {
        if (wanted != "" && tolower(groups[i]) != tolower(wanted)) continue
        selected_position++
        group_is_last = selected_position == selected_count
        group_connector = group_is_last ? last : branch
        printf "%s%s %s%s%s %s(%d)%s\n", prefix, group_connector, bold, groups[i], reset, dim, counts[i], reset

        if (tree_depth >= 1) {
          child_prefix = prefix (group_is_last ? space : pipe)
          for (j = 1; j <= counts[i]; j++) {
            command_is_last = j == counts[i]
            command_connector = command_is_last ? last : branch
            printf "%s%s %s%02d%s %s%s%s\n", child_prefix, command_connector, accent, j, reset, dim, titles[i, j], reset
            if (tree_depth >= 2) {
              command_prefix = child_prefix (command_is_last ? space : pipe)
              printf "%s%s %s$ %s%s\n", command_prefix, last, dim, runs[i, j], reset
            }
          }
        }
      }
    }
  ' "$catalog" || return 2
}

_god_print_tree_for_catalog() {
  local catalog service group full banner_title banner_subtitle command_count tree_depth

  catalog="$1"
  service="$2"
  group="$3"
  full="${4:-0}"
  command_count="$(LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$catalog")" || return 2
  banner_title="$(_god_upper "$service") TREE"
  [ -z "$group" ] || banner_title="$banner_title / $(_god_upper "$group")"

  if [ "$full" = "1" ]; then
    banner_subtitle='full hierarchy with native command lines'
    tree_depth=2
  elif [ -n "$group" ]; then
    banner_subtitle='one group with numbered rows'
    tree_depth=1
  else
    banner_subtitle='compact group map'
    tree_depth=0
  fi

  printf '%s%s%s  %s%s%s\n' "$_GOD_BOLD" "$banner_title" "$_GOD_RESET" "$_GOD_DIM" "$banner_subtitle" "$_GOD_RESET"
  if [ -n "$group" ]; then
    printf '%s%s%s\n' "$_GOD_ACCENT" "$service" "$_GOD_RESET"
  else
    printf '%s%s%s %s(%s commands)%s\n' "$_GOD_ACCENT" "$service" "$_GOD_RESET" "$_GOD_DIM" "$command_count" "$_GOD_RESET"
  fi
  _god_render_tree_groups "$catalog" "$group" "" "$tree_depth" || return 2

  if [ "$full" != "1" ]; then
    if [ -n "$group" ]; then
      printf '\n%s  Include commands: %sgod %s %s --tree --full%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "$service" "$group" "$_GOD_RESET"
      return 0
    fi
    printf '\n%s  Open one branch: %sgod %s GROUP --tree%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "$service" "$_GOD_RESET"
    printf '%s  Exhaustive tree: %sgod %s --tree --full%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "$service" "$_GOD_RESET"
  fi
}

_god_print_root_tree() {
  local full file service catalog_files service_count service_position command_count total_commands connector child_prefix subtitle tree_depth

  full="${1:-0}"
  catalog_files="$(_god_catalog_files)" || return 2
  service_count=0
  total_commands=0
  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    _god_validate_catalog "$file" || return 2
    service_count=$((service_count + 1))
    command_count="$(LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$file")" || return 2
    total_commands=$((total_commands + command_count))
  done <<< "$catalog_files"

  if [ "$full" = "1" ]; then
    subtitle='full hierarchy with native command lines'
    tree_depth=2
  else
    subtitle='compact service and group map'
    tree_depth=0
  fi
  printf '%sBASH_GOD TREE%s  %s%s%s\n' "$_GOD_BOLD" "$_GOD_RESET" "$_GOD_DIM" "$subtitle" "$_GOD_RESET"
  printf '%sBASH_GOD%s %s(%s commands)%s\n' "$_GOD_BRAND" "$_GOD_RESET" "$_GOD_DIM" "$total_commands" "$_GOD_RESET"

  service_position=0
  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    service_position=$((service_position + 1))
    service="$(_god_service_name_for_catalog "$file")" || return 2
    command_count="$(LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$file")" || return 2
    if [ "$service_position" -eq "$service_count" ]; then
      connector="$_GOD_TREE_LAST"
      child_prefix="$_GOD_TREE_SPACE"
    else
      connector="$_GOD_TREE_BRANCH"
      child_prefix="$_GOD_TREE_PIPE"
    fi
    printf '%s %s%s%s %s(%s)%s\n' "$connector" "$_GOD_ACCENT" "$service" "$_GOD_RESET" "$_GOD_DIM" "$command_count" "$_GOD_RESET"
    _god_render_tree_groups "$file" "" "$child_prefix" "$tree_depth" || return 2
  done <<< "$catalog_files"

  if [ "$full" != "1" ]; then
    printf '\n%s  Open one branch: %sgod SERVICE GROUP --tree%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "$_GOD_RESET"
    printf '%s  Exhaustive tree: %sgod --tree --full%s\n' "$_GOD_DIM" "$_GOD_COMMAND" "$_GOD_RESET"
  fi
}
