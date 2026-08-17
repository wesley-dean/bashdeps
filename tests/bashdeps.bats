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

@test "blank lines comments and an empty manifest are valid" {
  printf '%s\n' '' '   ' '# comment' $'\t# indented comment' >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 0 ]

  : >dependencies.txt
  run bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 0 ]
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

@test "verify ignores file mode when bytes are correct" {
  mkdir -p vendor
  printf 'approved bytes\n' >vendor/item.dat
  chmod 0700 vendor/item.dat
  digest=$(bashdeps_sha256_of vendor/item.dat)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item.dat digest=sha256:%s\n' "$digest" >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' vendor/item.dat)" = '700' ]
}

@test "unknown manifest fields fail closed" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 url=https://example.test/item dest=vendor/item.dat digest=sha256:%s mode=0755\n' "$digest" >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown dependency field: mode"* ]]
}

@test "duplicate fields and missing required fields are rejected" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 id=item@2 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate id field"* ]]

  printf 'id=item@1 url=https://example.test/item dest=vendor/item\n' >dependencies.txt
  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing digest"* ]]
}

@test "invalid URL destination and digest declarations are rejected" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 url=http://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-HTTPS url"* ]]

  printf 'id=item@1 url=https://example.test/item dest=../outside digest=sha256:%s\n' "$digest" >dependencies.txt
  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid destination"* ]]

  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:ABC\n' >dependencies.txt
  run bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid digest"* ]]
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

@test "duplicate destinations are rejected before acquisition" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf '%s\n' \
    "id=one@1 url=https://example.test/a dest=vendor/shared digest=sha256:$digest" \
    "id=two@1 url=https://example.test/b dest=vendor/shared digest=sha256:$digest" >dependencies.txt

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

@test "failed acquisition preserves existing stale bytes" {
  mkdir -p vendor
  printf 'stale bytes\n' >vendor/item
  printf 'approved bytes\n' >approved
  digest=$(bashdeps_sha256_of approved)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_mock_curl

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" MOCK_SOURCE="$BASHDEPS_TEST_PROJECT/does-not-exist" \
    bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 4 ]
  [ "$(cat vendor/item)" = 'stale bytes' ]
}

@test "sync preserves undeclared files" {
  mkdir -p vendor
  printf 'keep me\n' >vendor/extra
  printf 'approved bytes\n' >payload
  digest=$(bashdeps_sha256_of payload)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_mock_curl

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" MOCK_SOURCE="$BASHDEPS_TEST_PROJECT/payload" \
    bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 0 ]
  [ "$(cat vendor/extra)" = 'keep me' ]
}

@test "newly published files use mode 0644" {
  printf 'approved bytes\n' >payload
  digest=$(bashdeps_sha256_of payload)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_mock_curl

  run env PATH="$BASHDEPS_TEST_PROJECT/mock-bin:$PATH" MOCK_SOURCE="$BASHDEPS_TEST_PROJECT/payload" \
    bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' vendor/item)" = '644' ]
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

@test "symlinked final destinations fail closed" {
  mkdir -p vendor outside
  printf 'outside bytes\n' >outside/item
  ln -s "$BASHDEPS_TEST_PROJECT/outside/item" vendor/item
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt

  run bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 6 ]
  [ "$(cat outside/item)" = 'outside bytes' ]
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

@test "shasum is used when sha256sum is unavailable" {
  mkdir -p vendor
  printf 'approved bytes\n' >vendor/item
  digest=$(bashdeps_sha256_of vendor/item)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_mock_shasum_path

  run env PATH="$BASHDEPS_TEST_PROJECT/isolated-bin" /bin/bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 0 ]
}

@test "missing hash backend is status 3 when hashing is required" {
  mkdir -p vendor
  printf 'approved bytes\n' >vendor/item
  digest=$(bashdeps_sha256_of vendor/item)
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_base_isolated_path

  run env PATH="$BASHDEPS_TEST_PROJECT/isolated-bin" /bin/bash "$BASHDEPS_TEST_EXECUTABLE" verify
  [ "$status" -eq 3 ]
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
