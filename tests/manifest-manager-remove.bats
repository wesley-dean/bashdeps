#!/usr/bin/env bats

load manifest-manager-test-helper

setup() {
  manifest_manager_test_setup
  printf 'artifact bytes\n' >artifact
  digest=$(manifest_manager_sha256_of artifact)
}

@test "remove deletes one exact record and preserves every surrounding chunk" {
  printf '# before\n\n' >dependencies.txt
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >>dependencies.txt
  printf '# between\n\n' >>dependencies.txt
  manifest_manager_record acme/two v2 https://example.test/two \
    vendor/two "$digest" >>dependencies.txt
  printf '\n# after\n' >>dependencies.txt

  printf '# before\n\n# between\n\n' >expected
  manifest_manager_record acme/two v2 https://example.test/two \
    vendor/two "$digest" >>expected
  printf '\n# after\n' >>expected

  run manifest_manager_run remove acme/one@v1

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp -s expected dependencies.txt
}

@test "remove deletes every physical line of one continued record only" {
  printf '# comment remains\r\n' >dependencies.txt
  printf 'id=acme/one@v1 \\\r\n' >>dependencies.txt
  printf '  url=https://example.test/one \\\r\n' >>dependencies.txt
  printf '  dest=vendor/one \\\r\n' >>dependencies.txt
  printf '  digest=sha256:%s\r\n' "$digest" >>dependencies.txt
  printf '\r\n# following comment remains\r\n' >>dependencies.txt
  manifest_manager_record acme/two v2 https://example.test/two \
    vendor/two "$digest" >>dependencies.txt

  printf '# comment remains\r\n\r\n# following comment remains\r\n' >expected
  manifest_manager_record acme/two v2 https://example.test/two \
    vendor/two "$digest" >>expected

  run manifest_manager_run remove acme/one@v1

  [ "$status" -eq 0 ]
  cmp -s expected dependencies.txt
}

@test "remove uses the complete opaque identity rather than a package prefix" {
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run remove acme/tool

  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt

  run manifest_manager_run remove other.example/tool@v1

  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt
}

@test "remove accepts opaque identities including a leading dash after option terminator" {
  printf 'id=-tool@v1 url=https://example.test/tool dest=vendor/tool digest=sha256:%s\n' \
    "$digest" >dependencies.txt

  run manifest_manager_run remove -- -tool@v1

  [ "$status" -eq 0 ]
  [ ! -s dependencies.txt ]
}

@test "remove rejects duplicate identities as invalid manifest state" {
  manifest_manager_record acme/tool v1 https://example.test/one \
    vendor/one "$digest" >dependencies.txt
  manifest_manager_record acme/tool v1 https://example.test/two \
    vendor/two "$digest" >>dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run remove acme/tool@v1

  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt
}

@test "remove can leave an intentionally empty manifest" {
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >dependencies.txt

  run manifest_manager_run remove acme/tool@v1

  [ "$status" -eq 0 ]
  [ ! -s dependencies.txt ]
}

@test "remove preserves final newline state of all remaining chunks" {
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >dependencies.txt
  cp dependencies.txt expected
  printf 'id=acme/two@v2 url=https://example.test/two dest=vendor/two digest=sha256:%s' \
    "$digest" >>dependencies.txt

  run manifest_manager_run remove acme/two@v2

  [ "$status" -eq 0 ]
  cmp -s expected dependencies.txt

  printf 'id=acme/one@v1 url=https://example.test/one dest=vendor/one digest=sha256:%s\n' \
    "$digest" >dependencies.txt
  printf 'id=acme/two@v2 url=https://example.test/two dest=vendor/two digest=sha256:%s' \
    "$digest" >>dependencies.txt
  printf 'id=acme/two@v2 url=https://example.test/two dest=vendor/two digest=sha256:%s' \
    "$digest" >expected-last

  run manifest_manager_run remove acme/one@v1

  [ "$status" -eq 0 ]
  cmp -s expected-last dependencies.txt
}

