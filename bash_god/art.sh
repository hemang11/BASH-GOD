# shellcheck shell=bash

# Pre-rendered terminal artwork for the bare interactive `god` dashboard.
# No banner generator is needed at runtime, and sourcing this module is silent.

_god_stdout_is_terminal() {
  [ -t 1 ]
}

_god_print_command_spacing() {
  _god_stdout_is_terminal || return 0
  printf '\n'
}

_god_print_home_art() {
  [ "${_GOD_QUIET:-0}" != "1" ] || return 0
  _god_stdout_is_terminal || return 0

  printf '%s██████╗  █████╗ ███████╗██╗  ██╗    ██████╗  ██████╗ ██████╗%s\n' "$_GOD_ART_ROW_1" "$_GOD_RESET"
  printf '%s██╔══██╗██╔══██╗██╔════╝██║  ██║   ██╔════╝ ██╔═══██╗██╔══██╗%s\n' "$_GOD_ART_ROW_2" "$_GOD_RESET"
  printf '%s██████╔╝███████║███████╗███████║   ██║  ███╗██║   ██║██║  ██║%s\n' "$_GOD_ART_ROW_3" "$_GOD_RESET"
  printf '%s██╔══██╗██╔══██║╚════██║██╔══██║   ██║   ██║██║   ██║██║  ██║%s\n' "$_GOD_ART_ROW_4" "$_GOD_RESET"
  printf '%s██████╔╝██║  ██║███████║██║  ██║   ╚██████╔╝╚██████╔╝██████╔╝%s\n' "$_GOD_ART_ROW_5" "$_GOD_RESET"
  printf '%s╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝%s\n' "$_GOD_ART_ROW_6" "$_GOD_RESET"
  printf '\n%sYour DevOps command memory. Native commands, zero execution.%s\n\n' "$_GOD_BOLD" "$_GOD_RESET"
}
