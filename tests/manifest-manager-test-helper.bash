#!/usr/bin/env bash

manifest_manager_test_setup() {
  local raw_executable
  raw_executable=${MANIFEST_MANAGER_EXECUTABLE:-$BATS_TEST_DIRNAME/../src/manifest-manager.bash}
  MANIFEST_MANAGER_TEST_EXECUTABLE="$(cd "$(dirname "$raw_executable")" && pwd -P)/$(basename "$raw_executable")"
  export MANIFEST_MANAGER_TEST_EXECUTABLE

  MANIFEST_MANAGER_TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$MANIFEST_MANAGER_TEST_PROJECT/mock-bin"
  cd "$MANIFEST_MANAGER_TEST_PROJECT" || return

  MANIFEST_MANAGER_CURL_MAP="$MANIFEST_MANAGER_TEST_PROJECT/curl-map"
  MANIFEST_MANAGER_CURL_LOG="$MANIFEST_MANAGER_TEST_PROJECT/curl-log"
  : >"$MANIFEST_MANAGER_CURL_MAP"
  : >"$MANIFEST_MANAGER_CURL_LOG"
  export MANIFEST_MANAGER_CURL_MAP MANIFEST_MANAGER_CURL_LOG

  cat >"$MANIFEST_MANAGER_TEST_PROJECT/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -u
out=''
write_out=''
url=''
while (($#)); do
  case $1 in
    --output)
      out=$2
      shift 2
      ;;
    --write-out)
      write_out=$2
      shift 2
      ;;
    --)
      shift
      url=${1:-}
      shift || :
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n $url ]] || exit 97
printf '%s\n' "$url" >>"$MANIFEST_MANAGER_CURL_LOG"
found=0
while IFS='|' read -r request effective source status; do
  [[ $request == "$url" ]] || continue
  found=1
  status=${status:-0}
  ((status == 0)) || exit "$status"
  if [[ -n $out && $out != /dev/null ]]; then
    [[ -n $source && -r $source ]] || exit 95
    cp "$source" "$out"
  fi
  if [[ -n $write_out ]]; then
    [[ -n $effective ]] || effective=$url
    printf '%s' "$effective"
  fi
  break
done <"$MANIFEST_MANAGER_CURL_MAP"
((found)) || exit 22
MOCK
  chmod 0755 "$MANIFEST_MANAGER_TEST_PROJECT/mock-bin/curl"
}

manifest_manager_sha256_of() {
  local output
  output=$(sha256sum "$1")
  printf '%s\n' "${output%%[[:space:]]*}"
}

manifest_manager_record() {
  local package=$1 version=$2 url=$3 dest=$4 digest=$5
  local digest_url=${6:-}

  printf 'id=%s@%s url=%s dest=%s digest=sha256:%s' \
    "$package" "$version" "$url" "$dest" "$digest"
  if [[ -n $digest_url ]]; then
    printf ' digest_url=%s' "$digest_url"
  fi
  printf '\n'
}

manifest_manager_map() {
  local request=$1 effective=${2:-} source=${3:-} status=${4:-0}
  printf '%s|%s|%s|%s\n' "$request" "$effective" "$source" "$status" \
    >>"$MANIFEST_MANAGER_CURL_MAP"
}

manifest_manager_run() {
  env \
    PATH="$MANIFEST_MANAGER_TEST_PROJECT/mock-bin:$PATH" \
    MANIFEST_MANAGER_CURL_MAP="$MANIFEST_MANAGER_CURL_MAP" \
    MANIFEST_MANAGER_CURL_LOG="$MANIFEST_MANAGER_CURL_LOG" \
    bash "$MANIFEST_MANAGER_TEST_EXECUTABLE" "$@"
}
