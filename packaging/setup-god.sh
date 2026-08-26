#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

_setup_god_repository='hemang11/BASH-GOD'
_setup_god_latest_url="https://github.com/${_setup_god_repository}/releases/latest"
_setup_god_download_dir=''

_setup_god_die() {
  printf 'BASH_GOD setup: %s\n' "$1" >&2
  exit 1
}

_setup_god_usage() {
  printf 'Usage: %s [--uninstall]\n' "$0"
  printf '\nInstall or update BASH_GOD from its latest published GitHub Release.\n'
  printf 'The managed installation prefix is $HOME/.local.\n'
  printf '\nState-driven behavior:\n'
  printf '  not installed       offer the latest release installation\n'
  printf '  older installation  offer an update to the latest release\n'
  printf '  current/newer        offer uninstall only; never reinstall or downgrade\n'
  printf '\nOptions:\n'
  printf '  --uninstall          offer removal of the managed installation directly\n'
  printf '  --help, -h           show this help\n'
  printf '\nShell startup files and previous-version backups are never removed or edited.\n'
}

_setup_god_cleanup() {
  if [ -n "$_setup_god_download_dir" ] && [ -d "$_setup_god_download_dir" ]; then
    command rm -rf -- "$_setup_god_download_dir"
  fi
}

_setup_god_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  else
    _setup_god_die 'sha256sum or shasum is required to verify release files.'
  fi
}

_setup_god_verify() {
  _setup_god_verify_file=$1
  _setup_god_verify_checksum=$2
  _setup_god_verify_name=${_setup_god_verify_file##*/}

  if ! _setup_god_verify_expected="$(LC_ALL=C awk -v file="$_setup_god_verify_name" '
    $2 == file || $2 == "*" file { count++; hash = $1; fields = NF }
    END { if (count == 1 && fields == 2) print hash; else exit 1 }
  ' "$_setup_god_verify_checksum")"; then
    _setup_god_die "invalid checksum file for $_setup_god_verify_name"
  fi
  case "$_setup_god_verify_expected" in
    ''|*[!0-9A-Fa-f]*) _setup_god_die "invalid SHA-256 value for $_setup_god_verify_name" ;;
  esac
  [ "${#_setup_god_verify_expected}" -eq 64 ] || \
    _setup_god_die "invalid SHA-256 length for $_setup_god_verify_name"

  _setup_god_verify_actual="$(_setup_god_sha256 "$_setup_god_verify_file")"
  _setup_god_verify_expected="$(printf '%s' "$_setup_god_verify_expected" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  _setup_god_verify_actual="$(printf '%s' "$_setup_god_verify_actual" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [ "$_setup_god_verify_expected" = "$_setup_god_verify_actual" ] || \
    _setup_god_die "SHA-256 verification failed for $_setup_god_verify_name"
}

_setup_god_version_is_valid() {
  case "$1" in
    ''|.*|*.|*..*|*[!0-9.]*) return 1 ;;
    *) return 0 ;;
  esac
}

_setup_god_fetch_latest_version() {
  command -v curl >/dev/null 2>&1 || return 1
  _setup_god_fetch_url="$(curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 20 \
    -o /dev/null -w '%{url_effective}' "$_setup_god_latest_url" 2>/dev/null)" || return 1
  _setup_god_fetch_url=${_setup_god_fetch_url%/}
  _setup_god_fetch_tag=${_setup_god_fetch_url##*/}
  case "$_setup_god_fetch_tag" in
    v[0-9]*) _setup_god_fetch_version=${_setup_god_fetch_tag#v} ;;
    *) return 1 ;;
  esac
  _setup_god_version_is_valid "$_setup_god_fetch_version" || return 1
  [ "$_setup_god_fetch_url" = \
    "https://github.com/${_setup_god_repository}/releases/tag/$_setup_god_fetch_tag" ] || return 1
  printf '%s\n' "$_setup_god_fetch_version"
}

