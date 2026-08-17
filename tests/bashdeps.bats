#!/usr/bin/env bats

load test_helper

setup() {
  bashdeps_test_setup
}

@test "help and version expose the public CLI" {
  run bash "$BASHDEPS_TEST_EXECUTABLE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"bashdeps install"* ]]
  [[ "$output" == *"bashdeps sync [MANIFEST]"* ]]

  run bash "$BASHDEPS_TEST_EXECUTABLE" --version
  [ "$status" -eq 0 ]
  [[ "$output" == bashdeps\ * ]]
  [[ "$output" == *$'\n'build_date=* ]]
  [[ "$output" == *$'\n'commit=* ]]
}

@test "sync parses named fields and preserves equals signs in URL values" {
  printf 'approved bytes\n' >payload
  digest=$(bashdeps_sha256_of payload)
  bashdeps_make_mock_curl

  printf 'dest=vendor/item.dat digest=sha256:%s url=https://example.test/download?first=1&second=2 id=item@1\n' "$digest" >dependencies.txt

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" MOCK_SOURCE="$BASHDEPS_TEST_PROJECT/payload" \
    bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 0 ]
  [ "$(cat vendor/item.dat)" = 'approved bytes' ]
}

@test "verify is network-free and accepts already-correct bytes" {
  mkdir -p vendor
  printf 'approved bytes\n' >vendor/item.dat
  digest=$(bashdeps_sha256_of vendor/item.dat)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item.dat digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_mock_curl

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" MOCK_CURL_MARKER="$BASHDEPS_TEST_PROJECT/curl-called" \
    bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 0 ]
  [ ! -e "$BASHDEPS_TEST_PROJECT/curl-called" ]
}

@test "verify returns 1 for missing declared bytes" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 url=https://example.test/item dest=vendor/item.dat digest=sha256:%s\n' "$digest" >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 1 ]
  [ ! -e vendor ]
}

@test "unknown manifest fields fail closed" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 url=https://example.test/item dest=vendor/item.dat digest=sha256:%s mode=0755\n' "$digest" >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown dependency field: mode"* ]]
}

@test "duplicate identities are rejected before acquisition" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf '%s\n' \
    "id=item@1 url=https://example.test/a dest=vendor/a digest=sha256:$digest" \
    "id=item@1 url=https://example.test/b dest=vendor/b digest=sha256:$digest" >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 2 ]
  [ ! -e vendor ]
}

@test "sync preflights every candidate before publishing any replacement" {
  printf 'approved bytes\n' >good
  printf 'wrong bytes\n' >bad
  good_digest=$(bashdeps_sha256_of good)
  bashdeps_make_mock_curl

  printf '%s\n' \
    "id=one@1 url=https://example.test/good dest=vendor/one digest=sha256:$good_digest" \
    "id=two@1 url=https://example.test/bad dest=vendor/two digest=sha256:$good_digest" >dependencies.txt

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" \
    MOCK_GOOD_SOURCE="$BASHDEPS_TEST_PROJECT/good" MOCK_BAD_SOURCE="$BASHDEPS_TEST_PROJECT/bad" \
    bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 5 ]
  [ ! -e vendor/one ]
  [ ! -e vendor/two ]
}

@test "symlinked destination parents fail closed" {
  mkdir outside
  ln -s "$BASHDEPS_TEST_PROJECT/outside" vendor
  printf 'approved bytes\n' >payload
  digest=$(bashdeps_sha256_of payload)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_mock_curl

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" MOCK_SOURCE="$BASHDEPS_TEST_PROJECT/payload" \
    bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 6 ]
  [ ! -e outside/item ]
}

@test "wget is used when curl is unavailable" {
  printf 'approved bytes\n' >payload
  digest=$(bashdeps_sha256_of payload)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_isolated_path
  bashdeps_make_mock_wget

  run env PATH="$BASHDEPS_TEST_PROJECT/isolated-bin" MOCK_SOURCE="$BASHDEPS_TEST_PROJECT/payload" \
    /bin/bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 0 ]
  [ "$(cat vendor/item)" = 'approved bytes' ]
}

@test "a satisfied sync does not require a downloader" {
  mkdir -p vendor
  printf 'approved bytes\n' >vendor/item
  digest=$(bashdeps_sha256_of vendor/item)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_isolated_path

  run env PATH="$BASHDEPS_TEST_PROJECT/isolated-bin" /bin/bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 0 ]
}

@test "missing downloader is status 3 only when acquisition is required" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_isolated_path

  run env PATH="$BASHDEPS_TEST_PROJECT/isolated-bin" /bin/bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 3 ]
}

@test "install uses the same named-field declaration grammar" {
  printf 'approved bytes\n' >payload
  digest=$(bashdeps_sha256_of payload)
  bashdeps_make_mock_curl

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" MOCK_SOURCE="$BASHDEPS_TEST_PROJECT/payload" \
    bash "$BASHDEPS_TEST_EXECUTABLE" install \
      "url=https://example.test/item?x=1&y=2" "digest=sha256:$digest" "id=item@1" "dest=assets/item.dat"
  [ "$status" -eq 0 ]
  [ "$(cat assets/item.dat)" = 'approved bytes' ]
}
