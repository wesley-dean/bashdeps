#!/usr/bin/env bats

load test_helper

setup() {
  bashdeps_test_setup
}

@test "wget without required timeout and retry controls is rejected" {
  digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  printf 'id=item@1 url=https://example.test/item dest=vendor/item digest=sha256:%s\n' "$digest" >dependencies.txt
  bashdeps_make_isolated_path
  bashdeps_make_incapable_mock_wget

  run env PATH="$BASHDEPS_TEST_PROJECT/isolated-bin" /bin/bash "$BASHDEPS_TEST_EXECUTABLE" sync
  [ "$status" -eq 3 ]
  [[ "$output" == *"no supported HTTPS downloader is available"* ]]
  [ ! -e vendor/item ]
}
