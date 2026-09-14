#!/usr/bin/env bash

_bash_god_wrapper_dir="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || exit 1

# shellcheck source=src/core.sh
. "$_bash_god_wrapper_dir/src/core.sh" || exit 1

god "$@"
exit $?
