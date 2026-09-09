#!/usr/bin/env bats

load manifest-manager-test-helper

setup() {
  manifest_manager_test_setup
  printf 'old bytes\n' >old
  printf 'new filter bytes\n' >new-filter
  printf 'asset bytes\n' >asset
  printf 'one bytes\n' >one
  printf 'two bytes\n' >two
}

@test "help and version expose the manager public CLI" {
  run manifest_manager_run --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"manifest-manager.bash update"* ]]
  [[ "$output" == *"Failure after capture writes the complete"* ]]

  run manifest_manager_run --version
  [ "$status" -eq 0 ]
  [[ "$output" == manifest-manager.bash\ * ]]
  [[ "$output" == *$'\n'build_date=* ]]
  [[ "$output" == *$'\n'commit=* ]]
}

@test "explicit update changes only id url and digest values" {
  old_digest=$(manifest_manager_sha256_of old)
  new_digest=$(manifest_manager_sha256_of new-filter)
  manifest_manager_record \
    wesley-dean/bash-doxygen 0.0.6 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk \
    vendor/doxygen-bash.awk "$old_digest" >dependencies.txt
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run manifest_manager_run update wesley-dean/bash-doxygen v0.0.14

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -F 'id=wesley-dean/bash-doxygen@v0.0.14' dependencies.txt
  grep -F 'url=https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk' dependencies.txt
  grep -F "digest=sha256:$new_digest" dependencies.txt
  grep -F 'dest=vendor/doxygen-bash.awk' dependencies.txt
}

@test "omitted version follows GitHub latest-release redirect" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record \
    wesley-dean/bash-doxygen 0.0.6 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk \
    vendor/doxygen-bash.awk "$old_digest" >dependencies.txt
  manifest_manager_map \
    https://github.com/wesley-dean/bash-doxygen/releases/latest \
    https://github.com/wesley-dean/bash-doxygen/releases/tag/v0.0.14
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run manifest_manager_run update wesley-dean/bash-doxygen

  [ "$status" -eq 0 ]
  grep -F 'id=wesley-dean/bash-doxygen@v0.0.14' dependencies.txt
  grep -F 'https://github.com/wesley-dean/bash-doxygen/releases/latest' \
    "$MANIFEST_MANAGER_CURL_LOG"
}

@test "explicit literal latest does not perform release discovery" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record \
    wesley-dean/bash-doxygen 0.0.6 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk \
    vendor/doxygen-bash.awk "$old_digest" >dependencies.txt
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/latest/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run manifest_manager_run update wesley-dean/bash-doxygen latest

  [ "$status" -eq 0 ]
  grep -F 'id=wesley-dean/bash-doxygen@latest' dependencies.txt
  ! grep -F '/releases/latest' "$MANIFEST_MANAGER_CURL_LOG"
}

@test "release download URLs retain asset paths" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool.bash \
    vendor/tool.bash "$old_digest" >dependencies.txt
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.bash \
    '' "$PWD/asset"

  run manifest_manager_run update acme/tool v2

  [ "$status" -eq 0 ]
  grep -F 'id=acme/tool@v2' dependencies.txt
  grep -F 'url=https://github.com/acme/tool/releases/download/v2/tool.bash' \
    dependencies.txt
}

@test "latest release path decoding preserves literal plus" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record acme/meta v0 \
    https://raw.githubusercontent.com/acme/meta/v0/tool \
    vendor/meta "$old_digest" >dependencies.txt
  manifest_manager_map \
    https://github.com/acme/meta/releases/latest \
    https://github.com/acme/meta/releases/tag/v1.0%2Bmeta
  manifest_manager_map \
    https://raw.githubusercontent.com/acme/meta/v1.0+meta/tool \
    '' "$PWD/asset"

  run manifest_manager_run update acme/meta

  [ "$status" -eq 0 ]
  grep -F 'id=acme/meta@v1.0+meta' dependencies.txt
}

