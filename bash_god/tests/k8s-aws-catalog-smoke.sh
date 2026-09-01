#!/usr/bin/env bash

# Kubernetes/AWS catalog metadata regression checks. Every executable used
# here is a temporary fixture; no real kubectl, AWS CLI, curl, IMDS, cluster,
# or cloud account is contacted.

test_file="${BASH_SOURCE[0]}"
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
project_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
k8s_catalog="$project_dir/bash_god/catalog/k8s/service.god"
aws_catalog="$project_dir/bash_god/catalog/aws/service.god"
catalog_module="$project_dir/bash_god/catalog.sh"
discover_module="$project_dir/bash_god/discover.sh"
resolve_module="$project_dir/bash_god/resolve.sh"

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-k8s-aws.XXXXXX" 2>/dev/null)" || exit 1
trap 'rm -rf -- "$fixture_root"' EXIT

failures=0
checks=0

pass() {
  checks=$((checks + 1))
  printf 'ok %02d - %s\n' "$checks" "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'not ok %02d - %s\n' "$checks" "$1"
}

has_exact_line() {
  printf '%s\n' "$1" | LC_ALL=C grep -Fqx "$2"
}

catalog_command_count() {
  LC_ALL=C awk '/^@command[[:space:]]+/ { count++ } END { print count + 0 }' "$1"
}

catalog_since_count() {
  LC_ALL=C awk '/^@since[[:space:]]+/ { count++ } END { print count + 0 }' "$1"
}

catalog_mode_run_lines_use_bare_tool() {
  LC_ALL=C awk -v tool="$2" -v expected_mode="$3" '
    /^@mode[[:space:]]+/ {
      mode = $2
      next
    }
    /^@run$/ {
      getline
      if (mode == expected_mode) {
        runs++
        if ($0 !~ ("^" tool "([[:space:]]|$)")) bad = 1
      }
    }
    END { exit(runs > 0 && !bad ? 0 : 1) }
  ' "$1"
}

mkdir -p "$fixture_root/config/bash-god" "$fixture_root/state" "$fixture_root/fake-k8s" "$fixture_root/fake-aws" || exit 1
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "$1" = version ] && [ "$2" = --client ]; then' \
  '  printf "Client Version: v1.28.7\\n"' \
  '  exit 0' \
  'fi' \
  'printf "unexpected fake kubectl invocation: %s\\n" "$*" >&2' \
  'exit 64' > "$fixture_root/fake-k8s/kubectl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "$1" = --version ]; then' \
  '  printf "aws-cli/2.36.34 Python/3 fixture\\n" >&2' \
  '  exit 0' \
  'fi' \
  'printf "unexpected fake aws invocation: %s\\n" "$*" >&2' \
  'exit 64' > "$fixture_root/fake-aws/aws"
chmod 0700 "$fixture_root/fake-k8s/kubectl" "$fixture_root/fake-aws/aws" || exit 1
printf 'path=%s\n' "$fixture_root/fake-k8s" > "$fixture_root/config/bash-god/k8s.conf"
printf 'path=%s\n' "$fixture_root/fake-aws" > "$fixture_root/config/bash-god/aws.conf"

export HOME="$fixture_root/home"
export XDG_CONFIG_HOME="$fixture_root/config"
export XDG_STATE_HOME="$fixture_root/state"

# shellcheck source=../catalog.sh
. "$catalog_module" || exit 1
# shellcheck source=../discover.sh
. "$discover_module" || exit 1
# shellcheck source=../resolve.sh
. "$resolve_module" || exit 1

k8s_commands="$(catalog_command_count "$k8s_catalog")"
k8s_since="$(catalog_since_count "$k8s_catalog")"
aws_commands="$(catalog_command_count "$aws_catalog")"
aws_since="$(catalog_since_count "$aws_catalog")"
if [ "$k8s_commands" -eq 49 ] && [ "$k8s_since" -eq "$k8s_commands" ] && \
   [ "$aws_commands" -eq 15 ] && [ "$aws_since" -eq "$aws_commands" ]; then
  pass 'every Kubernetes and AWS executable-catalog record has a compatibility floor'
else
  fail 'every Kubernetes and AWS executable-catalog record has a compatibility floor'
fi

if catalog_mode_run_lines_use_bare_tool "$k8s_catalog" kubectl MODERN && \
   catalog_mode_run_lines_use_bare_tool "$aws_catalog" aws MODERN; then
  pass 'static Kubernetes and AWS CLI commands remain human-copyable'
else
  fail 'static Kubernetes and AWS CLI commands remain human-copyable'
fi

if _god_validate_catalog "$k8s_catalog" >/dev/null 2>&1 && \
   _god_validate_catalog "$aws_catalog" >/dev/null 2>&1; then
  pass 'Kubernetes and AWS executable catalogs validate'
else
  fail 'Kubernetes and AWS executable catalogs validate'
fi

if _god_discover_resolve k8s "$k8s_catalog" && \
   [ "$(_god_discover_path k8s)" = "$fixture_root/fake-k8s" ] && \
   [ "$(_god_discover_version k8s)" = '1.28.7' ]; then
  pass 'Kubernetes discovery uses a configured fake client and its client-only version'
else
  fail 'Kubernetes discovery uses a configured fake client and its client-only version'
fi

if _god_discover_resolve aws "$aws_catalog" && \
   [ "$(_god_discover_path aws)" = "$fixture_root/fake-aws" ] && \
   [ "$(_god_discover_version aws)" = '2.36.34' ]; then
  pass 'AWS discovery captures a fake CLI version written to stderr'
else
  fail 'AWS discovery captures a fake CLI version written to stderr'
fi

k8s_model="$(_god_resolve_command k8s "$k8s_catalog" pods 1 "$(_god_discover_path k8s)" 'list pods')"
aws_model="$(_god_resolve_command aws "$aws_catalog" identity 1 "$(_god_discover_path aws)" 'show current identity')"
k8s_display="$(printf 'DISPLAY\t%s/kubectl get pods -n <namespace>' "$fixture_root/fake-k8s")"
aws_display="$(printf 'DISPLAY\t%s/aws sts get-caller-identity' "$fixture_root/fake-aws")"
if has_exact_line "$k8s_model" "$k8s_display" && \
   has_exact_line "$aws_model" "$aws_display"; then
  pass 'generic resolution rewrites bare discovered probes to fake absolute paths'
else
  fail 'generic resolution rewrites bare discovered probes to fake absolute paths'
fi

aws_unset="$(_god_catalog_command_export "$aws_catalog" imds 3)"
aws_imdsv2="$(_god_catalog_command_export "$aws_catalog" imds 2)"
k8s_events="$(_god_catalog_command_export "$k8s_catalog" events 1)"
if has_exact_line "$aws_unset" $'RUNNABLE\t1' && \
   has_exact_line "$aws_unset" $'SINCE\t0.0' && \
   has_exact_line "$aws_imdsv2" $'RUNNABLE\t1' && \
   has_exact_line "$k8s_events" $'SINCE\t1.28'; then
  pass 'all AWS rows are runnable and per-command compatibility metadata exports correctly'
else
  fail 'all AWS rows are runnable and per-command compatibility metadata exports correctly'
fi

if [ "$failures" -ne 0 ]; then
  printf '%s of %s checks failed\n' "$failures" "$checks" >&2
  exit 1
fi

printf '%s checks passed\n' "$checks"
