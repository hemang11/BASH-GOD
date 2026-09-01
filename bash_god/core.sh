# shellcheck shell=bash

# BASH_GOD's catalog reader. This file is intentionally silent when sourced.
# Catalog files are parsed as text and are never sourced or executed.

if [ -n "${BASH_VERSION:-}" ]; then
  _BASH_GOD_CORE_FILE="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _BASH_GOD_CORE_FILE="${(%):-%x}"
else
  _BASH_GOD_CORE_FILE="$0"
fi

_BASH_GOD_CORE_DIR="$(CDPATH= cd "$(dirname "$_BASH_GOD_CORE_FILE")" 2>/dev/null && pwd -P)"
_BASH_GOD_CATALOG_DIR="$_BASH_GOD_CORE_DIR/catalog"
_BASH_GOD_VERSION='0.0.2.4.3'
_BASH_GOD_LICENSE='MIT'
unset _BASH_GOD_CORE_FILE

_god_lower() {
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

_god_upper() {
  printf '%s' "$1" | LC_ALL=C tr '[:lower:]' '[:upper:]'
}

# _god_version_compare LEFT RIGHT
#
# Dotted-numeric comparison shared by search filtering and discovery.
# Missing components count as zero, so 3.9 and 3.9.0 are equal. Prints 1, -1,
# or 0 and always returns success.
_god_version_compare() {
  local left right total i lv rv
  local -a left_parts right_parts

  IFS='.' read -r -a left_parts <<< "$1"
  IFS='.' read -r -a right_parts <<< "$2"
  total=${#left_parts[@]}
  [ "${#right_parts[@]}" -gt "$total" ] && total=${#right_parts[@]}

  i=0
  while [ "$i" -lt "$total" ]; do
    lv="${left_parts[$i]:-0}"
    rv="${right_parts[$i]:-0}"
    case "$lv" in ''|*[!0-9]*) lv=0 ;; esac
    case "$rv" in ''|*[!0-9]*) rv=0 ;; esac
    lv=$((10#$lv))
    rv=$((10#$rv))
    if [ "$lv" -gt "$rv" ]; then printf '1\n'; return 0; fi
    if [ "$lv" -lt "$rv" ]; then printf -- '-1\n'; return 0; fi
    i=$((i + 1))
  done
  printf '0\n'
}

_god_style_init() {
  local locale_name color_mode output_fd

  locale_name="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  color_mode="$(_god_lower "${GOD_COLOR:-auto}")"
  output_fd="${1:-1}"

  case "$color_mode" in
    auto|always|never) ;;
    *)
      printf 'BASH_GOD: GOD_COLOR must be auto, always, or never.\n' >&2
      return 2
      ;;
  esac

  case "$(_god_upper "$locale_name")" in
    *UTF-8*|*UTF8*)
      _GOD_TOP_LEFT='╭'
      _GOD_TOP_RIGHT='╮'
      _GOD_BOTTOM_LEFT='╰'
      _GOD_BOTTOM_RIGHT='╯'
      _GOD_VERTICAL='│'
      _GOD_HORIZONTAL='─'
      _GOD_PATH_SEPARATOR='›'
      _GOD_BULLET='•'
      _GOD_TREE_BRANCH='├──'
      _GOD_TREE_LAST='└──'
      _GOD_TREE_PIPE='│   '
      _GOD_TREE_SPACE='    '
      ;;
    *)
      _GOD_TOP_LEFT='+'
      _GOD_TOP_RIGHT='+'
      _GOD_BOTTOM_LEFT='+'
      _GOD_BOTTOM_RIGHT='+'
      _GOD_VERTICAL='|'
      _GOD_HORIZONTAL='-'
      _GOD_PATH_SEPARATOR='>'
      _GOD_BULLET='-'
      _GOD_TREE_BRANCH='|--'
      _GOD_TREE_LAST='`--'
      _GOD_TREE_PIPE='|   '
      _GOD_TREE_SPACE='    '
      ;;
  esac

  _GOD_RESET=''
  _GOD_BOLD=''
  _GOD_DIM=''
  _GOD_BRAND=''
  _GOD_ACCENT=''
  _GOD_COMMAND=''
  _GOD_WARNING=''
  _GOD_ART_ROW_1=''
  _GOD_ART_ROW_2=''
  _GOD_ART_ROW_3=''
  _GOD_ART_ROW_4=''
  _GOD_ART_ROW_5=''
  _GOD_ART_ROW_6=''

  if [ -z "${NO_COLOR+x}" ]; then
    if [ "$color_mode" = "always" ] || {
      [ "$color_mode" != "never" ] &&
      [ "${TERM:-}" != "dumb" ] &&
      [ -t "$output_fd" ]
    }; then
      _GOD_RESET="$(printf '\033[0m')"
      _GOD_BOLD="$(printf '\033[1m')"
      _GOD_DIM="$(printf '\033[2m')"
      _GOD_BRAND="$(printf '\033[1;35m')"
      _GOD_ACCENT="$(printf '\033[1;36m')"
      _GOD_COMMAND="$(printf '\033[32m')"
      _GOD_WARNING="$(printf '\033[1;33m')"
      _GOD_ART_ROW_1="$(printf '\033[1;38;5;255m')"
      _GOD_ART_ROW_2="$(printf '\033[1;38;5;230m')"
      _GOD_ART_ROW_3="$(printf '\033[1;38;5;229m')"
      _GOD_ART_ROW_4="$(printf '\033[1;38;5;228m')"
      _GOD_ART_ROW_5="$(printf '\033[1;38;5;227m')"
      _GOD_ART_ROW_6="$(printf '\033[1;38;5;220m')"
    fi
  fi
}

_god_repeat() {
  local character count output

  character="$1"
  count="$2"
  output=""
  while [ "$count" -gt 0 ]; do
    output="${output}${character}"
    count=$((count - 1))
  done
  printf '%s' "$output"
}

_god_banner() {
  local title subtitle

  title="$1"
  subtitle="$2"

  printf '%s%s' "$_GOD_BRAND" "$_GOD_TOP_LEFT"
  _god_repeat "$_GOD_HORIZONTAL" 72
  printf '%s%s\n' "$_GOD_TOP_RIGHT" "$_GOD_RESET"
  printf '%s%s%s %-70.70s %s%s\n' "$_GOD_BRAND" "$_GOD_VERTICAL" "$_GOD_RESET$_GOD_BOLD" "$title" "$_GOD_BRAND$_GOD_VERTICAL" "$_GOD_RESET"
  if [ -n "$subtitle" ]; then
    printf '%s%s%s %-70.70s %s%s\n' "$_GOD_BRAND" "$_GOD_VERTICAL" "$_GOD_RESET$_GOD_DIM" "$subtitle" "$_GOD_BRAND$_GOD_VERTICAL" "$_GOD_RESET"
  fi
  printf '%s%s' "$_GOD_BRAND" "$_GOD_BOTTOM_LEFT"
  _god_repeat "$_GOD_HORIZONTAL" 72
  printf '%s%s\n' "$_GOD_BOTTOM_RIGHT" "$_GOD_RESET"
}

_god_section() {
  printf '\n%s%s%s\n\n' "$_GOD_BOLD" "$1" "$_GOD_RESET"
}

_god_print_version() {
  printf 'BASH_GOD %s\nLicense: %s\n' "$_BASH_GOD_VERSION" "$_BASH_GOD_LICENSE"
}

# Catalog parsing and normal terminal rendering are sourced before specialized views.
# shellcheck source=catalog.sh
. "$_BASH_GOD_CORE_DIR/catalog.sh" || return 1
# discover.sh only reads its own cache here; it never probes the filesystem
# unless a caller invokes _god_discover_resolve explicitly. Optional: an
# installation that predates it (or a runtime package built before T8 ships
# it) simply never has a detected version, so search's version filtering
# stays inert, same as a service with no @discover block at all.
if [ -r "$_BASH_GOD_CORE_DIR/discover.sh" ]; then
  # shellcheck source=discover.sh
  . "$_BASH_GOD_CORE_DIR/discover.sh" || return 1
fi
# shellcheck source=art.sh
. "$_BASH_GOD_CORE_DIR/art.sh" || return 1
# shellcheck source=render.sh
. "$_BASH_GOD_CORE_DIR/render.sh" || return 1

# Tree and search are separate concerns but share the validated catalog and style helpers above.
# shellcheck source=tree.sh
. "$_BASH_GOD_CORE_DIR/tree.sh" || return 1
# shellcheck source=search.sh
. "$_BASH_GOD_CORE_DIR/search.sh" || return 1

# menu.sh, resolve.sh, and execute.sh are the interactive execution path.
# Optional for the same reason as discover.sh above: an installation that
# predates them just never offers to run anything, same as any service with
# no @discover block.
if [ -r "$_BASH_GOD_CORE_DIR/menu.sh" ]; then
  # shellcheck source=menu.sh
  . "$_BASH_GOD_CORE_DIR/menu.sh" || return 1
fi
if [ -r "$_BASH_GOD_CORE_DIR/resolve.sh" ]; then
  # shellcheck source=resolve.sh
  . "$_BASH_GOD_CORE_DIR/resolve.sh" || return 1
fi
if [ -r "$_BASH_GOD_CORE_DIR/execute.sh" ]; then
  # shellcheck source=execute.sh
  . "$_BASH_GOD_CORE_DIR/execute.sh" || return 1
fi

_god_run_maintenance() {
  local action maintenance_file

  action=$1
  maintenance_file="$_BASH_GOD_CORE_DIR/maintenance.sh"
  if [ ! -r "$maintenance_file" ]; then
    if [ "$action" = uninstall ]; then
      printf 'BASH_GOD: self-maintenance is unavailable in this installation.\n' >&2
      printf 'Use the package manager or source checkout that installed BASH_GOD.\n' >&2
      return 2
    fi
    return 0
  fi
  command bash "$maintenance_file" "$action" "$_BASH_GOD_VERSION"
}

_god_print_unknown_service() {
  _god_style_init 2 || return $?
  printf 'BASH_GOD: unknown service %s. Names must match exactly (case-insensitive).\n\n' "$1" >&2
  _god_print_root_help >&2
}

_god_print_unknown_group() {
  _god_style_init 2 || return $?
  printf 'BASH_GOD: unknown group %s for service %s. Names must match exactly (case-insensitive).\n\n' "$2" "$1" >&2
  _god_print_service_help "$3" "$1" >&2
}

# _god_resync_service CATALOG SERVICE
#
# `god SERVICE --resync`: forces a fresh probe/root/scan/version resolution,
# ignoring whatever is already cached. A service with no @discover block has
# nothing to resync; that is not an error, just nothing to do.
_god_resync_service() {
  local catalog service status path tool version synced service_upper cmp connection_kind target

  catalog="$1"
  service="$2"

  if [ -z "$(type -t _god_discover_resolve 2>/dev/null)" ]; then
    printf 'BASH_GOD: discovery is unavailable in this installation.\n' >&2
    return 2
  fi
  if ! _god_catalog_has_discover "$catalog"; then
    printf 'BASH_GOD: %s has no @discover block; there is nothing to resync.\n' "$service" >&2
    return 2
  fi

  _god_discover_resolve "$service" "$catalog"
  status=$?
  case "$status" in
    0)
      path="$(_god_discover_path "$service")"
      tool="$(_god_discover_tool "$service")"
      version="$(_god_discover_version "$service")"
      service_upper="$(printf '%s' "$service" | LC_ALL=C tr '[:lower:]' '[:upper:]')"

      _god_banner "${service_upper} RESYNCED" 'Re-probed this machine and refreshed client details and, where applicable, its target.'
      printf '  %s%-9s%s %s\n' "$_GOD_DIM" 'Path' "$_GOD_RESET" "$path"
      [ -z "$tool" ] || printf '  %s%-9s%s %s\n' "$_GOD_DIM" 'Tool' "$_GOD_RESET" "$tool"
      printf '  %s%-9s%s %s\n' "$_GOD_DIM" 'Version' "$_GOD_RESET" "${version:-unknown}"
      connection_kind="$(_god_catalog_connection_kind "$catalog")"
      if [ "$connection_kind" = ENDPOINT ]; then
        target="$(_god_discover_target "$service" 2>/dev/null)"
        printf '  %s%-9s%s %s\n' "$_GOD_DIM" 'Target' "$_GOD_RESET" "${target:-unresolved}"
      fi

      if [ "${version:-unknown}" = "unknown" ]; then
        printf '\n  %sCould not read a version number from this install; search will show every variant, unfiltered.%s\n' \
          "$_GOD_DIM" "$_GOD_RESET"
      else
        synced="$(_god_catalog_synced "$catalog" 2>/dev/null)"
        if [ -n "$synced" ]; then
          cmp="$(_god_version_compare "$version" "$synced")"
          if [ "$cmp" -gt 0 ]; then
            printf '\n  %sHeads up%s : Catalog was last checked against %s %s; You are running %s %s. Flags may differ — see %sgod %s native%s\n' \
              "$_GOD_WARNING" "$_GOD_RESET" "$service" "$synced" "$service" "$version" "$_GOD_COMMAND" "$service" "$_GOD_RESET"
          fi
        fi
      fi

      printf '\n  %sTry:%s %sgod %s q WORDS%s\n' "$_GOD_DIM" "$_GOD_RESET" "$_GOD_COMMAND" "$service" "$_GOD_RESET"
      return 0
      ;;
    *)
      printf 'BASH_GOD: could not find %s on this machine (checked PATH and the usual install locations).\n' "$service" >&2
      printf 'BASH_GOD: installed somewhere else? Add "path=<bin-directory>" to %s and resync again.\n' \
        "$(_god_discover_config_file "$service" 2>/dev/null || printf '~/.config/bash-god/%s.conf' "$service")" >&2
      return 1
      ;;
  esac
}