_setup_god_launcher_has_marker() {
  while IFS= read -r _setup_god_marker_line || [ -n "$_setup_god_marker_line" ]; do
    if [ "$_setup_god_marker_line" = \
      '# Real-file launcher installed at PREFIX/bin/god by the runtime package.' ]; then
      return 0
    fi
  done < "$_setup_god_launcher"
  return 1
}

_setup_god_is_managed() {
  [ ! -L "$_setup_god_launcher" ] &&
    [ -f "$_setup_god_launcher" ] &&
    [ -x "$_setup_god_launcher" ] &&
    _setup_god_launcher_has_marker &&
    [ ! -L "$_setup_god_runtime" ] &&
    [ -d "$_setup_god_runtime" ] &&
    [ -x "$_setup_god_runtime/god" ] &&
    [ -r "$_setup_god_runtime/bash_god/core.sh" ]
}

_setup_god_installed_version() {
  _setup_god_version_core="$_setup_god_runtime/bash_god/core.sh"
  _setup_god_version_value=''

  # Read version metadata as text. Never source or execute an installed runtime
  # merely to decide whether an update is eligible.
  while IFS= read -r _setup_god_version_line || [ -n "$_setup_god_version_line" ]; do
    case "$_setup_god_version_line" in
      "_BASH_GOD_VERSION='"*"'")
        _setup_god_version_candidate=${_setup_god_version_line#"_BASH_GOD_VERSION='"}
        _setup_god_version_candidate=${_setup_god_version_candidate%"'"}
        _setup_god_version_is_valid "$_setup_god_version_candidate" || return 1
        [ -z "$_setup_god_version_value" ] || return 1
        _setup_god_version_value=$_setup_god_version_candidate
        ;;
    esac
  done < "$_setup_god_version_core"

  [ -n "$_setup_god_version_value" ] || return 1
  printf '%s\n' "$_setup_god_version_value"
}

# Prints -1 when LEFT is older, 0 when equal, and 1 when LEFT is newer.
_setup_god_compare_versions() {
  _setup_god_compare_left=$1
  _setup_god_compare_right=$2

  while [ -n "$_setup_god_compare_left" ] || [ -n "$_setup_god_compare_right" ]; do
    case "$_setup_god_compare_left" in
      *.*)
        _setup_god_compare_left_component=${_setup_god_compare_left%%.*}
        _setup_god_compare_left=${_setup_god_compare_left#*.}
        ;;
      '') _setup_god_compare_left_component=0 ;;
      *)
        _setup_god_compare_left_component=$_setup_god_compare_left
        _setup_god_compare_left=''
        ;;
    esac
    case "$_setup_god_compare_right" in
      *.*)
        _setup_god_compare_right_component=${_setup_god_compare_right%%.*}
        _setup_god_compare_right=${_setup_god_compare_right#*.}
        ;;
      '') _setup_god_compare_right_component=0 ;;
      *)
        _setup_god_compare_right_component=$_setup_god_compare_right
        _setup_god_compare_right=''
        ;;
    esac

    while [ "${_setup_god_compare_left_component#0}" != \
      "$_setup_god_compare_left_component" ]; do
      _setup_god_compare_left_component=${_setup_god_compare_left_component#0}
    done
    while [ "${_setup_god_compare_right_component#0}" != \
      "$_setup_god_compare_right_component" ]; do
      _setup_god_compare_right_component=${_setup_god_compare_right_component#0}
    done
    _setup_god_compare_left_component=${_setup_god_compare_left_component:-0}
    _setup_god_compare_right_component=${_setup_god_compare_right_component:-0}

    if [ "${#_setup_god_compare_left_component}" -lt \
      "${#_setup_god_compare_right_component}" ]; then
      printf '%s\n' -1
      return 0
    fi
    if [ "${#_setup_god_compare_left_component}" -gt \
      "${#_setup_god_compare_right_component}" ]; then
      printf '%s\n' 1
      return 0
    fi
    if [[ "$_setup_god_compare_left_component" < "$_setup_god_compare_right_component" ]]; then
      printf '%s\n' -1
      return 0
    fi
    if [[ "$_setup_god_compare_left_component" > "$_setup_god_compare_right_component" ]]; then
      printf '%s\n' 1
      return 0
    fi
  done
  printf '%s\n' 0
}

_setup_god_download() {
  _setup_god_download_url=$1
  _setup_god_download_target=$2
  printf 'Downloading %s\n' "${_setup_god_download_url##*/}"
  curl --fail --show-error --location --retry 3 \
    --proto '=https' --proto-redir '=https' \
    -o "$_setup_god_download_target" "$_setup_god_download_url"
}

_setup_god_path_has_no_symlink_components() {
  _setup_god_safe_path=$1
  case "$_setup_god_safe_path" in
    /*) ;;
    *) return 1 ;;
  esac

  _setup_god_safe_remaining=${_setup_god_safe_path#/}
  _setup_god_safe_current=''
  while [ -n "$_setup_god_safe_remaining" ]; do
    _setup_god_safe_component=${_setup_god_safe_remaining%%/*}
    if [ "$_setup_god_safe_remaining" = "$_setup_god_safe_component" ]; then
      _setup_god_safe_remaining=''
    else
      _setup_god_safe_remaining=${_setup_god_safe_remaining#*/}
    fi
    [ -n "$_setup_god_safe_component" ] || continue
    _setup_god_safe_current="$_setup_god_safe_current/$_setup_god_safe_component"
    [ ! -L "$_setup_god_safe_current" ] || return 1
  done
  return 0
}

