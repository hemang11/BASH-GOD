#!/usr/bin/env bash

# Static contract for the cross-repository Homebrew publishing path. Runtime
# formula behavior is covered by the layout/install tests; this makes sure a
# future release still downloads its immutable assets, verifies them, and
# updates only the official tap's live formula.

set -o nounset
set -o pipefail

test_file=${BASH_SOURCE[0]}
test_dir="$(CDPATH= cd "$(dirname "$test_file")" 2>/dev/null && pwd -P)" || exit 1
repo_dir="$(CDPATH= cd "$test_dir/../.." 2>/dev/null && pwd -P)" || exit 1
workflow="$repo_dir/.github/workflows/release.yml"

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
  LC_ALL=C grep -F -- "$2" "$1" >/dev/null 2>&1
}

line_of() {
  LC_ALL=C grep -n -F -- "$2" "$1" | LC_ALL=C sed -n '1s/:.*//p'
}

if contains "$workflow" 'HOMEBREW_TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}' && \
   contains "$workflow" 'HOMEBREW_TAP_TOKEN is required to publish the matching Homebrew formula.'; then
  pass 'release refuses to publish when the scoped tap credential is absent'
else
  fail 'release refuses to publish when the scoped tap credential is absent'
fi

if contains "$workflow" 'version: ${{ steps.release.outputs.version }}' && \
   contains "$workflow" 'name: Publish Homebrew formula' && \
   contains "$workflow" 'needs: release'; then
  pass 'formula publishing receives the version verified by the release job'
else
  fail 'formula publishing receives the version verified by the release job'
fi

release_line="$(line_of "$workflow" 'gh release create "$GITHUB_REF_NAME"')"
download_line="$(line_of "$workflow" 'gh release download "v$VERSION"')"
if [ -n "$release_line" ] && [ -n "$download_line" ] && [ "$release_line" -lt "$download_line" ] && \
   contains "$workflow" 'sha256sum -c "bash-god-$VERSION-$target.tar.gz.sha256"'; then
  pass 'formula rendering consumes and verifies the immutable published target archives'
else
  fail 'formula rendering consumes and verifies the immutable published target archives'
fi

if contains "$workflow" 'repository: hemang11/homebrew-tap' && \
   contains "$workflow" 'ref: live' && \
   contains "$workflow" 'path: homebrew-tap' && \
   contains "$workflow" 'packaging/homebrew/render-formula.sh' && \
   contains "$workflow" 'homebrew-tap/Formula/bash-god.rb' && \
   contains "$workflow" 'git -C homebrew-tap push origin HEAD:live'; then
  pass 'formula sync renders and commits only to the official tap live branch'
else
  fail 'formula sync renders and commits only to the official tap live branch'
fi

if [ "$failures" -eq 0 ]; then
  printf '\n%d Homebrew release-sync checks passed.\n' "$checks"
  exit 0
fi

printf '\n%d of %d Homebrew release-sync checks failed.\n' "$failures" "$checks" >&2
exit 1
