# shellcheck shell=bash

# Source this file from Bash or zsh to load the `god` knowledge-base command.
# Loading is intentionally silent; catalog commands are inert text.

if [ -n "${BASH_VERSION:-}" ]; then
  _bash_god_entry_file="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _bash_god_entry_file="${(%):-%x}"
else
  _bash_god_entry_file=""
fi

_bash_god_load_failed=0
if [ -n "$_bash_god_entry_file" ]; then
  _bash_god_entry_dir="$(CDPATH= cd "$(dirname "$_bash_god_entry_file")" 2>/dev/null && pwd -P)"
  if [ -r "$_bash_god_entry_dir/bash_god/core.sh" ]; then
    . "$_bash_god_entry_dir/bash_god/core.sh" || _bash_god_load_failed=1
  else
    printf 'BASH_GOD: cannot read %s/bash_god/core.sh\n' "$_bash_god_entry_dir" >&2
    _bash_god_load_failed=1
  fi
else
  printf 'BASH_GOD: cannot determine the location of BASH_GOD.sh\n' >&2
  _bash_god_load_failed=1
fi

unset _bash_god_entry_file _bash_god_entry_dir
if [ "$_bash_god_load_failed" -ne 0 ]; then
  unset _bash_god_load_failed
  return 1
fi
unset _bash_god_load_failed
