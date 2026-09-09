#!/usr/bin/env bats

load manifest-manager-test-helper

setup() {
  manifest_manager_test_setup
  printf 'artifact bytes\n' >artifact
  digest=$(manifest_manager_sha256_of artifact)
}

@test "add accepts arbitrary field order and appends canonical field order" {
  : >dependencies.txt

  run manifest_manager_run add \
    "dest=vendor/tool" \
    "digest=sha256:$digest" \
    'id=acme/tool@v1' \
    'url=https://example.test/tool?first=1&second=2'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  expected="id=acme/tool@v1 url=https://example.test/tool?first=1&second=2 dest=vendor/tool digest=sha256:$digest"
  [ "$(cat dependencies.txt)" = "$expected" ]
  [ "$(tail -c 1 dependencies.txt | od -An -tu1 | tr -d ' ')" -eq 10 ]
}

@test "add preserves all existing bytes and appends after trailing comments and blanks" {
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >dependencies.txt
  printf '# retained trailing comment\n\n' >>dependencies.txt
  cp dependencies.txt before
  cp before expected
  printf 'id=acme/two@v2 url=https://example.test/two dest=vendor/two digest=sha256:%s\n' \
    "$digest" >>expected

  run manifest_manager_run add \
    id=acme/two@v2 \
    url=https://example.test/two \
    dest=vendor/two \
    "digest=sha256:$digest"

  [ "$status" -eq 0 ]
  cmp -s expected dependencies.txt
}

@test "add supplies one LF separator when a nonempty manifest lacks a final newline" {
  printf 'id=acme/one@v1 url=https://example.test/one dest=vendor/one digest=sha256:%s' \
    "$digest" >dependencies.txt
  cp dependencies.txt before
  cp before expected
  printf '\nid=acme/two@v2 url=https://example.test/two dest=vendor/two digest=sha256:%s\n' \
    "$digest" >>expected

  run manifest_manager_run add \
    id=acme/two@v2 \
    url=https://example.test/two \
    dest=vendor/two \
    "digest=sha256:$digest"

  [ "$status" -eq 0 ]
  cmp -s expected dependencies.txt
}

@test "add reuses CRLF when it is the last observed line ending" {
  printf '# heading\r\n' >dependencies.txt
  printf 'id=acme/one@v1 url=https://example.test/one dest=vendor/one digest=sha256:%s\r\n' \
    "$digest" >>dependencies.txt
  cp dependencies.txt expected
  printf 'id=acme/two@v2 url=https://example.test/two dest=vendor/two digest=sha256:%s\r\n' \
    "$digest" >>expected

  run manifest_manager_run add \
    id=acme/two@v2 \
    url=https://example.test/two \
    dest=vendor/two \
    "digest=sha256:$digest"

  [ "$status" -eq 0 ]
  cmp -s expected dependencies.txt
}

@test "add reuses prior CRLF for separator when final record has no newline" {
  printf '# heading\r\n' >dependencies.txt
  printf 'id=acme/one@v1 url=https://example.test/one dest=vendor/one digest=sha256:%s' \
    "$digest" >>dependencies.txt
  cp dependencies.txt expected
  printf '\r\nid=acme/two@v2 url=https://example.test/two dest=vendor/two digest=sha256:%s\r\n' \
    "$digest" >>expected

  run manifest_manager_run add \
    id=acme/two@v2 \
    url=https://example.test/two \
    dest=vendor/two \
    "digest=sha256:$digest"

  [ "$status" -eq 0 ]
  cmp -s expected dependencies.txt
}

@test "add rejects duplicate identity and destination without changing source" {
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run add \
    id=acme/one@v1 \
    url=https://example.test/other \
    dest=vendor/other \
    "digest=sha256:$digest"
  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt

  run manifest_manager_run add \
    id=acme/two@v2 \
    url=https://example.test/two \
    dest=vendor/one \
    "digest=sha256:$digest"
  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt
}