@test "remove does not claim ownership of adjacent comments or blank lines" {
  printf '# explanation for humans\n' >dependencies.txt
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >>dependencies.txt
  printf '\n# trailing explanation\n' >>dependencies.txt
  printf '# explanation for humans\n\n# trailing explanation\n' >expected

  run manifest_manager_run remove acme/tool@v1

  [ "$status" -eq 0 ]
  cmp -s expected dependencies.txt
}

@test "remove rejects malformed existing manifest without mutation" {
  printf '%s\n' 'id=broken url=https://example.test/broken dest=vendor/broken' \
    >dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run remove broken

  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt
}

@test "remove does not implicitly create a missing manifest" {
  rm -f dependencies.txt

  run manifest_manager_run remove acme/tool@v1

  [ "$status" -eq 6 ]
  [ ! -e dependencies.txt ]
}

@test "remove accepts an alternate manifest filename" {
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >dependencies-docs.txt

  run manifest_manager_run remove -f dependencies-docs.txt acme/tool@v1

  [ "$status" -eq 0 ]
  [ ! -s dependencies-docs.txt ]
  [ ! -e dependencies.txt ]
}

@test "remove stream success emits only the complete candidate" {
  printf '# retained\n' >input
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >>input
  printf '# middle\n' >>input
  manifest_manager_record acme/two v2 https://example.test/two \
    vendor/two "$digest" >>input

  printf '# retained\n# middle\n' >expected
  manifest_manager_record acme/two v2 https://example.test/two \
    vendor/two "$digest" >>expected

  run bash -c \
    'bash "$1" remove -f - acme/one@v1 <input >output 2>stream.err; status=$?; cmp -s expected output; cmp_status=$?; cat output; ((cmp_status == 0)) || exit 99; exit "$status"' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 0 ]
  [ "$output" = "$(cat expected)" ]
  [ ! -s stream.err ]
}

@test "remove stream selection failure reproduces captured original bytes" {
  manifest_manager_record acme/one v1 https://example.test/one \
    vendor/one "$digest" >input

  run bash -c \
    'bash "$1" remove -f - acme/missing@v1 <input >output 2>stream.err; status=$?; cmp -s input output; cmp_status=$?; cat output; ((cmp_status == 0)) || exit 99; exit "$status"' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 2 ]
  [ "$output" = "$(cat input)" ]
  [ -s stream.err ]
}

@test "remove stream CLI failure reproduces captured original bytes" {
  printf '%s\n' '# retained input' >input

  run bash -c \
    'bash "$1" remove -f - one two <input >output 2>stream.err; status=$?; cmp -s input output; cmp_status=$?; cat output; ((cmp_status == 0)) || exit 99; exit "$status"' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 2 ]
  [ "$output" = "$(cat input)" ]
  [ -s stream.err ]
}

@test "remove help is command specific and does not consume stream input" {
  printf '%s\n' 'sentinel input' >input

  run bash -c 'cat input | bash "$1" remove -f - --help' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 0 ]
  [[ "$output" == *'manifest-manager.bash remove [OPTIONS] ID'* ]]
  [[ "$output" == *'complete logical id= value'* ]]
  [[ "$output" != *'sentinel input'* ]]
}

@test "remove rejects invalid CLI forms" {
  : >dependencies.txt

  run manifest_manager_run remove
  [ "$status" -eq 2 ]

  run manifest_manager_run remove one two
  [ "$status" -eq 2 ]

  run manifest_manager_run remove --unknown acme/tool@v1
  [ "$status" -eq 2 ]

  run manifest_manager_run remove -f one -f two acme/tool@v1
  [ "$status" -eq 2 ]
}

@test "remove performs no network access or digest calculation" {
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >dependencies.txt
  cat >mock-bin/sha256sum <<'MOCK'
#!/usr/bin/env bash
exit 91
MOCK
  cat >mock-bin/shasum <<'MOCK'
#!/usr/bin/env bash
exit 92
MOCK
  chmod 0755 mock-bin/sha256sum mock-bin/shasum

  run manifest_manager_run remove acme/tool@v1

  [ "$status" -eq 0 ]
  [ ! -s "$MANIFEST_MANAGER_CURL_LOG" ]
  [ ! -s dependencies.txt ]
}
