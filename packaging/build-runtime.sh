#!/usr/bin/env bash

# Assemble direct-GitHub release assets. The shell runtime is portable, but
# god-tui is native code: each normal archive contains exactly one compiled
# helper. The unsuffixed archive intentionally contains all supported helpers
# only as a compatibility bridge for pre-R08 updaters that request its legacy
# filename; new bootstrap and update paths always select a platform archive.

set -o errexit
set -o nounset
set -o pipefail

_bash_god_package_die() {
  printf 'BASH_GOD package: %s\n' "$1" >&2
  exit 1
}

_bash_god_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  else
    _bash_god_package_die 'sha256sum or shasum is required to create release checksums.'
  fi
}

_bash_god_publish_file() {
  local source target mode

  source=$1
  target=$2
  mode=$3
  _bash_god_publish_current="$(mktemp "$_bash_god_output_dir/.bash-god-publish.XXXXXX")" || \
    _bash_god_package_die 'could not create a private artifact publication file.'
  command cat "$source" > "$_bash_god_publish_current"
  chmod "$mode" "$_bash_god_publish_current"
  ln "$_bash_god_publish_current" "$target" || \
    _bash_god_package_die "refusing to overwrite artifact: $target"
  _bash_god_created_artifacts+=("$target")
  command rm -f -- "$_bash_god_publish_current"
  _bash_god_publish_current=''
}

_bash_god_compile_helper() {
  local target output os arch

  target=$1
  output=$2
  os=${target%-*}
  arch=${target#*-}
  case "$target" in
    darwin-amd64|darwin-arm64|linux-amd64|linux-arm64) ;;
    *) _bash_god_package_die "internal unsupported helper target: $target" ;;
  esac

  mkdir -p "$(dirname "$output")"
  GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
    GOCACHE="$_bash_god_stage/go-cache-$target" \
    go build -trimpath -buildvcs=false -ldflags='-s -w' \
      -o "$output" ./cmd/god-tui || \
    _bash_god_package_die "could not compile god-tui for $target"
  [ -f "$output" ] || _bash_god_package_die "compiler did not create a helper for $target"
  chmod 0755 "$output"
}

_bash_god_stage_runtime() {
  local root artifact target module catalog service

  root=$1
  artifact=$2
  target=${3:-}
  mkdir -p \
    "$root/bin" \
    "$root/lib/bash-god/src/ui" \
    "$root/lib/bash-god/catalog" \
    "$root/libexec/bash-god" \
    "$root/share/licenses/bash-god"

  cp "$_bash_god_package_dir/god" "$root/bin/god"
  cp "$_bash_god_repo_dir/god" "$root/lib/bash-god/god"
  for module in catalog.sh core.sh discover.sh eligibility.sh execute.sh interaction.sh maintenance.sh resolve.sh search.sh; do
    cp "$_bash_god_repo_dir/src/$module" "$root/lib/bash-god/src/$module"
  done
  for module in art.sh input.sh menu.sh render.sh tree.sh tui.sh; do
    cp "$_bash_god_repo_dir/src/ui/$module" "$root/lib/bash-god/src/ui/$module"
  done

  _bash_god_catalog_count=0
  for catalog in "$_bash_god_repo_dir"/catalog/*/service.god; do
    [ -f "$catalog" ] || continue
    service=${catalog%/service.god}
    service=${service##*/}
    case "$service" in
      ''|*[!a-z0-9_-]*) _bash_god_package_die "unsafe service directory: $service" ;;
    esac
    mkdir -p "$root/lib/bash-god/catalog/$service"
    cp "$catalog" "$root/lib/bash-god/catalog/$service/service.god"
    _bash_god_catalog_count=$((_bash_god_catalog_count + 1))
  done
  [ "$_bash_god_catalog_count" -gt 0 ] || _bash_god_package_die 'no service catalogs were found.'

  if [ "$artifact" = multi ]; then
    for target in "${_bash_god_targets[@]}"; do
      mkdir -p "$root/libexec/bash-god/$target"
      cp "$_bash_god_helpers/$target/god-tui" "$root/libexec/bash-god/$target/god-tui"
    done
  else
    case "$artifact" in
      darwin-amd64|darwin-arm64|linux-amd64|linux-arm64) ;;
      *) _bash_god_package_die "internal unsupported archive artifact: $artifact" ;;
    esac
    cp "$_bash_god_helpers/$artifact/god-tui" "$root/libexec/bash-god/god-tui"
  fi

  # This manifest is checked both by the installer and by the installed shell
  # adapter. The installer replaces `artifact` with the concrete local target
  # when it activates the legacy multi-helper bridge.
  printf 'BASH_GOD_TUI_MANIFEST_V1\nversion=%s\nartifact=%s\nprotocol=%s\n' \
    "$_bash_god_version" "$artifact" "$_bash_god_protocol" > "$root/lib/bash-god/tui-manifest"
  cp "$_bash_god_repo_dir/LICENSE" "$root/share/licenses/bash-god/LICENSE"
  cp "$_bash_god_package_dir/THIRD_PARTY_NOTICES.md" \
    "$root/share/licenses/bash-god/THIRD_PARTY_NOTICES.md"

  command find "$root" -type d -exec chmod 0755 {} \;
  command find "$root" -type f -exec chmod 0644 {} \;
  chmod 0755 "$root/bin/god" "$root/lib/bash-god/god"
  command find "$root/libexec/bash-god" -type f -name god-tui -exec chmod 0755 {} \;
}