@test "add rejects missing duplicate unknown and invalid fields" {
  : >dependencies.txt

  run manifest_manager_run add \
    id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool
  [ "$status" -eq 2 ]

  run manifest_manager_run add \
    id=acme/tool@v1 id=acme/other@v1 \
    url=https://example.test/tool dest=vendor/tool "digest=sha256:$digest"
  [ "$status" -eq 2 ]

  run manifest_manager_run add \
    id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool \
    "digest=sha256:$digest" mode=0644
  [ "$status" -eq 2 ]

  run manifest_manager_run add \
    'id=acme/tool bad@v1' url=https://example.test/tool dest=vendor/tool \
    "digest=sha256:$digest"
  [ "$status" -eq 2 ]

  run manifest_manager_run add \
    id=acme/tool@v1 url=http://example.test/tool dest=vendor/tool \
    "digest=sha256:$digest"
  [ "$status" -eq 2 ]

  run manifest_manager_run add \
    id=acme/tool@v1 url=https://example.test/tool dest=../tool \
    "digest=sha256:$digest"
  [ "$status" -eq 2 ]

  run manifest_manager_run add \
    id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool \
    digest=sha256:ABCDEF
  [ "$status" -eq 2 ]

  [ ! -s dependencies.txt ]
}

@test "add rejects an invalid existing manifest without mutation" {
  printf '%s\n' 'id=broken url=https://example.test/broken dest=vendor/broken' \
    >dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run add \
    id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool \
    "digest=sha256:$digest"

  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt
}

@test "add does not implicitly create a missing manifest" {
  rm -f dependencies.txt

  run manifest_manager_run add \
    id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool \
    "digest=sha256:$digest"

  [ "$status" -eq 6 ]
  [ ! -e dependencies.txt ]
}

@test "add accepts an alternate manifest filename" {
  : >build-dependencies.txt

  run manifest_manager_run add -f build-dependencies.txt \
    id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool \
    "digest=sha256:$digest"

  [ "$status" -eq 0 ]
  [ ! -e dependencies.txt ]
  grep -F 'id=acme/tool@v1' build-dependencies.txt
}

@test "add stream success emits only the complete candidate" {
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >input

  run bash -c \
    'cat input | PATH="$1:$PATH" MANIFEST_MANAGER_CURL_MAP="$2" MANIFEST_MANAGER_CURL_LOG="$3" bash "$4" add -f - id=acme/two@v2 url=https://example.test/two dest=vendor/two "digest=sha256:$5"' \
    _ "$PWD/mock-bin" "$MANIFEST_MANAGER_CURL_MAP" "$MANIFEST_MANAGER_CURL_LOG" \
    "$MANIFEST_MANAGER_TEST_EXECUTABLE" "$digest"

  [ "$status" -eq 0 ]
  [[ "$output" == *'id=acme/one@v1'* ]]
  [[ "$output" == *'id=acme/two@v2'* ]]
  [[ "$output" != *'manifest-manager.bash:'* ]]
}

@test "add stream failure reproduces captured original bytes" {
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >input

  run bash -c \
    'cat input | bash "$1" add -f - id=acme/one@v1 url=https://example.test/two dest=vendor/two "digest=sha256:$2" 2>stream.err' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE" "$digest"

  [ "$status" -eq 2 ]
  [ "$output" = "$(cat input)" ]
  [ -s stream.err ]
}

@test "add stream CLI failure also reproduces captured original bytes" {
  printf '%s\n' '# retained input' >input

  run bash -c \
    'cat input | bash "$1" add -f - id=only-one-field 2>stream.err' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 2 ]
  [ "$output" = "$(cat input)" ]
  [ -s stream.err ]
}

@test "add help is command specific and does not consume stream input" {
  printf '%s\n' 'sentinel input' >input

  run bash -c 'cat input | bash "$1" add -f - --help' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 0 ]
  [[ "$output" == *'manifest-manager.bash add [OPTIONS]'* ]]
  [[ "$output" == *'Exactly one each of id=, url=, dest=, and digest='* ]]
  [[ "$output" != *'sentinel input'* ]]
}

@test "add performs no network access or digest calculation" {
  : >dependencies.txt
  cat >mock-bin/sha256sum <<'MOCK'
#!/usr/bin/env bash
exit 91
MOCK
  cat >mock-bin/shasum <<'MOCK'
#!/usr/bin/env bash
exit 92
MOCK
  chmod 0755 mock-bin/sha256sum mock-bin/shasum

  run manifest_manager_run add \
    id=acme/tool@v1 url=https://example.test/tool dest=vendor/tool \
    "digest=sha256:$digest"

  [ "$status" -eq 0 ]
  [ ! -s "$MANIFEST_MANAGER_CURL_LOG" ]
}
