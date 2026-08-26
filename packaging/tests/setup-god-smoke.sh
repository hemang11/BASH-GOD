#!/usr/bin/env bash

set -o nounset
set -o pipefail

_setup_test_file=${BASH_SOURCE[0]}
_setup_test_dir="$(CDPATH= cd "$(dirname "$_setup_test_file")" 2>/dev/null && pwd -P)" || exit 1
_setup_test_root="$(CDPATH= cd "$_setup_test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
_setup_test_script="$_setup_test_root/packaging/setup-god.sh"
_setup_test_temp="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-setup-smoke.XXXXXX")" || exit 1
_setup_test_temp="$(CDPATH= cd "$_setup_test_temp" 2>/dev/null && pwd -P)" || exit 1
trap 'rm -rf -- "$_setup_test_temp"' EXIT HUP INT TERM

_setup_test_checks=0
_setup_test_failures=0

_setup_test_pass() {
  _setup_test_checks=$((_setup_test_checks + 1))
  printf 'ok %02d - %s\n' "$_setup_test_checks" "$1"
}

_setup_test_fail() {
  _setup_test_checks=$((_setup_test_checks + 1))
  _setup_test_failures=$((_setup_test_failures + 1))
  printf 'not ok %02d - %s\n' "$_setup_test_checks" "$1"
}

_setup_test_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

_setup_test_route() {
  _setup_test_route_state=$1
  _setup_test_route_current=$2
  _setup_test_route_latest=$3
  _setup_test_route_confirm=$4

  (
    # shellcheck source=../setup-god.sh
    . "$_setup_test_script"
    _setup_god_prefix="$_setup_test_temp/prefix"
    _setup_god_launcher="$_setup_god_prefix/bin/god"
    _setup_god_runtime="$_setup_god_prefix/lib/bash-god"
    _setup_god_license_dir="$_setup_god_prefix/share/licenses/bash-god"
    _setup_god_license_file="$_setup_god_license_dir/LICENSE"
    _setup_god_refresh_state() {
      _setup_god_state=$_setup_test_route_state
      _setup_god_current_version=$_setup_test_route_current
      _setup_god_path_command=''
      if [ "$_setup_god_state" = managed ]; then
        _setup_god_managed=1
      else
        _setup_god_managed=0
      fi
    }
    _setup_god_print_status() { :; }
    _setup_god_fetch_latest_version() {
      [ -n "$_setup_test_route_latest" ] || return 1
      printf '%s\n' "$_setup_test_route_latest"
    }
    _setup_god_confirm_default_yes() {
      [ "$_setup_test_route_confirm" = yes ]
    }
    _setup_god_install_release() { printf 'ACTION install %s\n' "$1"; }
    _setup_god_uninstall() { printf 'ACTION uninstall\n'; }
    _setup_god_run_default
  )
}

_setup_test_help="$("$_setup_test_script" --help)"
if _setup_test_contains "$_setup_test_help" 'Usage:' && \
   _setup_test_contains "$_setup_test_help" '--uninstall' && \
   _setup_test_contains "$_setup_test_help" 'never reinstall or downgrade'; then
  _setup_test_pass 'help documents state-driven setup and explicit uninstall'
else
  _setup_test_fail 'help documents state-driven setup and explicit uninstall'
fi

_setup_test_output="$(_setup_test_route absent '' 2.0.0 yes)"
if _setup_test_contains "$_setup_test_output" 'ACTION install 2.0.0' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION uninstall'; then
  _setup_test_pass 'an absent installation offers only the latest release install path'
else
  _setup_test_fail 'an absent installation offers only the latest release install path'
fi

_setup_test_output="$(_setup_test_route absent '' 2.0.0 no)"
if _setup_test_contains "$_setup_test_output" 'Installation skipped' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION install' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION uninstall'; then
  _setup_test_pass 'declining a new install leaves state unchanged'
else
  _setup_test_fail 'declining a new install leaves state unchanged'
fi

_setup_test_output="$(_setup_test_route managed 1.9.9 2.0.0 yes)"
if _setup_test_contains "$_setup_test_output" 'ACTION install 2.0.0' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION uninstall'; then
  _setup_test_pass 'an older managed version offers only the update path'
else
  _setup_test_fail 'an older managed version offers only the update path'
fi

_setup_test_output="$(_setup_test_route managed 1.9.9 2.0.0 no)"
if _setup_test_contains "$_setup_test_output" 'Update skipped' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION install' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION uninstall'; then
  _setup_test_pass 'declining an update keeps the older managed version'
else
  _setup_test_fail 'declining an update keeps the older managed version'
fi

_setup_test_output="$(_setup_test_route managed 2.0.0 2.0.0 yes)"
if _setup_test_contains "$_setup_test_output" 'already the latest published release' && \
   _setup_test_contains "$_setup_test_output" 'ACTION uninstall' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION install'; then
  _setup_test_pass 'an equal version never enters the reinstall path'
