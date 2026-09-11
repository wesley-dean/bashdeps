#!/usr/bin/env bats

load manifest-manager-test-helper

setup() {
  manifest_manager_test_setup
  printf 'old bytes\n' >old
  printf 'new bytes\n' >new
}

@test "list accepts digest_url while four-field records remain valid" {
  old_digest=$(manifest_manager_sha256_of old)
  {
    manifest_manager_record acme/old v1 \
      https://github.com/acme/old/releases/download/v1/old \
      vendor/old "$old_digest"
    manifest_manager_record acme/new v1 \
      https://github.com/acme/new/releases/download/v1/new \
      vendor/new "$old_digest" \
      https://github.com/acme/new/releases/download/v1/new.sha256
  } >dependencies.txt

  run manifest_manager_run list

  [ "$status" -eq 0 ]
  [ "$output" = $'acme/old@v1\nacme/new@v1' ]
  [ ! -s "$MANIFEST_MANAGER_CURL_LOG" ]
}

@test "add accepts an explicit digest_url without network inference" {
  : >dependencies.txt
  digest=$(manifest_manager_sha256_of old)

  run manifest_manager_run add \
    id=acme/tool@v1 \
    url=https://github.com/acme/tool/releases/download/v1/tool \
    dest=vendor/tool \
    "digest=sha256:$digest" \
    digest_url=https://checks.example.test/tool-v1.sha256

  [ "$status" -eq 0 ]
  grep -Fx \
    "id=acme/tool@v1 url=https://github.com/acme/tool/releases/download/v1/tool dest=vendor/tool digest=sha256:$digest digest_url=https://checks.example.test/tool-v1.sha256" \
    dependencies.txt
  [ ! -s "$MANIFEST_MANAGER_CURL_LOG" ]
}

@test "add preserves four-field canonical output when digest_url is omitted" {
  : >dependencies.txt
  digest=$(manifest_manager_sha256_of old)

  run manifest_manager_run add \
    id=acme/tool@v1 \
    url=https://github.com/acme/tool/releases/download/v1/tool \
    dest=vendor/tool \
    "digest=sha256:$digest"

  [ "$status" -eq 0 ]
  grep -Fx \
    "id=acme/tool@v1 url=https://github.com/acme/tool/releases/download/v1/tool dest=vendor/tool digest=sha256:$digest" \
    dependencies.txt
  ! grep -F 'digest_url=' dependencies.txt
}

@test "add rejects non-HTTPS and duplicate digest_url fields" {
  : >dependencies.txt
  digest=$(manifest_manager_sha256_of old)

  run manifest_manager_run add \
    id=acme/tool@v1 \
    url=https://github.com/acme/tool/releases/download/v1/tool \
    dest=vendor/tool \
    "digest=sha256:$digest" \
    digest_url=http://example.test/tool.sha256
  [ "$status" -eq 2 ]
  [ ! -s dependencies.txt ]

  run manifest_manager_run add \
    id=acme/tool@v1 \
    url=https://github.com/acme/tool/releases/download/v1/tool \
    dest=vendor/tool \
    "digest=sha256:$digest" \
    digest_url=https://example.test/a \
    digest_url=https://example.test/b
  [ "$status" -eq 2 ]
  [ ! -s dependencies.txt ]
}

@test "update transforms and verifies an already-declared digest_url" {
  old_digest=$(manifest_manager_sha256_of old)
  new_digest=$(manifest_manager_sha256_of new)
  printf '%s  tool\n' "$new_digest" >new.sha256
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool \
    vendor/tool "$old_digest" \
    https://github.com/acme/tool/releases/download/v1/tool.sha256 \
    >dependencies.txt
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool \
    '' "$PWD/new"
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.sha256 \
    '' "$PWD/new.sha256"

  run manifest_manager_run update acme/tool v2

  [ "$status" -eq 0 ]
  grep -F 'id=acme/tool@v2' dependencies.txt
  grep -F 'url=https://github.com/acme/tool/releases/download/v2/tool' dependencies.txt
  grep -F 'digest_url=https://github.com/acme/tool/releases/download/v2/tool.sha256' dependencies.txt
  grep -F "digest=sha256:$new_digest" dependencies.txt
  grep -F 'dest=vendor/tool' dependencies.txt
  [ "$(wc -l <"$MANIFEST_MANAGER_CURL_LOG")" -eq 2 ]
}

@test "update accepts sha256-prefixed checksum text and normalizes uppercase hex" {
  old_digest=$(manifest_manager_sha256_of old)
  new_digest=$(manifest_manager_sha256_of new)
  printf 'sha256:%s *renamed-tool\n' "${new_digest^^}" >new.sha256
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool \
    vendor/tool "$old_digest" \
    https://github.com/acme/tool/releases/download/v1/tool.sha256 \
    >dependencies.txt
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool \
    '' "$PWD/new"
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.sha256 \
    '' "$PWD/new.sha256"

  run manifest_manager_run update acme/tool v2

  [ "$status" -eq 0 ]
  grep -F "digest=sha256:$new_digest" dependencies.txt
}

@test "upstream checksum mismatch fails update without changing the manifest" {
  old_digest=$(manifest_manager_sha256_of old)
  printf '%064d\n' 0 >new.sha256
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool \
    vendor/tool "$old_digest" \
    https://github.com/acme/tool/releases/download/v1/tool.sha256 \
    >dependencies.txt
  cp dependencies.txt original
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool \
    '' "$PWD/new"
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.sha256 \
    '' "$PWD/new.sha256"

  run manifest_manager_run update acme/tool v2

  [ "$status" -eq 5 ]
  cmp -s original dependencies.txt
}