_setup_god_uninstall_parents_are_safe() {
  _setup_god_path_has_no_symlink_components "$_setup_god_prefix/bin" &&
    _setup_god_path_has_no_symlink_components "$_setup_god_prefix/lib" &&
    _setup_god_path_has_no_symlink_components "$_setup_god_license_dir"
}

_setup_god_confirm_default_yes() {
  printf '%s [Y/n] ' "$1"
  if ! IFS= read -r _setup_god_answer; then
    printf '\nNo response received. Nothing was changed.\n'
    return 1
  fi
  case "$_setup_god_answer" in
    ''|y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

_setup_god_confirm_default_no() {
  printf '%s [y/N] ' "$1"
  if ! IFS= read -r _setup_god_answer; then
    printf '\nNo response received. Nothing was changed.\n'
    return 1
  fi
  case "$_setup_god_answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

_setup_god_refresh_state() {
  _setup_god_managed=0
  _setup_god_current_version=''
  _setup_god_path_command="$(command -v god 2>/dev/null || true)"

  if _setup_god_is_managed; then
    _setup_god_managed=1
    _setup_god_current_version="$(_setup_god_installed_version || true)"
    _setup_god_state='managed'
  elif [ -n "$_setup_god_path_command" ]; then
    _setup_god_state='unmanaged-command'
  elif [ -e "$_setup_god_launcher" ] || [ -L "$_setup_god_launcher" ] || \
       [ -e "$_setup_god_runtime" ] || [ -L "$_setup_god_runtime" ]; then
    _setup_god_state='partial'
  else
    _setup_god_state='absent'
  fi
}

_setup_god_install_release() {
  _setup_god_install_version=$1
  _setup_god_version_is_valid "$_setup_god_install_version" || \
    _setup_god_die 'the selected release version is invalid'

  # Re-read local state at the action boundary. Installation is allowed only
  # for an empty destination or a strictly older managed version.
  _setup_god_refresh_state
  _setup_god_replace=0
  case "$_setup_god_state" in
    absent)
      ;;
    managed)
      [ -n "$_setup_god_current_version" ] || \
        _setup_god_die 'managed version metadata is unreadable; nothing was changed'
      _setup_god_install_relation="$(_setup_god_compare_versions \
        "$_setup_god_current_version" "$_setup_god_install_version")"
      case "$_setup_god_install_relation" in
        -1) _setup_god_replace=1 ;;
        0)
          printf '\nBASH_GOD %s is already current. Nothing was changed.\n' \
            "$_setup_god_current_version"
          return 0
          ;;
        1)
          printf '\nInstalled BASH_GOD %s is newer than release %s. No downgrade was performed.\n' \
            "$_setup_god_current_version" "$_setup_god_install_version"
          return 0
          ;;
        *) _setup_god_die 'could not compare versions; nothing was changed' ;;
      esac
      ;;
    unmanaged-command)
      printf '\nA god command already exists at %s. Nothing was changed.\n' \
        "$_setup_god_path_command"
      printf 'This setup script will not replace or shadow an unmanaged command.\n'
      return 0
      ;;
    partial)
      printf '\nAn unmanaged or partial BASH_GOD installation exists under %s. Nothing was changed.\n' \
        "$_setup_god_prefix"
      printf 'Review those files manually; this script will not overwrite them.\n'
      return 0
      ;;
  esac

  command -v curl >/dev/null 2>&1 || \
    _setup_god_die 'curl is required to install or update BASH_GOD'
  command -v tar >/dev/null 2>&1 || \
    _setup_god_die 'tar is required to install or update BASH_GOD'
  command -v mktemp >/dev/null 2>&1 || \
    _setup_god_die 'mktemp is required to install or update BASH_GOD'
  command -v awk >/dev/null 2>&1 || \
    _setup_god_die 'awk is required to install or update BASH_GOD'
  command -v tr >/dev/null 2>&1 || \
    _setup_god_die 'tr is required to install or update BASH_GOD'
  command -v chmod >/dev/null 2>&1 || \
    _setup_god_die 'chmod is required to install or update BASH_GOD'
  command -v rm >/dev/null 2>&1 || \
    _setup_god_die 'rm is required to install or update BASH_GOD'
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || \
    _setup_god_die 'sha256sum or shasum is required to install or update BASH_GOD'

  _setup_god_download_dir="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-setup.XXXXXX")" || \
    _setup_god_die 'could not create a private download directory'
  chmod 0700 "$_setup_god_download_dir"

  _setup_god_release_url="https://github.com/${_setup_god_repository}/releases/download/v${_setup_god_install_version}"
  _setup_god_archive="$_setup_god_download_dir/bash-god-${_setup_god_install_version}.tar.gz"
  _setup_god_archive_checksum="${_setup_god_archive}.sha256"
  _setup_god_installer="$_setup_god_download_dir/install-runtime.sh"
  _setup_god_installer_checksum="${_setup_god_installer}.sha256"

  _setup_god_download \
    "$_setup_god_release_url/bash-god-${_setup_god_install_version}.tar.gz" \
    "$_setup_god_archive"
  _setup_god_download \
    "$_setup_god_release_url/bash-god-${_setup_god_install_version}.tar.gz.sha256" \
    "$_setup_god_archive_checksum"
  _setup_god_download "$_setup_god_release_url/install-runtime.sh" "$_setup_god_installer"
  _setup_god_download \
    "$_setup_god_release_url/install-runtime.sh.sha256" \
    "$_setup_god_installer_checksum"

  _setup_god_verify "$_setup_god_installer" "$_setup_god_installer_checksum"
  _setup_god_verify "$_setup_god_archive" "$_setup_god_archive_checksum"
  printf 'Checksums verified.\n'
  chmod 0700 "$_setup_god_installer"

  # Recheck immediately before invoking downloaded code so a concurrent local
  # change cannot turn an update into a reinstall or downgrade.
  _setup_god_refresh_state
  if [ "$_setup_god_replace" -eq 1 ]; then
    [ "$_setup_god_state" = 'managed' ] && [ -n "$_setup_god_current_version" ] || \
      _setup_god_die 'the managed installation changed during download; nothing was installed'
    [ "$(_setup_god_compare_versions \
      "$_setup_god_current_version" "$_setup_god_install_version")" = -1 ] || \
      _setup_god_die 'the installed version is no longer older; nothing was installed'
    "$_setup_god_installer" --replace --prefix "$_setup_god_prefix" \
      "$_setup_god_archive" "$_setup_god_archive_checksum"
  else
    [ "$_setup_god_state" = 'absent' ] || \
      _setup_god_die 'the installation destination changed during download; nothing was installed'
    "$_setup_god_installer" --prefix "$_setup_god_prefix" \
      "$_setup_god_archive" "$_setup_god_archive_checksum"
  fi

  _setup_god_refresh_state
  [ "$_setup_god_state" = 'managed' ] && \
    [ "$_setup_god_current_version" = "$_setup_god_install_version" ] || \
    _setup_god_die 'installation finished, but installed version metadata does not match the release'

  printf '\nInstalled BASH_GOD %s.\n' "$_setup_god_current_version"
  case ":${PATH:-}:" in
    *":$_setup_god_prefix/bin:"*) ;;
    *)
      printf 'For this shell, run:\n  export PATH="%s/bin:$PATH"\n' "$_setup_god_prefix"
      printf 'Add that line to your shell profile only if you want it to persist.\n'
      ;;
  esac
  printf '\nGet ready for the GOD...\n'
}

