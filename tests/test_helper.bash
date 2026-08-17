#!/usr/bin/env bash

bashdeps_test_setup() {
  local raw_executable
  raw_executable=${BASHDEPS_EXECUTABLE:-$BATS_TEST_DIRNAME/../src/bashdeps.bash}
  BASHDEPS_TEST_EXECUTABLE="$(cd "$(dirname "$raw_executable")" && pwd -P)/$(basename "$raw_executable")"
  export BASHDEPS_TEST_EXECUTABLE
  BASHDEPS_TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$BASHDEPS_TEST_PROJECT"
  cd "$BASHDEPS_TEST_PROJECT" || return
}

bashdeps_sha256_of() {
  local output
  output=$(sha256sum "$1")
  printf '%s\n' "${output%%[[:space:]]*}"
}

bashdeps_make_mock_curl() {
  mkdir -p "$BASHDEPS_TEST_PROJECT/mock-bin"
  cat >"$BASHDEPS_TEST_PROJECT/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -eu
out=''
url=''
while (($#)); do
  case $1 in
    --output)
      out=$2
      shift 2
      ;;
    --)
      shift
      url=${1:-}
      break
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n $out && -n $url ]]
if [[ -n ${MOCK_CURL_MARKER:-} ]]; then
  : >"$MOCK_CURL_MARKER"
fi
case $url in
  */good*) cp "$MOCK_GOOD_SOURCE" "$out" ;;
  */bad*) cp "$MOCK_BAD_SOURCE" "$out" ;;
  *) cp "$MOCK_SOURCE" "$out" ;;
esac
MOCK
  chmod +x "$BASHDEPS_TEST_PROJECT/mock-bin/curl"
}

bashdeps_make_base_isolated_path() {
  local command path
  mkdir -p "$BASHDEPS_TEST_PROJECT/isolated-bin"
  for command in bash mkdir rm chmod cp mv; do
    path=$(command -v "$command")
    ln -s "$path" "$BASHDEPS_TEST_PROJECT/isolated-bin/$command"
  done
}

bashdeps_make_isolated_path() {
  local path
  bashdeps_make_base_isolated_path
  path=$(command -v sha256sum)
  ln -s "$path" "$BASHDEPS_TEST_PROJECT/isolated-bin/sha256sum"
}

bashdeps_make_mock_shasum_path() {
  local sha256sum_path
  bashdeps_make_base_isolated_path
  sha256sum_path=$(command -v sha256sum)
  cat >"$BASHDEPS_TEST_PROJECT/isolated-bin/shasum" <<MOCK
#!/bin/bash
set -eu
[[ \${1:-} == '-a' && \${2:-} == '256' ]]
shift 2
"$sha256sum_path" "\$@"
MOCK
  chmod +x "$BASHDEPS_TEST_PROJECT/isolated-bin/shasum"
}

bashdeps_make_mock_wget() {
  cat >"$BASHDEPS_TEST_PROJECT/isolated-bin/wget" <<'MOCK'
#!/bin/bash
set -eu
out=''
url=''
while (($#)); do
  case $1 in
    -q) shift ;;
    -O) out=$2; shift 2 ;;
    *) url=$1; shift ;;
  esac
done
[[ -n $out && -n $url ]]
cp "$MOCK_SOURCE" "$out"
MOCK
  chmod +x "$BASHDEPS_TEST_PROJECT/isolated-bin/wget"
}
