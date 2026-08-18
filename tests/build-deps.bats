#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK/src" "$WORK/mock-bin"
  cp "$REPO_ROOT/Makefile" "$WORK/Makefile"
  cp "$REPO_ROOT/src/bashdeps.bash" "$WORK/src/bashdeps.bash"
  cp "$REPO_ROOT/dependencies.txt" "$WORK/dependencies.txt"

  printf '%s\n' 'managed documentation filter bytes' >"$WORK/managed-filter-source"

  cat >"$WORK/managed-minifier-source" <<'FAKE'
#!/usr/bin/env bash
set -eu
cat
FAKE

  cat >"$WORK/fake-bashdeps" <<'FAKE'
#!/usr/bin/env bash
set -eu

command=${1:-}
manifest=${2:-dependencies.txt}
filter_source=${FAKE_FILTER_SOURCE:?}
minifier_source=${FAKE_MINIFIER_SOURCE:?}
filter_destination=vendor/doxygen-bash.awk
minifier_destination=vendor/bash-minifier.bash

[[ -r $manifest ]]

sync_one() {
  local source=$1
  local destination=$2

  mkdir -p "$(dirname "$destination")"
  if [[ ! -f $destination ]] || ! cmp -s "$source" "$destination"; then
    cp "$source" "$destination"
    if [[ -n ${FAKE_SYNC_REPLACED_MARKER:-} ]]; then
      : >"$FAKE_SYNC_REPLACED_MARKER"
    fi
  fi
}

verify_one() {
  local source=$1
  local destination=$2

  [[ -f $destination ]]
  cmp -s "$source" "$destination"
}

case $command in
  sync)
    sync_one "$filter_source" "$filter_destination"
    sync_one "$minifier_source" "$minifier_destination"
    ;;
  verify)
    verify_one "$filter_source" "$filter_destination"
    verify_one "$minifier_source" "$minifier_destination"
    ;;
  *)
    exit 64
    ;;
esac
FAKE
  chmod 0755 "$WORK/fake-bashdeps"
  FAKE_BASHDEPS_SHA256="$(sha256sum "$WORK/fake-bashdeps" | awk '{print $1}')"

  cat >"$WORK/mock-bin/curl" <<'FAKE'
#!/usr/bin/env bash
set -eu

out=''
while (($#)); do
  case $1 in
    -o | --output)
      out=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n $out ]]
cp "${FAKE_CURL_SOURCE:?}" "$out"
if [[ -n ${FAKE_CURL_MARKER:-} ]]; then
  : >"$FAKE_CURL_MARKER"
fi
FAKE
  chmod 0755 "$WORK/mock-bin/curl"
}

run_make() {
  env \
    PATH="$WORK/mock-bin:$PATH" \
    FAKE_CURL_SOURCE="${FAKE_CURL_SOURCE:-$WORK/fake-bashdeps}" \
    FAKE_CURL_MARKER="${FAKE_CURL_MARKER:-}" \
    FAKE_FILTER_SOURCE="$WORK/managed-filter-source" \
    FAKE_MINIFIER_SOURCE="$WORK/managed-minifier-source" \
    FAKE_SYNC_REPLACED_MARKER="${FAKE_SYNC_REPLACED_MARKER:-}" \
    make -C "$WORK" \
      BASHDEPS_URL=https://example.test/bashdeps.bash \
      BASHDEPS_SHA256="$FAKE_BASHDEPS_SHA256" \
      "$@"
}

@test "plain build fails without acquiring dependency state" {
  run make -C "$WORK" build VERSION=0.0.0-test

  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing Bash-Minifier build dependency"* ]]
  [ ! -e "$WORK/vendor" ]
  [ ! -e "$WORK/dist" ]
}

@test "deps bootstraps released bashdeps and converges managed state" {
  FAKE_CURL_MARKER="$WORK/curl-called"
  FAKE_SYNC_REPLACED_MARKER="$WORK/replaced"

  run run_make deps

  [ "$status" -eq 0 ]
  [ -x "$WORK/vendor/bashdeps.bash" ]
  cmp -s "$WORK/fake-bashdeps" "$WORK/vendor/bashdeps.bash"
  cmp -s "$WORK/managed-filter-source" "$WORK/vendor/doxygen-bash.awk"
  cmp -s "$WORK/managed-minifier-source" "$WORK/vendor/bash-minifier.bash"
  [ -e "$WORK/curl-called" ]
  [ -e "$WORK/replaced" ]

  rm -f "$WORK/curl-called" "$WORK/replaced"
  run run_make deps

  [ "$status" -eq 0 ]
  [ ! -e "$WORK/curl-called" ]
  [ ! -e "$WORK/replaced" ]

  printf '%s\n' 'stale minifier bytes' >"$WORK/vendor/bash-minifier.bash"
  FAKE_SYNC_REPLACED_MARKER="$WORK/replaced"
  run run_make deps

  [ "$status" -eq 0 ]
  [ -e "$WORK/replaced" ]
  cmp -s "$WORK/managed-minifier-source" "$WORK/vendor/bash-minifier.bash"
}