_setup_god_uninstall() {
  _setup_god_refresh_state
  if [ "$_setup_god_state" != 'managed' ]; then
    printf '\nNo managed BASH_GOD installation was found under %s. Nothing was removed.\n' \
      "$_setup_god_prefix"
    if [ -n "$_setup_god_path_command" ]; then
      printf 'The existing god command at %s was not touched.\n' "$_setup_god_path_command"
    fi
    return 0
  fi

  command -v rm >/dev/null 2>&1 || _setup_god_die 'rm is required to uninstall BASH_GOD'

  printf '\nUninstall the managed BASH_GOD installation?\n'
  printf '  launcher  %s\n' "$_setup_god_launcher"
  printf '  runtime   %s\n' "$_setup_god_runtime"
  printf '  license   %s\n' "$_setup_god_license_file"
  printf '\nPrevious-version backups will be preserved:\n'
  printf '  %s\n' "$_setup_god_prefix/lib/bash-god.backup-*"
  printf 'Shell startup files and PATH configuration will not be changed.\n\n'
  if ! _setup_god_confirm_default_no 'Continue with uninstall?'; then
    printf 'Uninstall cancelled. Nothing was removed.\n'
    return 0
  fi

  # Recheck ownership immediately before deleting only the exact managed paths.
  _setup_god_is_managed || \
    _setup_god_die 'the managed installation changed during confirmation; nothing was removed'
  _setup_god_uninstall_parents_are_safe || \
    _setup_god_die 'a managed parent path is symlinked; nothing was removed'
  command rm -f -- "$_setup_god_launcher"
  command rm -rf -- "$_setup_god_runtime"
  command rm -f -- "$_setup_god_license_file"
  if command -v rmdir >/dev/null 2>&1; then
    rmdir "$_setup_god_license_dir" 2>/dev/null || true
  fi

  printf '\nUninstalled the managed BASH_GOD runtime. Retained release backups, if any.\n'
  printf 'Run `hash -r` in an existing shell if it still remembers the old command path.\n'
}

