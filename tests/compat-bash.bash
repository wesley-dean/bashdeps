#!/usr/bin/env bash

set -u
set -o pipefail

failures=0
BASHDEPS_EXECUTABLE=${BASHDEPS_EXECUTABLE:-src/bashdeps.bash}

check_status() {
  local expected actual label
  expected=$1
  actual=$2
  label=$3
  if [[ $expected -ne $actual ]]; then
    printf 'FAIL: %s: expected status %s, got %s\n' "$label" "$expected" "$actual" >&2
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

status=0
capture_status status bash "$BASHDEPS_EXECUTABLE" --help
check_status 0 "$status" 'help'

capture_status status bash "$BASHDEPS_EXECUTABLE" --version
check_status 0 "$status" 'version'

capture_status status bash "$BASHDEPS_EXECUTABLE" unknown
check_status 2 "$status" 'unknown command'

capture_status status bash "$BASHDEPS_EXECUTABLE" install \
  id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:bad
check_status 2 "$status" 'invalid digest'

if ((failures != 0)); then
  printf 'Bash %s compatibility: %s failure(s)\n' "$BASH_VERSION" "$failures" >&2
  exit 1
fi

printf 'Bash %s compatibility checks passed for %s\n' "$BASH_VERSION" "$BASHDEPS_EXECUTABLE"
