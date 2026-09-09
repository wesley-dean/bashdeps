#!/usr/bin/env bash

set -u
set -o pipefail

failures=0
MANIFEST_MANAGER_EXECUTABLE=${MANIFEST_MANAGER_EXECUTABLE:-src/manifest-manager.bash}

check_status() {
  local expected=$1 actual=$2 label=$3
  if [[ $expected -ne $actual ]]; then
    printf 'FAIL: %s: expected status %s, got %s\n' \
      "$label" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

capture_status() {
  local status_name=$1
  shift
  local result
  if "$@" >/dev/null 2>&1; then
    result=0
  else
    result=$?
  fi
  printf -v "$status_name" '%s' "$result"
}

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  printf 'FAIL: Bash 4.3 or newer required; found %s\n' "$BASH_VERSION" >&2
  exit 1
fi

if ! bash -n "$MANIFEST_MANAGER_EXECUTABLE"; then
  printf 'FAIL: Bash %s cannot parse %s\n' \
    "$BASH_VERSION" "$MANIFEST_MANAGER_EXECUTABLE" >&2
  exit 1
fi

status=0
capture_status status bash "$MANIFEST_MANAGER_EXECUTABLE" --help
check_status 0 "$status" 'help'

capture_status status bash "$MANIFEST_MANAGER_EXECUTABLE" --version
check_status 0 "$status" 'version'

capture_status status bash "$MANIFEST_MANAGER_EXECUTABLE" list --help
check_status 0 "$status" 'list help'

capture_status status bash "$MANIFEST_MANAGER_EXECUTABLE" add --help
check_status 0 "$status" 'add help'

capture_status status bash "$MANIFEST_MANAGER_EXECUTABLE" remove --help
check_status 0 "$status" 'remove help'

capture_status status bash "$MANIFEST_MANAGER_EXECUTABLE" unknown
check_status 2 "$status" 'unknown command'

work=${TMPDIR:-/tmp}/manifest-manager-compat.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
printf '%s\n' '# rollback input' >"$work/input"
if bash "$MANIFEST_MANAGER_EXECUTABLE" update -f - --all extra \
  <"$work/input" >"$work/output" 2>/dev/null; then
  status=0
else
  status=$?
fi
check_status 2 "$status" 'stream CLI failure'
if ! cmp -s "$work/input" "$work/output"; then
  printf 'FAIL: stream CLI rollback did not preserve input bytes\n' >&2
  failures=$((failures + 1))
fi

digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
printf '%s\n' \
  "id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool digest=sha256:$digest" \
  >"$work/dependencies.txt"
if bash "$MANIFEST_MANAGER_EXECUTABLE" list -f "$work/dependencies.txt" \
  >"$work/list-output" 2>/dev/null; then
  status=0
else
  status=$?
fi
check_status 0 "$status" 'list manifest identities'
if [[ $(cat "$work/list-output") != 'acme/tool@v1' ]]; then
  printf 'FAIL: list did not emit the complete identity\n' >&2
  failures=$((failures + 1))
fi

if bash "$MANIFEST_MANAGER_EXECUTABLE" add -f "$work/dependencies.txt" \
  id=acme/other@v2 \
  url=https://example.test/other \
  dest=vendor/other \
  "digest=sha256:$digest" >/dev/null 2>&1; then
  status=0
else
  status=$?
fi
check_status 0 "$status" 'add explicit declaration'
if ! grep -Fq 'id=acme/other@v2 url=https://example.test/other dest=vendor/other' \
  "$work/dependencies.txt"; then
  printf 'FAIL: add did not append the expected declaration\n' >&2
  failures=$((failures + 1))
fi

if bash "$MANIFEST_MANAGER_EXECUTABLE" remove -f "$work/dependencies.txt" \
  acme/tool@v1 >/dev/null 2>&1; then
  status=0
else
  status=$?
fi
check_status 0 "$status" 'remove exact declaration'
if grep -Fq 'id=acme/tool@v1 ' "$work/dependencies.txt"; then
  printf 'FAIL: remove left the selected declaration in the manifest\n' >&2
  failures=$((failures + 1))
fi
if ! grep -Fq 'id=acme/other@v2 ' "$work/dependencies.txt"; then
  printf 'FAIL: remove did not preserve the unrelated declaration\n' >&2
  failures=$((failures + 1))
fi

if ((failures != 0)); then
  printf 'Bash %s manifest-manager compatibility: %s failure(s)\n' \
    "$BASH_VERSION" "$failures" >&2
  exit 1
fi

printf 'Bash %s compatibility checks passed for %s\n' \
  "$BASH_VERSION" "$MANIFEST_MANAGER_EXECUTABLE"
