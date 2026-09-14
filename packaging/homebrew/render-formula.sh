#!/usr/bin/env bash

# Render the immutable Formula/bash-god.rb that a release can hand to the
# separate Homebrew tap. This repository deliberately stores the renderer,
# not a stale formula pinned to an old GitHub Release checksum.

set -o errexit
set -o nounset
set -o pipefail

die() {
  printf 'BASH_GOD Homebrew formula: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'Usage: %s --version VERSION --darwin-amd64 ARCHIVE --darwin-arm64 ARCHIVE --linux-amd64 ARCHIVE --linux-arm64 ARCHIVE [--base-url URL] [--output FILE]\n' "$0"
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | LC_ALL=C awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | LC_ALL=C awk '{ print $1 }'
  else
    die 'sha256sum or shasum is required.'
  fi
}

version=''
darwin_amd64=''
darwin_arm64=''
linux_amd64=''
linux_arm64=''
output=''
base_url=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || die '--version requires a value.'
      version=$2
      shift 2
      ;;
    --darwin-amd64)
      [ "$#" -ge 2 ] || die '--darwin-amd64 requires an archive.'
      darwin_amd64=$2
      shift 2
      ;;
    --darwin-arm64)
      [ "$#" -ge 2 ] || die '--darwin-arm64 requires an archive.'
      darwin_arm64=$2
      shift 2
      ;;
    --linux-amd64)
      [ "$#" -ge 2 ] || die '--linux-amd64 requires an archive.'
      linux_amd64=$2
      shift 2
      ;;
    --linux-arm64)
      [ "$#" -ge 2 ] || die '--linux-arm64 requires an archive.'
      linux_arm64=$2
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || die '--output requires a file.'
      output=$2
      shift 2
      ;;
    --base-url)
      [ "$#" -ge 2 ] || die '--base-url requires a value.'
      base_url=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

case "$version" in
  ''|*[!0-9.]*) die 'VERSION must contain only dotted numeric components.' ;;
esac

for target in darwin-amd64 darwin-arm64 linux-amd64 linux-arm64; do
  case "$target" in
    darwin-amd64) archive=$darwin_amd64 ;;
    darwin-arm64) archive=$darwin_arm64 ;;
    linux-amd64) archive=$linux_amd64 ;;
    linux-arm64) archive=$linux_arm64 ;;
  esac
  [ -f "$archive" ] && [ ! -L "$archive" ] || die "missing regular archive for $target."
  expected="bash-god-$version-$target.tar.gz"
  [ "$(basename "$archive")" = "$expected" ] || die "expected $expected for $target."
done

darwin_amd64_sha="$(sha256 "$darwin_amd64")"
darwin_arm64_sha="$(sha256 "$darwin_arm64")"
linux_amd64_sha="$(sha256 "$linux_amd64")"
linux_arm64_sha="$(sha256 "$linux_arm64")"
if [ -z "$base_url" ]; then
  base_url="https://github.com/hemang11/BASH-GOD/releases/download/v$version"
fi
case "$base_url" in
  *$'\n'*|*$'\r'*|*'"'*|*'\\'*) die '--base-url contains an unsafe Formula string character.' ;;
  https://*|file://*) ;;
  *) die '--base-url must begin with https:// or file://.' ;;
esac
base_url=${base_url%/}

if [ -z "$output" ]; then
  output='-'
fi

render() {
  printf '%s\n' \
    '# typed: strict' \
    '# frozen_string_literal: true' \
    '' \
    '# BASH_GOD packages searchable local command memory for reviewed native operations.' \
    'class BashGod < Formula' \
    '  desc "Searchable local command memory for reviewed native operations"' \
    '  homepage "https://github.com/hemang11/BASH-GOD"' \
    '  license "MIT"' \
    '' \
    '  on_macos do' \
    '    on_arm do' \
    "      url \"$base_url/bash-god-$version-darwin-arm64.tar.gz\"" \
    "      sha256 \"$darwin_arm64_sha\"" \
    '    end' \
    '' \
    '    on_intel do' \
    "      url \"$base_url/bash-god-$version-darwin-amd64.tar.gz\"" \
    "      sha256 \"$darwin_amd64_sha\"" \
    '    end' \
    '  end' \
    '' \
    '  on_linux do' \
    '    on_arm do' \
    "      url \"$base_url/bash-god-$version-linux-arm64.tar.gz\"" \
    "      sha256 \"$linux_arm64_sha\"" \
    '    end' \
    '' \
    '    on_intel do' \
    "      url \"$base_url/bash-god-$version-linux-amd64.tar.gz\"" \
    "      sha256 \"$linux_amd64_sha\"" \
    '    end' \
    '  end' \
    '' \
    '  def install' \
    '    target = if OS.mac?' \
    '      Hardware::CPU.arm? ? "darwin-arm64" : "darwin-amd64"' \
    '    else' \
    '      Hardware::CPU.arm? ? "linux-arm64" : "linux-amd64"' \
    '    end' \
    '    package_root = "bash-god-#{version}-#{target}"' \
    '    source_root = if Dir.exist?(package_root)' \
    '      package_root' \
    '    elsif (buildpath/"bin").directory? && (buildpath/"lib/bash-god/god").executable?' \
    '      "."' \
    '    else' \
    '      odie "missing BASH_GOD runtime directory: #{package_root}"' \
    '    end' \
    '    libexec.install Dir.children(source_root).map { |entry| "#{source_root}/#{entry}" }' \
    '    bin.install_symlink libexec/"bin/god"' \
    '  end' \
    '' \
    '  test do' \
    '    assert_match "BASH_GOD #{version}", shell_output("#{bin}/god --version")' \
    '    assert_match "GENERAL COMMANDS", shell_output("#{bin}/god general --quiet")' \
    '  end' \
    'end'
}

if [ "$output" = '-' ]; then
  render
  exit 0
fi

output_dir="$(dirname "$output")"
[ -d "$output_dir" ] || die "output directory does not exist: $output_dir"
[ ! -e "$output" ] && [ ! -L "$output" ] || die "refusing to overwrite an existing formula: $output"
temporary_output="$(mktemp "$output_dir/.bash-god-formula.XXXXXX")" || die 'could not create a temporary formula file.'
cleanup() {
  command rm -f -- "$temporary_output"
}
trap cleanup EXIT HUP INT TERM
render > "$temporary_output"
chmod 0644 "$temporary_output"
mv "$temporary_output" "$output"
trap - EXIT HUP INT TERM
