#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK/src" "$WORK/mock-bin"
  cp "$REPO_ROOT/Makefile" "$WORK/Makefile"
  cp "$REPO_ROOT/src/bashdeps.bash" "$WORK/src/bashdeps.bash"
  cp "$REPO_ROOT/dependencies.txt" "$WORK/dependencies.txt"

  printf '%s\n' 'managed documentation filter bytes' >"$WORK/managed-source"

  cat >"$WORK/fake-bashdeps" <<'FAKE'
#!/usr/bin/env bash
set -eu

command=${1:-}
manifest=${2:-dependencies.txt}
source_path=${FAKE_MANAGED_SOURCE:?}
destination=vendor/doxygen-bash.awk

[[ -r $manifest ]]

case $command in
  sync)
    mkdir -p vendor
    if [[ ! -f $destination ]] || ! cmp -s "$source_path" "$destination"; then
      cp "$source_path" "$destination"
      if [[ -n ${FAKE_SYNC_REPLACED_MARKER:-} ]]; then
        : >"$FAKE_SYNC_REPLACED_MARKER"
      fi
    fi
    ;;
  verify)
    [[ -f $destination ]]
    cmp -s "$source_path" "$destination"
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
    FAKE_MANAGED_SOURCE="$WORK/managed-source" \
    FAKE_SYNC_REPLACED_MARKER="${FAKE_SYNC_REPLACED_MARKER:-}" \
    make -C "$WORK" \
      BASHDEPS_URL=https://example.test/bashdeps.bash \
      BASHDEPS_SHA256="$FAKE_BASHDEPS_SHA256" \
      "$@"
}

@test "plain build succeeds without acquiring dependency state" {
  run make -C "$WORK" build VERSION=0.0.0-test

  [ "$status" -eq 0 ]
  [ -x "$WORK/dist/bashdeps.bash" ]
  [ -x "$WORK/dist/bashdeps.dev.bash" ]
  [ ! -e "$WORK/vendor" ]
}

@test "deps bootstraps released bashdeps and converges managed state" {
  FAKE_CURL_MARKER="$WORK/curl-called"
  FAKE_SYNC_REPLACED_MARKER="$WORK/replaced"

  run run_make deps

  [ "$status" -eq 0 ]
  [ -x "$WORK/vendor/bashdeps.bash" ]
  cmp -s "$WORK/fake-bashdeps" "$WORK/vendor/bashdeps.bash"
  cmp -s "$WORK/managed-source" "$WORK/vendor/doxygen-bash.awk"
  [ -e "$WORK/curl-called" ]
  [ -e "$WORK/replaced" ]

  rm -f "$WORK/curl-called" "$WORK/replaced"
  run run_make deps

  [ "$status" -eq 0 ]
  [ ! -e "$WORK/curl-called" ]
  [ ! -e "$WORK/replaced" ]

  printf '%s\n' 'stale managed bytes' >"$WORK/vendor/doxygen-bash.awk"
  FAKE_SYNC_REPLACED_MARKER="$WORK/replaced"
  run run_make deps

  [ "$status" -eq 0 ]
  [ -e "$WORK/replaced" ]
  cmp -s "$WORK/managed-source" "$WORK/vendor/doxygen-bash.awk"
}

@test "deps-check detects tampering without network repair" {
  run run_make deps
  [ "$status" -eq 0 ]

  printf '%s\n' 'tampered bytes' >"$WORK/vendor/doxygen-bash.awk"
  FAKE_CURL_MARKER="$WORK/curl-called"

  run run_make deps-check

  [ "$status" -ne 0 ]
  [ ! -e "$WORK/curl-called" ]
  [ "$(cat "$WORK/vendor/doxygen-bash.awk")" = 'tampered bytes' ]
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

@test "all synchronizes dependencies before building" {
  run run_make all VERSION=0.0.0-test

  [ "$status" -eq 0 ]
  cmp -s "$WORK/managed-source" "$WORK/vendor/doxygen-bash.awk"
  [ -x "$WORK/dist/bashdeps.bash" ]
}

@test "distclean removes generated vendor and reference state" {
  mkdir -p "$WORK/vendor" "$WORK/doc/reference" "$WORK/dist"
  : >"$WORK/vendor/bashdeps.bash"
  : >"$WORK/vendor/doxygen-bash.awk"
  : >"$WORK/doc/reference/index.html"
  : >"$WORK/dist/bashdeps.bash"

  run make -C "$WORK" distclean

  [ "$status" -eq 0 ]
  [ ! -e "$WORK/vendor" ]
  [ ! -e "$WORK/doc/reference" ]
  [ ! -e "$WORK/dist" ]
}

@test "generated consumer artifact runs without bootstrap manifest or vendor tree" {
  run make -C "$WORK" build VERSION=0.0.0-test
  [ "$status" -eq 0 ]

  rm -rf "$WORK/vendor" "$WORK/dependencies.txt"
  run "$WORK/dist/bashdeps.bash" --version

  [ "$status" -eq 0 ]
  [[ "$output" == bashdeps.bash\ * ]]
}