_setup_god_print_status() {
  printf '\nBASH_GOD SETUP\n'
  case "$_setup_god_state" in
    absent) printf '  Current installation  not installed\n' ;;
    managed)
      if [ -n "$_setup_god_current_version" ]; then
        printf '  Current installation  managed v%s\n' "$_setup_god_current_version"
      else
        printf '  Current installation  managed, version unknown\n'
      fi
      ;;
    unmanaged-command)
      printf '  Current installation  unmanaged command: %s\n' "$_setup_god_path_command"
      ;;
    partial)
      printf '  Current installation  unmanaged or partial files under %s\n' \
        "$_setup_god_prefix"
      ;;
  esac
  printf '  Managed prefix        %s\n' "$_setup_god_prefix"
}

_setup_god_run_default() {
  _setup_god_refresh_state
  _setup_god_print_status

  case "$_setup_god_state" in
    unmanaged-command)
      printf '\nA god command already exists at %s. Nothing was changed.\n' \
        "$_setup_god_path_command"
      printf 'This setup script will not replace or shadow an unmanaged command.\n'
      return 0
      ;;
    partial)
      printf '\nAn unmanaged or partial BASH_GOD installation already exists. Nothing was changed.\n'
      printf 'Review %s manually; this script will not overwrite it.\n' "$_setup_god_prefix"
      return 0
      ;;
    managed)
      if [ -z "$_setup_god_current_version" ]; then
        printf '\nThe installed version cannot be read, so update eligibility cannot be determined.\n'
        _setup_god_uninstall
        return 0
      fi
      ;;
    absent) ;;
  esac

  if ! _setup_god_latest_version="$(_setup_god_fetch_latest_version)"; then
    _setup_god_latest_version=''
    if [ "$_setup_god_state" = 'managed' ]; then
      printf '\nGitHub\047s latest published release tag could not be checked.\n'
      printf 'The managed installation was kept; no update was attempted.\n'
      _setup_god_uninstall
      return 0
    fi
    _setup_god_die "could not determine GitHub's latest published release; nothing was installed"
  fi

  printf '  Latest release        v%s\n' "$_setup_god_latest_version"
  if [ "$_setup_god_state" = 'absent' ]; then
    printf '\n'
    if _setup_god_confirm_default_yes \
      "Install BASH_GOD v$_setup_god_latest_version?"; then
      _setup_god_install_release "$_setup_god_latest_version"
    else
      printf 'Installation skipped. Nothing was changed.\n'
    fi
    return 0
  fi

  _setup_god_relation="$(_setup_god_compare_versions \
    "$_setup_god_current_version" "$_setup_god_latest_version")"
  case "$_setup_god_relation" in
    -1)
      printf '\n'
      if _setup_god_confirm_default_yes \
        "Update BASH_GOD v$_setup_god_current_version to v$_setup_god_latest_version?"; then
        _setup_god_install_release "$_setup_god_latest_version"
      else
        printf 'Update skipped. BASH_GOD %s was kept.\n' "$_setup_god_current_version"
      fi
      ;;
    0)
      printf '\nBASH_GOD %s is already the latest published release. No reinstall is needed.\n' \
        "$_setup_god_current_version"
      _setup_god_uninstall
      ;;
    1)
      printf '\nInstalled BASH_GOD %s is newer than the latest published release %s.\n' \
        "$_setup_god_current_version" "$_setup_god_latest_version"
      printf 'No downgrade will be attempted.\n'
      _setup_god_uninstall
      ;;
    *) _setup_god_die 'could not compare installed and published versions' ;;
  esac
}

_setup_god_main() {
  _setup_god_mode='default'
  case "${1:-}" in
    --help|-h)
      _setup_god_usage
      return 0
      ;;
    --uninstall)
      _setup_god_mode='uninstall'
      shift
      ;;
    '') ;;
    *)
      _setup_god_usage >&2
      return 2
      ;;
  esac
  [ "$#" -eq 0 ] || {
    _setup_god_usage >&2
    return 2
  }

  [ -n "${HOME:-}" ] || _setup_god_die 'HOME is unavailable'
  [ -t 0 ] || _setup_god_die 'run this setup script from an interactive terminal'

  trap '_setup_god_cleanup' EXIT
  trap 'exit 130' HUP INT TERM

  _setup_god_prefix="$HOME/.local"
  _setup_god_launcher="$_setup_god_prefix/bin/god"
  _setup_god_runtime="$_setup_god_prefix/lib/bash-god"
  _setup_god_license_dir="$_setup_god_prefix/share/licenses/bash-god"
  _setup_god_license_file="$_setup_god_license_dir/LICENSE"

  if [ "$_setup_god_mode" = 'uninstall' ]; then
    _setup_god_uninstall
  else
    _setup_god_run_default
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _setup_god_main "$@"
fi