@test "stream success emits only the complete candidate" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record \
    wesley-dean/bash-doxygen 0.0.6 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk \
    vendor/doxygen-bash.awk "$old_digest" >input
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run bash -c \
    'cat input | PATH="$1:$PATH" MANIFEST_MANAGER_CURL_MAP="$2" MANIFEST_MANAGER_CURL_LOG="$3" bash "$4" update -f - wesley-dean/bash-doxygen v0.0.14' \
    _ "$PWD/mock-bin" "$MANIFEST_MANAGER_CURL_MAP" "$MANIFEST_MANAGER_CURL_LOG" \
    "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 0 ]
  [[ "$output" == *'id=wesley-dean/bash-doxygen@v0.0.14'* ]]
  [[ "$output" != *'manifest-manager.bash:'* ]]
}

@test "stream operational failure reproduces original input" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record \
    wesley-dean/bash-doxygen 0.0.6 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk \
    vendor/doxygen-bash.awk "$old_digest" >input

  run bash -c 'cat input | bash "$1" update -f - no/such v1 2>stream.err' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 2 ]
  [ "$output" = "$(cat input)" ]
}

@test "stream CLI failure reproduces original input" {
  printf '%s\n' '# retained input' >input

  run bash -c 'cat input | bash "$1" update -f - --all extra 2>stream.err' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 2 ]
  [ "$output" = "$(cat input)" ]
}

@test "CRLF continuations and final-newline state survive surgical update" {
  old_digest=$(manifest_manager_sha256_of old)
  printf '# heading\r\n\r\n' >dependencies.txt
  printf '  id=wesley-dean/bash-doxygen@0.0.6 \\\r\n' >>dependencies.txt
  printf '\turl=https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk \\\r\n' >>dependencies.txt
  printf '  dest=vendor/doxygen-bash.awk \\\r\n' >>dependencies.txt
  printf '\tdigest=sha256:%s' "$old_digest" >>dependencies.txt
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run manifest_manager_run update wesley-dean/bash-doxygen v0.0.14

  [ "$status" -eq 0 ]
  [ "$(tail -c 1 dependencies.txt | od -An -tu1 | tr -d ' ')" != 10 ]
  [ "$(tr -cd '\r' <dependencies.txt | wc -c)" -eq 5 ]
  grep -F 'id=wesley-dean/bash-doxygen@v0.0.14' dependencies.txt
}

@test "exact-once substitution failure leaves file unchanged" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record \
    wesley-dean/bash-doxygen 0.0.6 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk \
    vendor/wesley-dean/bash-doxygen@0.0.6 "$old_digest" >dependencies.txt
  cp dependencies.txt before
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run manifest_manager_run update wesley-dean/bash-doxygen v0.0.14

  [ "$status" -eq 5 ]
  cmp -s before dependencies.txt
}

@test "verified same target is a successful no-op" {
  digest=$(manifest_manager_sha256_of new-filter)
  manifest_manager_record \
    wesley-dean/bash-doxygen v0.0.14 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    vendor/doxygen-bash.awk "$digest" >dependencies.txt
  cp dependencies.txt before
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run manifest_manager_run update wesley-dean/bash-doxygen v0.0.14

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp -s before dependencies.txt
}

@test "changed bytes at the same immutable URL are rejected" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record \
    wesley-dean/bash-doxygen v0.0.14 \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    vendor/doxygen-bash.awk "$old_digest" >dependencies.txt
  cp dependencies.txt before
  manifest_manager_map \
    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.14/doxygen-bash.awk \
    '' "$PWD/new-filter"

  run manifest_manager_run update wesley-dean/bash-doxygen v0.0.14

  [ "$status" -eq 5 ]
  cmp -s before dependencies.txt
}

