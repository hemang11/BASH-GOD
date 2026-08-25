# shellcheck shell=bash

# Terminal artwork used only by the root dashboard. Sourcing this module is silent.

_god_print_home_art() {
  local slogan

  slogan='Your DevOps command memory. Native commands, zero execution.'

  printf '\n%s BASH_GOD%s\n\n' "$_GOD_BRAND$_GOD_BOLD" "$_GOD_RESET"
  printf '%s .----------------------------------------------------------------.%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s |%s %-63s%s|%s\n' "$_GOD_BRAND" "$_GOD_RESET$_GOD_BOLD" "$slogan" "$_GOD_BRAND" "$_GOD_RESET"
  printf "%s '------.---------------------------------------------------------'%s\n" "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s         \\\n' "$_GOD_BRAND"
  printf '%s       .-============-.%s\n' "$_GOD_ACCENT" "$_GOD_RESET"
  printf '%s          .-""""""""-.%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf "%s        .'            '.%s\n" "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s       /   .--------.   \\%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s      |   / _      _ \\   |%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s      |  | (o)    (o) |  |%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s      |  |     /\\     |  |%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s      |  |   .____.   |  |%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s       \\  \\  \\____/  /  /%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf "%s        '._'.      .'_.'%s\n" "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s           \\ /\\/\\/\\ /%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s            \\/\\/\\/\\/%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s             \\||||/%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s              \\__/%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s       _______/  \\_______%s\n' "$_GOD_BRAND" "$_GOD_RESET"
  printf '%s      /        --+--       \\%s\n' "$_GOD_ACCENT" "$_GOD_RESET"
  printf '%s     /___________|__________\\%s\n' "$_GOD_ACCENT" "$_GOD_RESET"
}