_bash_god_archive_stage() {
  local name artifact target root archive checksum

  name=$1
  artifact=$2
  target=${3:-}
  root="$_bash_god_stage/$name"
  archive="$_bash_god_stage/$name.tar.gz"
  checksum="$archive.sha256"
  _bash_god_stage_runtime "$root" "$artifact" "$target"
  (
    CDPATH= cd "$_bash_god_repo_dir"
    GOCACHE="$_bash_god_stage/go-cache-archive" \
      go run ./cmd/god-archive --source "$root" --output "$archive"
  ) || _bash_god_package_die "could not create a normalized archive for $name"
  printf '%s  %s\n' "$(_bash_god_sha256 "$archive")" "$(basename "$archive")" > "$checksum"
  _bash_god_staged_archives+=("$archive")
  _bash_god_staged_checksums+=("$checksum")
}

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [OUTPUT_DIRECTORY]\n' "$0" >&2
  exit 2
fi

_bash_god_package_file="${BASH_SOURCE[0]}"
_bash_god_package_dir="$(CDPATH= cd "$(dirname "$_bash_god_package_file")" 2>/dev/null && pwd -P)" || exit 1
_bash_god_repo_dir="$(CDPATH= cd "$_bash_god_package_dir/.." 2>/dev/null && pwd -P)" || exit 1
_bash_god_core="$_bash_god_repo_dir/src/core.sh"
_bash_god_tui="$_bash_god_repo_dir/src/ui/tui.sh"
_bash_god_version_helpers="$_bash_god_package_dir/version.sh"

[ -r "$_bash_god_core" ] || _bash_god_package_die "cannot read $_bash_god_core"
[ -r "$_bash_god_tui" ] || _bash_god_package_die "cannot read $_bash_god_tui"
[ -r "$_bash_god_version_helpers" ] || _bash_god_package_die "cannot read $_bash_god_version_helpers"
[ -r "$_bash_god_package_dir/THIRD_PARTY_NOTICES.md" ] || \
  _bash_god_package_die 'cannot read packaged god-tui third-party notices.'
command -v go >/dev/null 2>&1 || _bash_god_package_die 'Go is required to build release helpers; installed users do not need Go.'

# shellcheck source=packaging/version.sh
. "$_bash_god_version_helpers"
_bash_god_version="$(_bash_god_package_version_from_core "$_bash_god_core")" || \
  _bash_god_package_die 'could not read a numeric BASH_GOD version from core.sh.'
_bash_god_protocol="$(LC_ALL=C awk -F= '
  /^_GOD_TUI_PROTOCOL_VERSION=/ {
    count++
    value=$2
    gsub(/[[:space:]]/, "", value)
  }
  END {
    if (count == 1 && value ~ /^[1-9][0-9]*$/) print value
    else exit 1
  }
' "$_bash_god_tui")" || _bash_god_package_die 'could not read a positive helper protocol version.'

_bash_god_targets=(darwin-amd64 darwin-arm64 linux-amd64 linux-arm64)
_bash_god_output_dir="${1:-$_bash_god_repo_dir/dist}"
mkdir -p "$_bash_god_output_dir"
_bash_god_output_dir="$(CDPATH= cd "$_bash_god_output_dir" 2>/dev/null && pwd -P)" || exit 1

_bash_god_archive_names=("bash-god-$_bash_god_version")
for _bash_god_target in "${_bash_god_targets[@]}"; do
  _bash_god_archive_names+=("bash-god-$_bash_god_version-$_bash_god_target")
done
_bash_god_output_names=(install-runtime.sh install-runtime.sh.sha256 install.sh install.sh.sha256)
for _bash_god_name in "${_bash_god_archive_names[@]}"; do
  _bash_god_output_names+=("$_bash_god_name.tar.gz" "$_bash_god_name.tar.gz.sha256")