@test "checksum acquisition failure maps to status 4 without changing the manifest" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool \
    vendor/tool "$old_digest" \
    https://github.com/acme/tool/releases/download/v1/tool.sha256 \
    >dependencies.txt
  cp dependencies.txt original
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool \
    '' "$PWD/new"
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.sha256 \
    '' '' 22

  run manifest_manager_run update acme/tool v2

  [ "$status" -eq 4 ]
  cmp -s original dependencies.txt
}

@test "malformed multi-entry and unsupported checksum algorithms fail as integrity errors" {
  old_digest=$(manifest_manager_sha256_of old)
  new_digest=$(manifest_manager_sha256_of new)
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool \
    vendor/tool "$old_digest" \
    https://github.com/acme/tool/releases/download/v1/tool.sha256 \
    >dependencies.txt
  cp dependencies.txt original
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool \
    '' "$PWD/new"

  printf 'not-a-checksum\n' >new.sha256
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.sha256 \
    '' "$PWD/new.sha256"
  run manifest_manager_run update acme/tool v2
  [ "$status" -eq 5 ]
  cmp -s original dependencies.txt

  : >"$MANIFEST_MANAGER_CURL_MAP"
  printf '%s  one\n%s  two\n' "$new_digest" "$new_digest" >new.sha256
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool \
    '' "$PWD/new"
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.sha256 \
    '' "$PWD/new.sha256"
  run manifest_manager_run update acme/tool v2
  [ "$status" -eq 5 ]
  cmp -s original dependencies.txt

  : >"$MANIFEST_MANAGER_CURL_MAP"
  printf 'sha512:%s\n' "$new_digest" >new.sha256
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool \
    '' "$PWD/new"
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v2/tool.sha256 \
    '' "$PWD/new.sha256"
  run manifest_manager_run update acme/tool v2
  [ "$status" -eq 5 ]
  cmp -s original dependencies.txt
}

@test "same-target update verifies digest_url and remains a no-op" {
  old_digest=$(manifest_manager_sha256_of old)
  printf '%s\n' "$old_digest" >old.sha256
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool \
    vendor/tool "$old_digest" \
    https://github.com/acme/tool/releases/download/v1/tool.sha256 \
    >dependencies.txt
  cp dependencies.txt original
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v1/tool \
    '' "$PWD/old"
  manifest_manager_map \
    https://github.com/acme/tool/releases/download/v1/tool.sha256 \
    '' "$PWD/old.sha256"

  run manifest_manager_run update acme/tool v1

  [ "$status" -eq 0 ]
  cmp -s original dependencies.txt
  grep -Fx 'https://github.com/acme/tool/releases/download/v1/tool' \
    "$MANIFEST_MANAGER_CURL_LOG"
  grep -Fx 'https://github.com/acme/tool/releases/download/v1/tool.sha256' \
    "$MANIFEST_MANAGER_CURL_LOG"
}

@test "unsupported digest_url update relationship fails before network access" {
  old_digest=$(manifest_manager_sha256_of old)
  manifest_manager_record acme/tool v1 \
    https://github.com/acme/tool/releases/download/v1/tool \
    vendor/tool "$old_digest" \
    https://checks.example.test/releases/v1/tool.sha256 \
    >dependencies.txt
  cp dependencies.txt original

  run manifest_manager_run update acme/tool v2

  [ "$status" -eq 2 ]
  cmp -s original dependencies.txt
  [ ! -s "$MANIFEST_MANAGER_CURL_LOG" ]
}

@test "a later checksum failure under update --all preserves the whole manifest" {
  one_digest=$(manifest_manager_sha256_of old)
  two_digest=$(manifest_manager_sha256_of old)
  printf 'one new\n' >one-new
  printf 'two new\n' >two-new
  one_new_digest=$(manifest_manager_sha256_of one-new)
  printf '%s\n' "$one_new_digest" >one-new.sha256
  printf '%064d\n' 0 >two-new.sha256
  {
    manifest_manager_record acme/one v1 \
      https://github.com/acme/one/releases/download/v1/one \
      vendor/one "$one_digest" \
      https://github.com/acme/one/releases/download/v1/one.sha256
    manifest_manager_record acme/two v1 \
      https://github.com/acme/two/releases/download/v1/two \
      vendor/two "$two_digest" \
      https://github.com/acme/two/releases/download/v1/two.sha256
  } >dependencies.txt
  cp dependencies.txt original
  manifest_manager_map \
    https://github.com/acme/one/releases/latest \
    https://github.com/acme/one/releases/tag/v2
  manifest_manager_map \
    https://github.com/acme/two/releases/latest \
    https://github.com/acme/two/releases/tag/v2
  manifest_manager_map \
    https://github.com/acme/one/releases/download/v2/one \
    '' "$PWD/one-new"
  manifest_manager_map \
    https://github.com/acme/one/releases/download/v2/one.sha256 \
    '' "$PWD/one-new.sha256"
  manifest_manager_map \
    https://github.com/acme/two/releases/download/v2/two \
    '' "$PWD/two-new"
  manifest_manager_map \
    https://github.com/acme/two/releases/download/v2/two.sha256 \
    '' "$PWD/two-new.sha256"

  run manifest_manager_run update --all

  [ "$status" -eq 5 ]
  cmp -s original dependencies.txt
}
