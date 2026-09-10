#!/usr/bin/env bats

load test_helper

setup() {
  bashdeps_test_setup
  BASHDEPS_CURL_MAP="$BASHDEPS_TEST_PROJECT/digest-url-curl-map"
  BASHDEPS_CURL_LOG="$BASHDEPS_TEST_PROJECT/digest-url-curl-log"
  : >"$BASHDEPS_CURL_MAP"
  : >"$BASHDEPS_CURL_LOG"
  export BASHDEPS_CURL_MAP BASHDEPS_CURL_LOG
  make_digest_url_mock_curl
}

make_digest_url_mock_curl() {
  mkdir -p "$BASHDEPS_TEST_PROJECT/mock-bin"
  cat >"$BASHDEPS_TEST_PROJECT/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -u
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
[[ -n $out && -n $url ]] || exit 97
printf '%s\n' "$url" >>"$BASHDEPS_CURL_LOG"
found=0
while IFS='|' read -r request source status; do
  [[ $request == "$url" ]] || continue
  found=1
  status=${status:-0}
  ((status == 0)) || exit "$status"
  [[ -n $source && -r $source ]] || exit 95
  cp "$source" "$out"
  break
done <"$BASHDEPS_CURL_MAP"
((found)) || exit 22
MOCK
  chmod 0755 "$BASHDEPS_TEST_PROJECT/mock-bin/curl"
}

map_digest_url_request() {
  local request=$1 source=${2:-} status=${3:-0}
  printf '%s|%s|%s\n' "$request" "$source" "$status" >>"$BASHDEPS_CURL_MAP"
}

run_bashdeps() {
  env \
    PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" \
    BASHDEPS_CURL_MAP="$BASHDEPS_CURL_MAP" \
    BASHDEPS_CURL_LOG="$BASHDEPS_CURL_LOG" \
    bash "$BASHDEPS_TEST_EXECUTABLE" "$@"
}

@test "four-field manifests remain backward compatible without checksum requests" {
  printf 'approved bytes\n' >artifact
  digest=$(bashdeps_sha256_of artifact)
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s\n' \
    "$digest" >dependencies.txt

  run run_bashdeps sync

  [ "$status" -eq 0 ]
  [ "$(cat vendor/tool)" = 'approved bytes' ]
  [ "$(cat "$BASHDEPS_CURL_LOG")" = 'https://example.test/tool' ]
}

@test "correct cached bytes with digest_url require no network access" {
  mkdir -p vendor
  printf 'approved bytes\n' >vendor/tool
  digest=$(bashdeps_sha256_of vendor/tool)
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/tool.sha256\n' \
    "$digest" >dependencies.txt

  run run_bashdeps sync

  [ "$status" -eq 0 ]
  [ ! -s "$BASHDEPS_CURL_LOG" ]
}

@test "verify validates digest_url syntax but remains network-free" {
  mkdir -p vendor
  printf 'approved bytes\n' >vendor/tool
  digest=$(bashdeps_sha256_of vendor/tool)
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/tool.sha256\n' \
    "$digest" >dependencies.txt

  run run_bashdeps verify

  [ "$status" -eq 0 ]
  [ ! -s "$BASHDEPS_CURL_LOG" ]
}

@test "fresh sync accepts a matching bare upstream SHA-256 digest" {
  printf 'approved bytes\n' >artifact
  digest=$(bashdeps_sha256_of artifact)
  printf '%s\n' "$digest" >checksum
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  map_digest_url_request 'https://checks.example.test/tool.sha256' "$BASHDEPS_TEST_PROJECT/checksum"
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://checks.example.test/tool.sha256\n' \
    "$digest" >dependencies.txt

  run run_bashdeps sync

  [ "$status" -eq 0 ]
  [ "$(cat vendor/tool)" = 'approved bytes' ]
  [ "$(wc -l <"$BASHDEPS_CURL_LOG")" -eq 2 ]
}

@test "fresh install accepts sha256-prefixed conventional checksum text" {
  printf 'approved bytes\n' >artifact
  digest=$(bashdeps_sha256_of artifact)
  printf 'sha256:%s  upstream-name.bin\n' "${digest^^}" >checksum
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  map_digest_url_request 'https://example.test/checksum' "$BASHDEPS_TEST_PROJECT/checksum"

  run run_bashdeps install \
    'id=tool@1' \
    'url=https://example.test/tool' \
    'dest=vendor/tool' \
    "digest=sha256:$digest" \
    'digest_url=https://example.test/checksum'

  [ "$status" -eq 0 ]
  [ "$(cat vendor/tool)" = 'approved bytes' ]
}

@test "committed digest mismatch fails before digest_url is requested" {
  printf 'unapproved bytes\n' >artifact
  printf 'whatever\n' >checksum
  approved=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  map_digest_url_request 'https://example.test/tool.sha256' "$BASHDEPS_TEST_PROJECT/checksum"
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/tool.sha256\n' \
    "$approved" >dependencies.txt

  run run_bashdeps sync

  [ "$status" -eq 5 ]
  [ ! -e vendor/tool ]
  [ "$(cat "$BASHDEPS_CURL_LOG")" = 'https://example.test/tool' ]
}

