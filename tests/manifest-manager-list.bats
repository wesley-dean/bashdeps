#!/usr/bin/env bats

load manifest-manager-test-helper

setup() {
  manifest_manager_test_setup
  printf 'artifact bytes\n' >artifact
}

@test "list emits complete identities in manifest order" {
  digest=$(manifest_manager_sha256_of artifact)
  {
    manifest_manager_record acme/one v1 \
      https://raw.githubusercontent.com/acme/one/v1/one vendor/one "$digest"
    manifest_manager_record other.example/tool release-7 \
      https://example.test/tool vendor/two "$digest"
  } >dependencies.txt

  run manifest_manager_run list

  [ "$status" -eq 0 ]
  [ "$output" = $'acme/one@v1\nother.example/tool@release-7' ]
}

@test "list accepts continued records without reserializing them" {
  digest=$(manifest_manager_sha256_of artifact)
  printf '# heading\n' >dependencies.txt
  printf 'id=acme/tool@v1 \\\n' >>dependencies.txt
  printf '  url=https://example.test/tool \\\n' >>dependencies.txt
  printf '  dest=vendor/tool \\\n' >>dependencies.txt
  printf '  digest=sha256:%s\n' "$digest" >>dependencies.txt
  cp dependencies.txt before

  run manifest_manager_run list

  [ "$status" -eq 0 ]
  [ "$output" = 'acme/tool@v1' ]
  cmp -s before dependencies.txt
}

@test "list accepts an alternate manifest filename" {
  digest=$(manifest_manager_sha256_of artifact)
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >build-dependencies.txt

  run manifest_manager_run list -f build-dependencies.txt

  [ "$status" -eq 0 ]
  [ "$output" = 'acme/tool@v1' ]
}

@test "list stream mode reads manifest and emits identities only" {
  digest=$(manifest_manager_sha256_of artifact)
  manifest_manager_record acme/tool v1 https://example.test/tool \
    vendor/tool "$digest" >input

  run bash -c 'cat input | bash "$1" list -f -' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 0 ]
  [ "$output" = 'acme/tool@v1' ]
}

@test "list validates the complete manifest before emitting output" {
  digest=$(manifest_manager_sha256_of artifact)
  {
    manifest_manager_record acme/valid v1 https://example.test/valid \
      vendor/valid "$digest"
    printf '%s\n' 'id=broken url=https://example.test/broken dest=vendor/broken'
  } >dependencies.txt

  run bash -c 'bash "$1" list >list.out 2>list.err' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 2 ]
  [ ! -s list.out ]
  [ -s list.err ]
}

@test "list empty manifest is a successful empty result" {
  : >dependencies.txt

  run manifest_manager_run list

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list help is command specific and does not consume stream input" {
  printf '%s\n' 'sentinel input' >input

  run bash -c 'cat input | bash "$1" list -f - --help' \
    _ "$MANIFEST_MANAGER_TEST_EXECUTABLE"

  [ "$status" -eq 0 ]
  [[ "$output" == *'manifest-manager.bash list [OPTIONS]'* ]]
  [[ "$output" == *'one identity per line'* ]]
  [[ "$output" != *'sentinel input'* ]]
}

@test "top-level help summarizes list and update" {
  run manifest_manager_run --help

  [ "$status" -eq 0 ]
  [[ "$output" == *'update    Update one or all'* ]]
  [[ "$output" == *'list      List complete validated'* ]]
}

@test "update help remains command specific" {
  run manifest_manager_run update --help

  [ "$status" -eq 0 ]
  [[ "$output" == *'manifest-manager.bash update [OPTIONS] ID [VERSION]'* ]]
  [[ "$output" == *'Failure after capture writes the complete'* ]]
}

@test "list rejects positional and unknown option syntax" {
  run manifest_manager_run list unexpected
  [ "$status" -eq 2 ]

  run manifest_manager_run list --wat
  [ "$status" -eq 2 ]
}
