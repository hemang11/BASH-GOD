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
_BASH_GOD_VERSION='0.0.1.1'
_BASH_GOD_LICENSE='MIT'
unset _BASH_GOD_CORE_FILE

_god_lower() {
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

_god_upper() {
  printf '%s' "$1" | LC_ALL=C tr '[:lower:]' '[:upper:]'
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
# shellcheck source=art.sh
. "$_BASH_GOD_CORE_DIR/art.sh" || return 1
# shellcheck source=render.sh
. "$_BASH_GOD_CORE_DIR/render.sh" || return 1

# Tree and search are separate concerns but share the validated catalog and style helpers above.
# shellcheck source=tree.sh
. "$_BASH_GOD_CORE_DIR/tree.sh" || return 1
# shellcheck source=search.sh
. "$_BASH_GOD_CORE_DIR/search.sh" || return 1

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

god() {
  local first first_lower catalog service second second_lower group third third_lower tree_full argument parent_call_depth parent_quiet
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
  _god_style_init || return $?
  _god_validate_all_catalogs || return $?

  if [ "$#" -eq 0 ]; then
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