# Re-probe every catalog which owns an installed-tool-family discovery block.
# PATH-only catalogs intentionally do not participate because they have no
# single tool family or service-version cache to refresh. A missing optional
# tool is a normal result here, so a whole-machine resync reports it inline
# and still completes successfully.
_god_resync_all() {
  local catalog_files file catalog service probe path tool version total resolved

  if [ -z "$(type -t _god_discover_resolve 2>/dev/null)" ]; then
    printf 'BASH_GOD: discovery is unavailable in this installation.\n' >&2
    return 2
  fi

  catalog_files="$(_god_catalog_files)" || return 2
  total=0
  resolved=0

  _god_banner 'BASH_GOD / RESYNC' \
    'Refreshing catalog-declared tools, detected versions, and endpoint targets where applicable.'
  printf '\n'

  while IFS= read -r file; do
    _god_is_catalog_file "$file" || continue
    catalog=$file
    _god_catalog_has_discover "$catalog" || continue
    service="$(_god_service_name_for_catalog "$catalog")" || return 2
    total=$((total + 1))

    if _god_discover_resolve "$service" "$catalog"; then
      path="$(_god_discover_path "$service")"
      tool="$(_god_discover_tool "$service")"
      version="$(_god_discover_version "$service")"
      if [ -n "$tool" ]; then
        if [ "${version:-unknown}" = unknown ]; then
          printf '  %s%-16s%s %s%s%s %s(via %s · version unavailable)%s\n' \
            "$_GOD_ACCENT" "$service" "$_GOD_RESET" \
            "$_GOD_COMMAND" "$path" "$_GOD_RESET" \
            "$_GOD_DIM" "$tool" "$_GOD_RESET"
        else
          printf '  %s%-16s%s %s%s%s %s(via %s · v%s)%s\n' \
            "$_GOD_ACCENT" "$service" "$_GOD_RESET" \
            "$_GOD_COMMAND" "$path" "$_GOD_RESET" \
            "$_GOD_DIM" "$tool" "$version" "$_GOD_RESET"
        fi
      else
        printf '  %s%-16s%s %s%s%s %s(version %s)%s\n' \
          "$_GOD_ACCENT" "$service" "$_GOD_RESET" \
          "$_GOD_COMMAND" "$path" "$_GOD_RESET" \
          "$_GOD_DIM" "${version:-unknown}" "$_GOD_RESET"
      fi
      resolved=$((resolved + 1))
    else
      probe="$(_god_catalog_discover_value "$catalog" probe)"
      printf '  %s%-16s%s %snot found (%s)%s\n' \
        "$_GOD_ACCENT" "$service" "$_GOD_RESET" \
        "$_GOD_DIM" "${probe:-tool}" "$_GOD_RESET"
    fi
  done <<< "$catalog_files"

  if [ "$total" -eq 0 ]; then
    printf '  %sNo service in this installation supports automatic path detection.%s\n' \
      "$_GOD_DIM" "$_GOD_RESET"
    return 0
  fi

  printf '\n  %s%d of %d detectable services refreshed.%s\n' \
    "$_GOD_DIM" "$resolved" "$total" "$_GOD_RESET"
  if [ "$resolved" -lt "$total" ]; then
    printf '  %sFor one service, set its configured path and run god SERVICE --resync again.%s\n' \
      "$_GOD_DIM" "$_GOD_RESET"
  fi
  return 0
}