@test "upstream digest mismatch fails closed without publication" {
  printf 'approved bytes\n' >artifact
  digest=$(bashdeps_sha256_of artifact)
  printf '%064d\n' 0 >checksum
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  map_digest_url_request 'https://example.test/tool.sha256' "$BASHDEPS_TEST_PROJECT/checksum"
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/tool.sha256\n' \
    "$digest" >dependencies.txt

  run run_bashdeps sync

  [ "$status" -eq 5 ]
  [ ! -e vendor/tool ]
  [[ "$output" == *'does not match upstream checksum'* ]]
}

@test "checksum transport failure maps to status 4 and preserves destination state" {
  printf 'approved bytes\n' >artifact
  digest=$(bashdeps_sha256_of artifact)
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  map_digest_url_request 'https://example.test/tool.sha256' '' 22
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/tool.sha256\n' \
    "$digest" >dependencies.txt

  run run_bashdeps sync

  [ "$status" -eq 4 ]
  [ ! -e vendor/tool ]
  [[ "$output" == *'network acquisition failed: https://example.test/tool.sha256'* ]]
}

@test "malformed multiple-entry and unsupported checksum syntax fail with status 5" {
  printf 'approved bytes\n' >artifact
  digest=$(bashdeps_sha256_of artifact)
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"

  printf 'not-a-checksum\n' >checksum
  map_digest_url_request 'https://example.test/malformed' "$BASHDEPS_TEST_PROJECT/checksum"
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/malformed\n' \
    "$digest" >dependencies.txt
  run run_bashdeps sync
  [ "$status" -eq 5 ]
  [ ! -e vendor/tool ]

  : >"$BASHDEPS_CURL_LOG"
  : >"$BASHDEPS_CURL_MAP"
  printf '%s  one\n%s  two\n' "$digest" "$digest" >checksum
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  map_digest_url_request 'https://example.test/multiple' "$BASHDEPS_TEST_PROJECT/checksum"
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/multiple\n' \
    "$digest" >dependencies.txt
  run run_bashdeps sync
  [ "$status" -eq 5 ]
  [ ! -e vendor/tool ]

  : >"$BASHDEPS_CURL_LOG"
  : >"$BASHDEPS_CURL_MAP"
  printf 'sha512:%s\n' "$digest" >checksum
  map_digest_url_request 'https://example.test/tool' "$BASHDEPS_TEST_PROJECT/artifact"
  map_digest_url_request 'https://example.test/algorithm' "$BASHDEPS_TEST_PROJECT/checksum"
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/algorithm\n' \
    "$digest" >dependencies.txt
  run run_bashdeps sync
  [ "$status" -eq 5 ]
  [ ! -e vendor/tool ]
}

@test "invalid and duplicate digest_url declarations fail as status 2" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=http://example.test/tool.sha256\n' \
    "$digest" >dependencies.txt

  run run_bashdeps verify
  [ "$status" -eq 2 ]
  [[ "$output" == *'non-HTTPS digest_url'* ]]
  [ ! -s "$BASHDEPS_CURL_LOG" ]

  printf 'id=tool@1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s digest_url=https://example.test/a digest_url=https://example.test/b\n' \
    "$digest" >dependencies.txt
  run run_bashdeps verify
  [ "$status" -eq 2 ]
  [[ "$output" == *'duplicate digest_url field'* ]]
}

@test "a later upstream mismatch prevents publication of earlier staged candidates" {
  printf 'first bytes\n' >first
  printf 'second bytes\n' >second
  first_digest=$(bashdeps_sha256_of first)
  second_digest=$(bashdeps_sha256_of second)
  printf '%s\n' "$first_digest" >first.sum
  printf '%064d\n' 0 >second.sum

  map_digest_url_request 'https://example.test/first' "$BASHDEPS_TEST_PROJECT/first"
  map_digest_url_request 'https://example.test/first.sha256' "$BASHDEPS_TEST_PROJECT/first.sum"
  map_digest_url_request 'https://example.test/second' "$BASHDEPS_TEST_PROJECT/second"
  map_digest_url_request 'https://example.test/second.sha256' "$BASHDEPS_TEST_PROJECT/second.sum"
  {
    printf 'id=first@1 url=https://example.test/first dest=vendor/first digest=sha256:%s digest_url=https://example.test/first.sha256\n' "$first_digest"
    printf 'id=second@1 url=https://example.test/second dest=vendor/second digest=sha256:%s digest_url=https://example.test/second.sha256\n' "$second_digest"
  } >dependencies.txt

  run run_bashdeps sync

  [ "$status" -eq 5 ]
  [ ! -e vendor/first ]
  [ ! -e vendor/second ]
}
