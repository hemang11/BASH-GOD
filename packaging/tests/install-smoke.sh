#!/usr/bin/env bash

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
version="$(LC_ALL=C awk -F"'" '/^_BASH_GOD_VERSION=/ { print $2; exit }' "$repo_dir/bash_god/core.sh")"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-install-smoke.XXXXXX")" || exit 1
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

checks=0
failures=0

pass() {
  checks=$((checks + 1))
  printf 'ok %02d - %s\n' "$checks" "$1"
}

fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'not ok %02d - %s\n' "$checks" "$1"
}

contains() {
  case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

assets="$temporary/assets"
prefix="$temporary/prefix"
test_home="$temporary/home"
fake_bin="$temporary/bin"
mkdir -p "$assets" "$test_home" "$fake_bin"
test_path="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin"

if "$repo_dir/packaging/build-runtime.sh" "$assets" >/dev/null; then
  pass 'release assets build for the public installer test'
else
  fail 'release assets build for the public installer test'
fi

cat > "$fake_bin/curl" <<'CURL_STUB'
#!/usr/bin/env bash
output=''
url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    -w)
      shift 2
      ;;
    --proto|--proto-redir|--connect-timeout|--max-time|--retry)
      shift 2
      ;;
    --fail|--silent|--show-error|--location)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done
case "$url" in
  */releases/latest)
    printf 'https://github.com/hemang11/BASH-GOD/releases/tag/v%s' "$BASH_GOD_TEST_VERSION"
    ;;
  */releases/download/*)
    [ -n "$output" ] || exit 2
    cp "$BASH_GOD_TEST_ASSETS/${url##*/}" "$output"
    ;;
  *)
    exit 22
    ;;
esac
CURL_STUB
chmod 0755 "$fake_bin/curl"

install_output="$(
  HOME="$test_home" \
  BASH_GOD_PREFIX="$prefix" \
  BASH_GOD_TEST_ASSETS="$assets" \
  BASH_GOD_TEST_VERSION="$version" \
  PATH="$test_path" \
  bash "$repo_dir/packaging/install.sh"
)"
if contains "$install_output" 'Checksums verified.' && \
   contains "$install_output" "Installed BASH_GOD $version" && \
   contains "$install_output" 'Get ready for the GOD...' && \
   [ -x "$prefix/bin/god" ] && \
   [ "$(GOD_COLOR=never "$prefix/bin/god" --version)" = "$(printf 'BASH_GOD %s\nLicense: MIT' "$version")" ]; then
  pass 'one public command installs the latest verified release'
else
  fail 'one public command installs the latest verified release'
fi

manifest="$(command cat "$prefix/share/bash-god/install-manifest")"
prefix_physical="$(CDPATH= cd "$prefix" && pwd -P)"
expected_manifest="$(printf 'BASH_GOD_INSTALL_MANIFEST_V1\nmethod=github-release\nprefix=%s\nversion=%s' "$prefix_physical" "$version")"
if [ "$manifest" = "$expected_manifest" ]; then
  pass 'public installation records managed ownership and version'
else
  fail 'public installation records managed ownership and version'
fi

current_output="$(
  HOME="$test_home" \
  BASH_GOD_PREFIX="$prefix" \
  BASH_GOD_TEST_ASSETS="$assets" \
  BASH_GOD_TEST_VERSION="$version" \
  PATH="$test_path" \
  bash "$repo_dir/packaging/install.sh"
)"
if [ "$current_output" = "BASH_GOD $version is already installed and current." ] && \
   [ -z "$(command find "$prefix/lib" -maxdepth 1 -name 'bash-god.backup-*' -print)" ]; then
  pass 're-running install.sh is idempotent when the release is current'
else
  fail 're-running install.sh is idempotent when the release is current'
fi

old_version='0.0.1.2'
LC_ALL=C awk -v old="$old_version" '
  /^_BASH_GOD_VERSION=/ { print "_BASH_GOD_VERSION=\047" old "\047"; next }
  { print }
' "$prefix/lib/bash-god/bash_god/core.sh" > "$temporary/old-core.sh"
mv "$temporary/old-core.sh" "$prefix/lib/bash-god/bash_god/core.sh"
upgrade_output="$(
  HOME="$test_home" \
  BASH_GOD_PREFIX="$prefix" \
  BASH_GOD_TEST_ASSETS="$assets" \
  BASH_GOD_TEST_VERSION="$version" \
  PATH="$test_path" \
  bash "$repo_dir/packaging/install.sh"
)"
backup="$(command find "$prefix/lib" -maxdepth 1 -type d -name 'bash-god.backup-*' -print | LC_ALL=C awk 'NR == 1 { print; exit }')"
if contains "$upgrade_output" "Installed BASH_GOD $version" && \
   contains "$upgrade_output" 'Previous runtime retained at:' && \
   [ -n "$backup" ] && \
   [ "$(GOD_COLOR=never "$prefix/bin/god" --version | LC_ALL=C awk 'NR == 1 { print $2 }')" = "$version" ]; then
  pass 'install.sh upgrades an older managed runtime without reinstalling blindly'
else
  fail 'install.sh upgrades an older managed runtime without reinstalling blindly'
fi

partial_prefix="$temporary/partial"
mkdir -p "$partial_prefix/bin"
printf '#!/usr/bin/env bash\n' > "$partial_prefix/bin/god"
partial_status=0
HOME="$test_home" \
BASH_GOD_PREFIX="$partial_prefix" \
BASH_GOD_TEST_ASSETS="$assets" \
BASH_GOD_TEST_VERSION="$version" \
PATH="$test_path" \
bash "$repo_dir/packaging/install.sh" >/dev/null 2>&1 || partial_status=$?
if [ "$partial_status" -eq 1 ] && [ ! -e "$partial_prefix/lib/bash-god" ]; then
  pass 'public installer refuses partial or unmanaged destination files'
else
  fail 'public installer refuses partial or unmanaged destination files'
fi

source_result="$(bash -c '
  set +o errexit
  set +o nounset
  set +o pipefail
  . "$1" >/dev/null 2>&1
  status=$?
  case "$-" in *e*|*u*) options=changed ;; *) options=clean ;; esac
  pipefail_state="$(set -o | while read -r name state; do
    [ "$name" = pipefail ] && printf "%s" "$state"
  done)"
  printf "%s %s %s\n" "$status" "$options" "$pipefail_state"
' _ "$repo_dir/packaging/install.sh")"
if [ "$source_result" = '1 clean off' ]; then
  pass 'install.sh refuses accidental sourcing without changing shell options'
else
  fail 'install.sh refuses accidental sourcing without changing shell options'
fi

if [ ! -e "$repo_dir/packaging/setup-god.sh" ] && \
   [ ! -e "$repo_dir/packaging/tests/setup-god-smoke.sh" ] && \
   [ ! -e "$assets/setup-god.sh" ] && \
   [ ! -e "$assets/setup-god.sh.sha256" ]; then
  pass 'setup-god is absent from source and release assets'
else
  fail 'setup-god is absent from source and release assets'
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d install checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d install checks failed.\n' "$failures" "$checks" >&2
exit 1