else
  _setup_test_fail 'an equal version never enters the reinstall path'
fi

_setup_test_output="$(_setup_test_route managed 2.1.0 2.0.0 yes)"
if _setup_test_contains "$_setup_test_output" 'No downgrade will be attempted' && \
   _setup_test_contains "$_setup_test_output" 'ACTION uninstall' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION install'; then
  _setup_test_pass 'a newer version never enters the downgrade path'
else
  _setup_test_fail 'a newer version never enters the downgrade path'
fi

_setup_test_output="$(_setup_test_route managed 2.0.0 '' yes)"
if _setup_test_contains "$_setup_test_output" 'latest published release tag could not be checked' && \
   _setup_test_contains "$_setup_test_output" 'ACTION uninstall' && \
   ! _setup_test_contains "$_setup_test_output" 'ACTION install'; then
  _setup_test_pass 'a failed release lookup cannot make an update eligible'
else
  _setup_test_fail 'a failed release lookup cannot make an update eligible'
fi

_setup_test_versions="$(
  . "$_setup_test_script"
  printf '%s ' "$(_setup_god_compare_versions 1.2.9 1.10.0)"
  printf '%s ' "$(_setup_god_compare_versions 1.02.0 1.2)"
  printf '%s\n' "$(_setup_god_compare_versions 3.0 2.99.99)"
)"
if [ "$_setup_test_versions" = '-1 0 1' ]; then
  _setup_test_pass 'numeric release comparison handles older, equal, and newer versions'
else
  _setup_test_fail 'numeric release comparison handles older, equal, and newer versions'
fi

_setup_test_uninstall_prefix="$_setup_test_temp/uninstall-prefix"
mkdir -p \
  "$_setup_test_uninstall_prefix/bin" \
  "$_setup_test_uninstall_prefix/lib/bash-god/bash_god" \
  "$_setup_test_uninstall_prefix/lib/bash-god.backup-1.0.0.keep/runtime" \
  "$_setup_test_uninstall_prefix/share/licenses/bash-god"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# Real-file launcher installed at PREFIX/bin/god by the runtime package.' \
  > "$_setup_test_uninstall_prefix/bin/god"
printf '#!/usr/bin/env bash\n' > "$_setup_test_uninstall_prefix/lib/bash-god/god"
printf "_BASH_GOD_VERSION='1.0.0'\n" > \
  "$_setup_test_uninstall_prefix/lib/bash-god/bash_god/core.sh"
printf 'MIT\n' > "$_setup_test_uninstall_prefix/share/licenses/bash-god/LICENSE"
printf 'keep\n' > \
  "$_setup_test_uninstall_prefix/lib/bash-god.backup-1.0.0.keep/runtime/marker"
printf 'unrelated\n' > "$_setup_test_uninstall_prefix/unrelated"
chmod 0755 \
  "$_setup_test_uninstall_prefix/bin/god" \
  "$_setup_test_uninstall_prefix/lib/bash-god/god"

(
  . "$_setup_test_script"
  _setup_god_prefix=$_setup_test_uninstall_prefix
  _setup_god_launcher="$_setup_god_prefix/bin/god"
  _setup_god_runtime="$_setup_god_prefix/lib/bash-god"
  _setup_god_license_dir="$_setup_god_prefix/share/licenses/bash-god"
  _setup_god_license_file="$_setup_god_license_dir/LICENSE"
  _setup_god_confirm_default_no() { return 0; }
  _setup_god_uninstall >/dev/null
)
if [ ! -e "$_setup_test_uninstall_prefix/bin/god" ] && \
   [ ! -e "$_setup_test_uninstall_prefix/lib/bash-god" ] && \
   [ ! -e "$_setup_test_uninstall_prefix/share/licenses/bash-god/LICENSE" ] && \
   [ -f "$_setup_test_uninstall_prefix/lib/bash-god.backup-1.0.0.keep/runtime/marker" ] && \
   [ -f "$_setup_test_uninstall_prefix/unrelated" ]; then
  _setup_test_pass 'uninstall removes only exact managed paths and preserves backups'
else
  _setup_test_fail 'uninstall removes only exact managed paths and preserves backups'
fi

if LC_ALL=C grep -q -- "--proto '=https' --proto-redir '=https'" "$_setup_test_script" && \
   LC_ALL=C grep -q 'Get ready for the GOD' "$_setup_test_script"; then
  _setup_test_pass 'downloads remain HTTPS-only and successful install keeps the closing message'
else
  _setup_test_fail 'downloads remain HTTPS-only and successful install keeps the closing message'
fi

if [ "$_setup_test_failures" -eq 0 ]; then
  printf '\n%d setup checks passed.\n' "$_setup_test_checks"
  exit 0
fi

printf '\n%d of %d setup checks failed.\n' \
  "$_setup_test_failures" "$_setup_test_checks" >&2
exit 1