@test "deps-check detects minifier tampering without network repair" {
  run run_make deps
  [ "$status" -eq 0 ]

  printf '%s\n' 'tampered bytes' >"$WORK/vendor/bash-minifier.bash"
  FAKE_CURL_MARKER="$WORK/curl-called"

  run run_make deps-check

  [ "$status" -ne 0 ]
  [ ! -e "$WORK/curl-called" ]
  [ "$(cat "$WORK/vendor/bash-minifier.bash")" = 'tampered bytes' ]
}

@test "failed bootstrap digest verification preserves existing bytes" {
  mkdir -p "$WORK/vendor"
  printf '%s\n' 'previous bootstrap bytes' >"$WORK/vendor/bashdeps.bash"
  chmod 0755 "$WORK/vendor/bashdeps.bash"
  printf '%s\n' 'unverified candidate bytes' >"$WORK/bad-bootstrap"
  FAKE_CURL_SOURCE="$WORK/bad-bootstrap"

  run run_make deps

  [ "$status" -ne 0 ]
  [ "$(cat "$WORK/vendor/bashdeps.bash")" = 'previous bootstrap bytes' ]
  [ ! -e "$WORK/vendor/bashdeps.bash.tmp" ]
}

@test "prepared build remains network-free" {
  run run_make deps
  [ "$status" -eq 0 ]

  FAKE_CURL_MARKER="$WORK/curl-called"
  run run_make build VERSION=0.0.0-test

  [ "$status" -eq 0 ]
  [ ! -e "$WORK/curl-called" ]
  [ -x "$WORK/dist/bashdeps.dev.bash" ]
  [ -x "$WORK/dist/bashdeps.bash" ]
  [ -x "$WORK/dist/bashdeps.min.bash" ]
}

@test "all synchronizes dependencies before building all release flavors" {
  run run_make all VERSION=0.0.0-test

  [ "$status" -eq 0 ]
  cmp -s "$WORK/managed-filter-source" "$WORK/vendor/doxygen-bash.awk"
  cmp -s "$WORK/managed-minifier-source" "$WORK/vendor/bash-minifier.bash"
  [ -x "$WORK/dist/bashdeps.dev.bash" ]
  [ -x "$WORK/dist/bashdeps.bash" ]
  [ -x "$WORK/dist/bashdeps.min.bash" ]
  [ -f "$WORK/dist/bashdeps.dev.bash.256" ]
  [ -f "$WORK/dist/bashdeps.bash.256" ]
  [ -f "$WORK/dist/bashdeps.min.bash.256" ]
}

@test "distclean removes generated vendor and reference state" {
  mkdir -p "$WORK/vendor" "$WORK/doc/reference" "$WORK/dist"
  : >"$WORK/vendor/bashdeps.bash"
  : >"$WORK/vendor/doxygen-bash.awk"
  : >"$WORK/vendor/bash-minifier.bash"
  : >"$WORK/doc/reference/index.html"
  : >"$WORK/dist/bashdeps.bash"
  : >"$WORK/dist/bashdeps.min.bash"

  run make -C "$WORK" distclean

  [ "$status" -eq 0 ]
  [ ! -e "$WORK/vendor" ]
  [ ! -e "$WORK/doc/reference" ]
  [ ! -e "$WORK/dist" ]
}

@test "generated release artifacts run without bootstrap manifest or vendor tree" {
  run run_make all VERSION=0.0.0-test
  [ "$status" -eq 0 ]

  rm -rf "$WORK/vendor" "$WORK/dependencies.txt"

  for artifact in bashdeps.dev.bash bashdeps.bash bashdeps.min.bash; do
    run "$WORK/dist/$artifact" --version
    [ "$status" -eq 0 ]
    [[ "$output" == bashdeps.bash\ * ]]
  done
}