done
for _bash_god_name in "${_bash_god_output_names[@]}"; do
  if [ -e "$_bash_god_output_dir/$_bash_god_name" ] || [ -L "$_bash_god_output_dir/$_bash_god_name" ]; then
    _bash_god_package_die "refusing to overwrite an existing artifact in $_bash_god_output_dir: $_bash_god_name"
  fi
done

_bash_god_stage="$(mktemp -d "${TMPDIR:-/tmp}/bash-god-package.XXXXXX")" || exit 1
_bash_god_helpers="$_bash_god_stage/helpers"
_bash_god_created_artifacts=()
_bash_god_publish_current=''
_bash_god_staged_archives=()
_bash_god_staged_checksums=()
_bash_god_package_cleanup() {
  _bash_god_cleanup_status="$1"
  if [ "$_bash_god_cleanup_status" -ne 0 ]; then
    # Bash 3.2 treats an empty-array expansion as unset under `set -u`.
    # A helper compilation can fail before the first artifact is published,
    # so guard the expansion and preserve the original failure/cleanup path.
    if [ "${#_bash_god_created_artifacts[@]}" -gt 0 ]; then
      for _bash_god_created_artifact in "${_bash_god_created_artifacts[@]}"; do
        command rm -f -- "$_bash_god_created_artifact"
      done
    fi
  fi
  [ -z "$_bash_god_publish_current" ] || command rm -f -- "$_bash_god_publish_current"
  command rm -rf -- "$_bash_god_stage"
}
trap '_bash_god_package_cleanup $?' EXIT
trap 'exit 1' HUP INT TERM

for _bash_god_target in "${_bash_god_targets[@]}"; do
  _bash_god_compile_helper "$_bash_god_target" "$_bash_god_helpers/$_bash_god_target/god-tui"
done

# The unsuffixed archive is intentionally multi-helper for installed runtimes
# from before R08. Its updater requests this legacy filename before it can run
# the new target-aware maintenance code. New installations never download it.
_bash_god_archive_stage "bash-god-$_bash_god_version" multi
for _bash_god_target in "${_bash_god_targets[@]}"; do
  _bash_god_archive_stage "bash-god-$_bash_god_version-$_bash_god_target" "$_bash_god_target"
done

_bash_god_staged_installer="$_bash_god_stage/install-runtime.sh"
_bash_god_staged_installer_checksum="$_bash_god_staged_installer.sha256"
_bash_god_staged_bootstrap="$_bash_god_stage/install.sh"
_bash_god_staged_bootstrap_checksum="$_bash_god_staged_bootstrap.sha256"
cp "$_bash_god_package_dir/install-runtime.sh" "$_bash_god_staged_installer"
chmod 0755 "$_bash_god_staged_installer"
printf '%s  %s\n' "$(_bash_god_sha256 "$_bash_god_staged_installer")" install-runtime.sh > \
  "$_bash_god_staged_installer_checksum"
cp "$_bash_god_package_dir/install.sh" "$_bash_god_staged_bootstrap"
chmod 0755 "$_bash_god_staged_bootstrap"
printf '%s  %s\n' "$(_bash_god_sha256 "$_bash_god_staged_bootstrap")" install.sh > \
  "$_bash_god_staged_bootstrap_checksum"

for _bash_god_archive in "${_bash_god_staged_archives[@]}"; do
  _bash_god_name="$(basename "$_bash_god_archive")"
  _bash_god_publish_file "$_bash_god_archive" "$_bash_god_output_dir/$_bash_god_name" 0644
done
for _bash_god_checksum in "${_bash_god_staged_checksums[@]}"; do
  _bash_god_name="$(basename "$_bash_god_checksum")"
  _bash_god_publish_file "$_bash_god_checksum" "$_bash_god_output_dir/$_bash_god_name" 0644
done
_bash_god_publish_file "$_bash_god_staged_installer" "$_bash_god_output_dir/install-runtime.sh" 0755
_bash_god_publish_file "$_bash_god_staged_installer_checksum" "$_bash_god_output_dir/install-runtime.sh.sha256" 0644
_bash_god_publish_file "$_bash_god_staged_bootstrap" "$_bash_god_output_dir/install.sh" 0755
_bash_god_publish_file "$_bash_god_staged_bootstrap_checksum" "$_bash_god_output_dir/install.sh.sha256" 0644

printf 'Built direct-install compatibility archive: %s\n' "$_bash_god_output_dir/bash-god-$_bash_god_version.tar.gz"
for _bash_god_target in "${_bash_god_targets[@]}"; do
  printf 'Built native helper archive: %s\n' \
    "$_bash_god_output_dir/bash-god-$_bash_god_version-$_bash_god_target.tar.gz"
done
printf 'Installer: %s\n' "$_bash_god_output_dir/install-runtime.sh"
printf 'Bootstrap: %s\n' "$_bash_god_output_dir/install.sh"