@test "all rejects commit pins before any network access" {
  digest=$(manifest_manager_sha256_of old)
  commit=0123456789012345678901234567890123456789
  manifest_manager_record acme/pinned "$commit" \
    "https://raw.githubusercontent.com/acme/pinned/$commit/tool" \
    vendor/pinned "$digest" >dependencies.txt

  run manifest_manager_run update --all

  [ "$status" -eq 2 ]
  [ ! -s "$MANIFEST_MANAGER_CURL_LOG" ]
}

@test "all updates every supported dependency as one transaction" {
  digest=$(manifest_manager_sha256_of old)
  {
    manifest_manager_record acme/one v1 \
      https://raw.githubusercontent.com/acme/one/v1/one vendor/one "$digest"
    manifest_manager_record acme/two v1 \
      https://raw.githubusercontent.com/acme/two/v1/two vendor/two "$digest"
  } >dependencies.txt
  manifest_manager_map https://github.com/acme/one/releases/latest \
    https://github.com/acme/one/releases/tag/v2
  manifest_manager_map https://github.com/acme/two/releases/latest \
    https://github.com/acme/two/releases/tag/v3
  manifest_manager_map https://raw.githubusercontent.com/acme/one/v2/one '' "$PWD/one"
  manifest_manager_map https://raw.githubusercontent.com/acme/two/v3/two '' "$PWD/two"

  run manifest_manager_run update --all

  [ "$status" -eq 0 ]
  grep -F 'id=acme/one@v2' dependencies.txt
  grep -F 'id=acme/two@v3' dependencies.txt
}

@test "all leaves the manifest untouched when a later acquisition fails" {
  digest=$(manifest_manager_sha256_of old)
  {
    manifest_manager_record acme/one v1 \
      https://raw.githubusercontent.com/acme/one/v1/one vendor/one "$digest"
    manifest_manager_record acme/two v1 \
      https://raw.githubusercontent.com/acme/two/v1/two vendor/two "$digest"
  } >dependencies.txt
  cp dependencies.txt before
  manifest_manager_map https://github.com/acme/one/releases/latest \
    https://github.com/acme/one/releases/tag/v2
  manifest_manager_map https://github.com/acme/two/releases/latest \
    https://github.com/acme/two/releases/tag/v3
  manifest_manager_map https://raw.githubusercontent.com/acme/one/v2/one \
    '' "$PWD/one"
  manifest_manager_map https://raw.githubusercontent.com/acme/two/v3/two \
    '' '' 22

  run manifest_manager_run update --all

  [ "$status" -eq 4 ]
  cmp -s before dependencies.txt
  grep -F 'https://raw.githubusercontent.com/acme/one/v2/one' \
    "$MANIFEST_MANAGER_CURL_LOG"
  grep -F 'https://raw.githubusercontent.com/acme/two/v3/two' \
    "$MANIFEST_MANAGER_CURL_LOG"
}

@test "empty all is a network-free successful no-op" {
  : >dependencies.txt

  run manifest_manager_run update --all

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$MANIFEST_MANAGER_CURL_LOG" ]
  [ ! -s dependencies.txt ]
}

@test "unsupported URL and NUL input fail without mutation" {
  digest=$(manifest_manager_sha256_of old)
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run update acme/tool v2
  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt

  printf 'id=acme/tool@v1\0 url=https://github.com/acme/tool/releases/download/v1/tool.bash dest=vendor/tool digest=sha256:%s\n' \
    "$digest" >dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run update acme/tool v2
  [ "$status" -eq 2 ]
  cmp -s before dependencies.txt
}

@test "downloaded candidate artifact is never executed" {
  old_digest=$(manifest_manager_sha256_of old)
  cat >candidate <<MOCK
#!/usr/bin/env bash
: >"$PWD/executed"
MOCK
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool.bash \
    vendor/tool.bash "$old_digest" >dependencies.txt
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v9/tool.bash '' "$PWD/candidate"

  run manifest_manager_run update acme/tool v9

  [ "$status" -eq 0 ]
  [ ! -e executed ]
}