god() {
  local first first_lower catalog service second second_lower group third third_lower tree_full argument parent_call_depth parent_quiet maintenance_status
  local -a god_arguments

  parent_call_depth="${_GOD_CALL_DEPTH:-0}"
  parent_quiet="${_GOD_QUIET:-0}"
  local _GOD_CALL_DEPTH
  local _GOD_QUIET
  case "$parent_call_depth" in
    1|2) _GOD_CALL_DEPTH=2 ;;
    *) _GOD_CALL_DEPTH=1 ;;
  esac
  _GOD_QUIET="$parent_quiet"
  god_arguments=()
  for argument in "$@"; do
    if [ "$(_god_lower "$argument")" = "--quiet" ]; then
      _GOD_QUIET=1
    else
      god_arguments+=("$argument")
    fi
  done
  set -- "${god_arguments[@]}"

  if [ "$_GOD_CALL_DEPTH" = 1 ]; then
    _god_print_command_spacing
  fi
  if [ "$#" -gt 0 ] && [ "$(_god_lower "$1")" = "--uninstall" ]; then
    if [ "$#" -ne 1 ]; then
      printf 'BASH_GOD: --uninstall does not accept additional arguments.\n' >&2
      return 2
    fi
    _god_run_maintenance uninstall
    return $?
  fi
  _god_style_init || return $?
  _god_validate_all_catalogs || return $?

  if [ "$#" -eq 0 ]; then
    if [ "$_GOD_CALL_DEPTH" = 1 ] && [ "$_GOD_QUIET" != 1 ] && _god_stdout_is_terminal; then
      _god_run_maintenance check
      maintenance_status=$?
      case "$maintenance_status" in
        0) ;;
        10) return 0 ;;
        *) return "$maintenance_status" ;;
      esac
    fi
    _god_print_home_art
    _god_print_root_help
    return $?
  fi

  first="$1"
  first_lower="$(_god_lower "$first")"
  shift

  case "$first_lower" in
    keys|--keys)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: root --keys does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_view_keys
      return $?
      ;;
    details|--details)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: root --details does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_root_details
      return $?
      ;;
    paths|--paths)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: root --paths does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_discovered_paths
      return $?
      ;;
    resync|--resync)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: root --resync does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_resync_all
      return $?
      ;;
    full|--full)
      printf 'BASH_GOD: --full must follow --tree.\n' >&2
      return 2
      ;;
    version|--version|-v)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: version does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_version
      return $?
      ;;
    help|--help|-h)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: god help does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_root_help
      return $?
      ;;
    tree|--tree)
      if [ "$#" -eq 0 ]; then
        _god_print_root_tree 0
        return $?
      fi
      case "$(_god_lower "$1")" in
        full|--full)
          if [ "$#" -ne 1 ]; then
            printf 'BASH_GOD: root --tree --full does not accept additional arguments.\n' >&2
            return 2
          fi
          _god_print_root_tree 1
          return $?
          ;;
      esac
      if [ "$#" -gt 3 ]; then
        printf 'BASH_GOD: tree accepts SERVICE, optional GROUP, and optional --full.\n' >&2
        return 2
      fi
      case "$(_god_lower "$1")" in
        tree|--tree)
          printf 'BASH_GOD: tree cannot be nested under tree.\n' >&2
          return 2
          ;;
      esac
      if [ "$#" -eq 2 ]; then
        case "$(_god_lower "$2")" in
          full|--full)
            god "$1" --tree --full
            return $?
            ;;
        esac
      fi
      if [ "$#" -eq 3 ]; then
        case "$(_god_lower "$3")" in
          full|--full)
            god "$1" "$2" --tree --full
            return $?
            ;;
          *)
            printf 'BASH_GOD: the only third tree argument is --full.\n' >&2
            return 2
            ;;
        esac
      fi
      god "$@" --tree
      return $?
      ;;
    q|-q)
      _god_dispatch_search "" "" "$@"
      return $?
      ;;
  esac

  if ! _god_is_route_token "$first"; then
    printf 'BASH_GOD: invalid service token. Use letters, numbers, hyphens, or underscores.\n' >&2
    return 2
  fi

  catalog="$(_god_catalog_for "$first")" || {
    _god_print_unknown_service "$first"
    return 2
  }
  service="$(_god_service_name_for_catalog "$catalog")" || return 2

  if ! _god_validate_catalog "$catalog"; then
    return 2
  fi

  if [ "$#" -eq 0 ]; then
    _god_print_service_help "$catalog" "$service"
    return $?
  fi

  second="$1"
  second_lower="$(_god_lower "$second")"
  shift

  if ! _god_is_route_token "$second"; then
    printf 'BASH_GOD: invalid group token. Use letters, numbers, hyphens, or underscores.\n' >&2
    return 2
  fi

  case "$second_lower" in
    q|-q)
      _god_dispatch_search "$service" "" "$@"
      return $?
      ;;
    keys|--keys)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: service --keys does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_view_keys "$service"
      return $?
      ;;
    help|--help|-h)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: service help does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_service_help "$catalog" "$service"
      return $?
      ;;
    details|--details|-v)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: service --details does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_print_service_details "$catalog" "$service"
      return $?
      ;;
    resync|--resync)
      if [ "$#" -ne 0 ]; then
        printf 'BASH_GOD: service --resync does not accept additional arguments.\n' >&2
        return 2
      fi
      _god_resync_service "$catalog" "$service"
      return $?
      ;;
    full|--full)
      printf 'BASH_GOD: --full must follow --tree.\n' >&2
      return 2
      ;;
    --tree|tree)
      tree_full=0
      if [ "$#" -eq 1 ]; then
        case "$(_god_lower "$1")" in
          full|--full) tree_full=1 ;;
          *)
            printf 'BASH_GOD: service --tree accepts only optional --full.\n' >&2
            return 2
            ;;
        esac
      elif [ "$#" -gt 1 ]; then
        printf 'BASH_GOD: service --tree accepts only optional --full.\n' >&2
        return 2
      fi
      _god_print_tree_for_catalog "$catalog" "$service" "" "$tree_full"
      return $?
      ;;
  esac

  group="$(_god_group_name "$catalog" "$second")" || {
    _god_print_unknown_group "$service" "$second" "$catalog"
    return 2
  }

  if [ "$#" -eq 0 ]; then
    _god_print_catalog_compact "$catalog" "$service" "$group"
    return $?
  fi

  third="$1"
  third_lower="$(_god_lower "$third")"
  shift

  if [ "$third_lower" = "q" ] || [ "$third_lower" = "-q" ]; then
    _god_dispatch_search "$service" "$group" "$@"
    return $?
  fi

  if [ "$third_lower" = "--tree" ] || [ "$third_lower" = "tree" ]; then
    tree_full=0
    if [ "$#" -eq 1 ]; then
      case "$(_god_lower "$1")" in
        full|--full) tree_full=1 ;;
        *)
          printf 'BASH_GOD: group --tree accepts only optional --full.\n' >&2
          return 2
          ;;
      esac
    elif [ "$#" -gt 1 ]; then
      printf 'BASH_GOD: group --tree accepts only optional --full.\n' >&2
      return 2
    fi
    _god_print_tree_for_catalog "$catalog" "$service" "$group" "$tree_full"
    return $?
  fi

  if [ "$third_lower" = "--full" ] || [ "$third_lower" = "full" ]; then
    printf 'BASH_GOD: --full must follow --tree.\n' >&2
    return 2
  fi

  if [ "$#" -ne 0 ]; then
    _god_style_init 2 || return $?
    printf 'BASH_GOD: too many arguments after %s %s.\n\n' "$service" "$group" >&2
    _god_print_group_help "$catalog" "$service" "$group" >&2
    return 2
  fi

  case "$third_lower" in
    keys|--keys)
      _god_print_view_keys "$service" "$group"
      return $?
      ;;
    help|--help|-h)
      _god_print_group_help "$catalog" "$service" "$group"
      return $?
      ;;
    details|--details|-v)
      _god_print_catalog_entry "$catalog" "$service" "$group" "all"
      return $?
      ;;
    *)
      case "$third" in
        *[!0-9]*) ;;
        *)
          _god_print_catalog_entry "$catalog" "$service" "$group" "$third"
          return $?
          ;;
      esac
      _god_style_init 2 || return $?
      printf 'BASH_GOD: command titles are knowledge entries, not executable GOD routes.\n\n' >&2
      _god_print_group_help "$catalog" "$service" "$group" >&2
      return 2
      ;;
  esac
}
