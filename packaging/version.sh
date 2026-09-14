#!/usr/bin/env bash

# Shared package-version helpers. This file is sourced by build tooling only;
# it deliberately changes no caller shell options or global configuration.

_bash_god_package_version_valid() {
  case "${1:-}" in
    ''|*[!0-9.]*) return 1 ;;
    *..*|.*|*.) return 1 ;;
    *) return 0 ;;
  esac
}

_bash_god_package_version_from_core() {
  local core version

  core=$1
  [ -r "$core" ] || return 1
  version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$core")" || return 1
  _bash_god_package_version_valid "$version" || return 1
  printf '%s\n' "$version"
}

_bash_god_package_debian_version() {
  local version revision

  version=$1
  revision=${2:-1}
  _bash_god_package_version_valid "$version" || return 1
  case "$revision" in
    ''|*[!0-9]*|0*) return 1 ;;
  esac
  # The runtime version is Debian's upstream version. Package metadata and
  # control-file-only revisions increment the Debian revision independently.
  printf '%s-%s\n' "$version" "$revision"
}
