#!/usr/bin/env bash

# bashdeps: materialize exact SHA-256-pinned external artifacts.
#
# The supported public interface is the executable CLI.  All functions and
# variables below are private implementation details.

__bashdeps_version=${__bashdeps_version:-0.0.0-dev}
__bashdeps_build_date=${__bashdeps_build_date:-unknown}
__bashdeps_build_commit=${__bashdeps_build_commit:-unknown}

__bashdeps_record_id=''
__bashdeps_record_url=''
__bashdeps_record_dest=''
__bashdeps_record_digest=''

__bashdeps_ids=()
__bashdeps_urls=()
__bashdeps_dests=()
__bashdeps_digests=()
__bashdeps_stage_dir=''
__bashdeps_hash_backend=''
__bashdeps_download_backend=''

__bashdeps_usage() {
  printf '%s\n' \
    'Usage:' \
    '  bashdeps install id=IDENTITY url=HTTPS_URL dest=RELATIVE_PATH digest=sha256:HEX' \
    '  bashdeps sync [MANIFEST]' \
    '  bashdeps verify [MANIFEST]' \
    '  bashdeps help' \
    '  bashdeps version'
}

__bashdeps_diag() {
  printf 'bashdeps: %s\n' "$*" >&2
}

__bashdeps_reset_record() {
  __bashdeps_record_id=''
  __bashdeps_record_url=''
  __bashdeps_record_dest=''
  __bashdeps_record_digest=''
}

__bashdeps_validate_dest_text() {
  local dest component
  local -a components

  dest=$1
  [[ -n $dest ]] || return 1
  [[ $dest != /* ]] || return 1
  [[ $dest != */ ]] || return 1
  [[ $dest != *//* ]] || return 1

  IFS='/' read -r -a components <<<"$dest"
  for component in "${components[@]}"; do
    [[ -n $component ]] || return 1
    [[ $component != '.' && $component != '..' ]] || return 1
  done
}

__bashdeps_validate_record() {
  [[ -n $__bashdeps_record_id ]] || {
    __bashdeps_diag 'dependency declaration is missing id'
    return 2
  }
  [[ -n $__bashdeps_record_url ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id is missing url"
    return 2
  }
  [[ -n $__bashdeps_record_dest ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id is missing dest"
    return 2
  }
  [[ -n $__bashdeps_record_digest ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id is missing digest"
    return 2
  }

  [[ $__bashdeps_record_url == https://* ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id has a non-HTTPS url"
    return 2
  }

  __bashdeps_validate_dest_text "$__bashdeps_record_dest" || {
    __bashdeps_diag "dependency $__bashdeps_record_id has an invalid destination: $__bashdeps_record_dest"
    return 2
  }

  [[ $__bashdeps_record_digest =~ ^sha256:[0-9a-f]{64}$ ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id has an invalid digest"
    return 2
  }
}

__bashdeps_parse_tokens() {
  local token key value
  local seen_id=0 seen_url=0 seen_dest=0 seen_digest=0

  __bashdeps_reset_record

  for token in "$@"; do
    [[ $token == *=* ]] || {
      __bashdeps_diag "invalid dependency field: $token"
      return 2
    }
    [[ ! $token =~ [[:space:]] ]] || {
      __bashdeps_diag 'dependency fields must not contain whitespace'
      return 2
    }

    key=${token%%=*}
    value=${token#*=}
    [[ -n $key ]] || {
      __bashdeps_diag "invalid dependency field: $token"
      return 2
    }

    case $key in
      id)
        ((seen_id == 0)) || {
          __bashdeps_diag 'duplicate id field'
          return 2
        }
        seen_id=1
        __bashdeps_record_id=$value
        ;;
      url)
        ((seen_url == 0)) || {
          __bashdeps_diag 'duplicate url field'
          return 2
        }
        seen_url=1
        __bashdeps_record_url=$value
        ;;
      dest)
        ((seen_dest == 0)) || {
          __bashdeps_diag 'duplicate dest field'
          return 2
        }
        seen_dest=1
        __bashdeps_record_dest=$value
        ;;
      digest)
        ((seen_digest == 0)) || {
          __bashdeps_diag 'duplicate digest field'
          return 2
        }
        seen_digest=1
        __bashdeps_record_digest=$value
        ;;
      *)
        __bashdeps_diag "unknown dependency field: $key"
        return 2
        ;;
    esac
  done

  __bashdeps_validate_record
}

__bashdeps_array_contains() {
  local needle item
  needle=$1
  shift
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

__bashdeps_append_record() {
  if __bashdeps_array_contains "$__bashdeps_record_id" "${__bashdeps_ids[@]}"; then
    __bashdeps_diag "duplicate dependency id: $__bashdeps_record_id"
    return 2
  fi
  if __bashdeps_array_contains "$__bashdeps_record_dest" "${__bashdeps_dests[@]}"; then
    __bashdeps_diag "duplicate dependency destination: $__bashdeps_record_dest"
    return 2
  fi

  __bashdeps_ids+=("$__bashdeps_record_id")
  __bashdeps_urls+=("$__bashdeps_record_url")
  __bashdeps_dests+=("$__bashdeps_record_dest")
  __bashdeps_digests+=("${__bashdeps_record_digest#sha256:}")
}

__bashdeps_load_manifest() {
  local manifest line line_number=0
  local -a tokens

  manifest=$1
  __bashdeps_ids=()
  __bashdeps_urls=()
  __bashdeps_dests=()
  __bashdeps_digests=()

  [[ -f $manifest && -r $manifest ]] || {
    __bashdeps_diag "manifest is not a readable regular file: $manifest"
    return 2
  }
  while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    [[ $line =~ ^[[:blank:]]*$ ]] && continue
    [[ $line =~ ^[[:blank:]]*# ]] && continue

    tokens=()
    IFS=$' \t' read -r -a tokens <<<"$line"
    if ! __bashdeps_parse_tokens "${tokens[@]}"; then
      __bashdeps_diag "invalid manifest record at $manifest:$line_number"
      return 2
    fi
    __bashdeps_append_record || return $?
  done <"$manifest"
}

__bashdeps_select_hash_backend() {
  if [[ -n $__bashdeps_hash_backend ]]; then
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    __bashdeps_hash_backend=sha256sum
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    __bashdeps_hash_backend=shasum
    return 0
  fi
  __bashdeps_diag 'no supported SHA-256 implementation is available'
  return 3
}

__bashdeps_hash_file() {
  local path output digest
  path=$1

  __bashdeps_select_hash_backend || return $?
  case $__bashdeps_hash_backend in
    sha256sum)
      output=$(sha256sum "$path" 2>/dev/null) || return 3
      ;;
    shasum)
      output=$(shasum -a 256 "$path" 2>/dev/null) || return 3
      ;;
    *)
      return 3
      ;;
  esac
  digest=${output%%[[:space:]]*}
  [[ $digest =~ ^[0-9a-f]{64}$ ]] || return 3
  printf '%s\n' "$digest"
}

__bashdeps_wget_has_required_controls() {
  local help

  help=$(wget --help 2>&1) || :
  [[ $help == *'-T '* || $help == *'-T,'* ]] || return 1
  [[ $help == *'-t '* || $help == *'-t,'* ]] || return 1
}

__bashdeps_select_download_backend() {
  if [[ -n $__bashdeps_download_backend ]]; then
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    __bashdeps_download_backend=curl
    return 0
  fi
  if command -v wget >/dev/null 2>&1 && __bashdeps_wget_has_required_controls; then
    __bashdeps_download_backend=wget
    return 0
  fi
  __bashdeps_diag 'no supported HTTPS downloader is available'
  return 3
}

__bashdeps_download_once() {
  local url candidate
  url=$1
  candidate=$2

  __bashdeps_select_download_backend || return $?
  case $__bashdeps_download_backend in
    curl)
      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --proto '=https' \
        --proto-redir '=https' \
        --max-redirs 10 \
        --connect-timeout 10 \
        --max-time 120 \
        --output "$candidate" \
        -- "$url"
      ;;
    wget)
      wget -q -T 120 -t 1 -O "$candidate" "$url"
      ;;
    *)
      return 3
      ;;
  esac
}

__bashdeps_download() {
  local url candidate attempt status
  url=$1
  candidate=$2

  __bashdeps_select_download_backend || return $?
  for ((attempt = 1; attempt <= 3; attempt++)); do
    rm -f "$candidate" || return 6
    if __bashdeps_download_once "$url" "$candidate"; then
      return 0
    else
      status=$?
    fi
    ((status == 3)) && return 3
  done

  __bashdeps_diag "network acquisition failed: $url"
  return 4
}

__bashdeps_project_root() {
  pwd -P
}

__bashdeps_check_existing_path() {
  local root dest current component last index
  local -a components
  root=$1
  dest=$2

  IFS='/' read -r -a components <<<"$dest"
  current=$root
  last=$((${#components[@]} - 1))

  for ((index = 0; index <= last; index++)); do
    component=${components[index]}
    current=$current/$component

    if [[ -L $current ]]; then
      __bashdeps_diag "symbolic links are not permitted in destination path: $dest"
      return 6
    fi

    if ((index < last)); then
      if [[ -e $current && ! -d $current ]]; then
        __bashdeps_diag "destination parent is not a directory: $dest"
        return 6
      fi
    elif [[ -e $current && ! -f $current ]]; then
      __bashdeps_diag "destination is not a regular file: $dest"
      return 6
    fi
  done
}

__bashdeps_check_parent_path() {
  local root dest current component last index
  local -a components
  root=$1
  dest=$2

  IFS='/' read -r -a components <<<"$dest"
  current=$root
  last=$((${#components[@]} - 1))

  for ((index = 0; index < last; index++)); do
    component=${components[index]}
    current=$current/$component
    if [[ -L $current ]]; then
      __bashdeps_diag "symbolic links are not permitted in destination path: $dest"
      return 6
    fi
    if [[ -e $current && ! -d $current ]]; then
      __bashdeps_diag "destination parent is not a directory: $dest"
      return 6
    fi
  done
}

__bashdeps_destination_state() {
  local root dest expected path actual
  root=$1
  dest=$2
  expected=$3
  path=$root/$dest

  __bashdeps_check_existing_path "$root" "$dest" || return $?
  [[ -e $path ]] || return 1

  actual=$(__bashdeps_hash_file "$path") || return $?
  [[ $actual == "$expected" ]] || return 1
  return 0
}

__bashdeps_make_stage() {
  local root candidate attempt
  root=$1

  for ((attempt = 1; attempt <= 5; attempt++)); do
    candidate=$root/.bashdeps-stage.$$.$RANDOM
    if mkdir -m 0700 "$candidate" 2>/dev/null; then
      __bashdeps_stage_dir=$candidate
      return 0
    fi
  done

  __bashdeps_diag 'unable to create staging directory'
  return 6
}

__bashdeps_cleanup_stage() {
  if [[ -n $__bashdeps_stage_dir ]]; then
    rm -rf "$__bashdeps_stage_dir" 2>/dev/null || :
    __bashdeps_stage_dir=''
  fi
}

__bashdeps_ensure_parent() {
  local root dest parent
  root=$1
  dest=$2

  if [[ $dest == */* ]]; then
    parent=${dest%/*}
    __bashdeps_check_parent_path "$root" "$dest" || return $?
    mkdir -p "$root/$parent" 2>/dev/null || {
      __bashdeps_diag "unable to create destination parent: $parent"
      return 6
    }
    __bashdeps_check_parent_path "$root" "$dest" || return $?
  fi
}

__bashdeps_publish_candidate() {
  local root dest candidate final tmp attempt
  root=$1
  dest=$2
  candidate=$3
  final=$root/$dest

  __bashdeps_ensure_parent "$root" "$dest" || return $?
  __bashdeps_check_existing_path "$root" "$dest" || return $?

  for ((attempt = 1; attempt <= 5; attempt++)); do
    tmp=$final.bashdeps-tmp.$$.$RANDOM
    [[ ! -e $tmp && ! -L $tmp ]] && break
    tmp=''
  done
  [[ -n $tmp ]] || {
    __bashdeps_diag "unable to allocate publication path for: $dest"
    return 6
  }

  cp "$candidate" "$tmp" 2>/dev/null || {
    __bashdeps_diag "unable to stage verified bytes beside destination: $dest"
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }
  chmod 0644 "$tmp" 2>/dev/null || {
    __bashdeps_diag "unable to set destination mode: $dest"
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }

  __bashdeps_check_existing_path "$root" "$dest" || {
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }

  mv -f "$tmp" "$final" 2>/dev/null || {
    __bashdeps_diag "unable to publish dependency: $dest"
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }
}

__bashdeps_verify_loaded() {
  local root index state unsatisfied=0
  root=$1

  for ((index = 0; index < ${#__bashdeps_ids[@]}; index++)); do
    __bashdeps_destination_state "$root" "${__bashdeps_dests[index]}" "${__bashdeps_digests[index]}"
    state=$?
    case $state in
      0) ;;
      1)
        unsatisfied=1
        ;;
      3 | 6)
        return "$state"
        ;;
      *)
        return 6
        ;;
    esac
  done

  ((unsatisfied == 0)) || return 1
}

__bashdeps_sync_loaded() {
  local root index state candidate actual
  local -a needed candidates
  root=$1
  needed=()
  candidates=()

  for ((index = 0; index < ${#__bashdeps_ids[@]}; index++)); do
    __bashdeps_check_existing_path "$root" "${__bashdeps_dests[index]}" || return $?
    __bashdeps_destination_state "$root" "${__bashdeps_dests[index]}" "${__bashdeps_digests[index]}"
    state=$?
    case $state in
      0) ;;
      1)
        needed+=("$index")
        ;;
      3 | 6)
        return "$state"
        ;;
      *)
        return 6
        ;;
    esac
  done

  ((${#needed[@]} > 0)) || return 0

  __bashdeps_select_hash_backend || return $?
  __bashdeps_select_download_backend || return $?
  __bashdeps_make_stage "$root" || return $?
  trap '__bashdeps_cleanup_stage' EXIT

  for index in "${needed[@]}"; do
    candidate=$__bashdeps_stage_dir/$index
    __bashdeps_download "${__bashdeps_urls[index]}" "$candidate" || return $?
    actual=$(__bashdeps_hash_file "$candidate") || return $?
    if [[ $actual != "${__bashdeps_digests[index]}" ]]; then
      __bashdeps_diag "downloaded bytes do not match approved digest for: ${__bashdeps_ids[index]}"
      return 5
    fi
    candidates[index]=$candidate
  done

  for index in "${needed[@]}"; do
    __bashdeps_publish_candidate "$root" "${__bashdeps_dests[index]}" "${candidates[index]}" || return $?
  done

  __bashdeps_verify_loaded "$root"
  state=$?
  case $state in
    0) return 0 ;;
    3) return 3 ;;
    *)
      __bashdeps_diag 'final destination verification failed after publication'
      return 6
      ;;
  esac
}

__bashdeps_cmd_install() {
  local root
  (($# > 0)) || {
    __bashdeps_diag 'install requires one dependency declaration'
    return 2
  }

  __bashdeps_parse_tokens "$@" || return $?
  __bashdeps_ids=("$__bashdeps_record_id")
  __bashdeps_urls=("$__bashdeps_record_url")
  __bashdeps_dests=("$__bashdeps_record_dest")
  __bashdeps_digests=("${__bashdeps_record_digest#sha256:}")
  root=$(__bashdeps_project_root) || return 6
  __bashdeps_sync_loaded "$root"
}

__bashdeps_cmd_sync() {
  local manifest root
  (($# <= 1)) || {
    __bashdeps_diag 'sync accepts at most one manifest path'
    return 2
  }
  manifest=${1:-dependencies.txt}
  __bashdeps_load_manifest "$manifest" || return $?
  root=$(__bashdeps_project_root) || return 6
  __bashdeps_sync_loaded "$root"
}

__bashdeps_cmd_verify() {
  local manifest root
  (($# <= 1)) || {
    __bashdeps_diag 'verify accepts at most one manifest path'
    return 2
  }
  manifest=${1:-dependencies.txt}
  __bashdeps_load_manifest "$manifest" || return $?
  root=$(__bashdeps_project_root) || return 6
  __bashdeps_verify_loaded "$root"
}

__bashdeps_cmd_version() {
  printf 'bashdeps %s\n' "$__bashdeps_version"
  printf 'build_date=%s\n' "$__bashdeps_build_date"
  printf 'commit=%s\n' "$__bashdeps_build_commit"
}

__bashdeps_main() {
  local command
  command=${1:-}
  [[ -n $command ]] || {
    __bashdeps_diag 'missing command'
    __bashdeps_usage >&2
    return 2
  }
  shift

  case $command in
    install)
      __bashdeps_cmd_install "$@"
      ;;
    sync)
      __bashdeps_cmd_sync "$@"
      ;;
    verify)
      __bashdeps_cmd_verify "$@"
      ;;
    help | -h | --help)
      (($# == 0)) || {
        __bashdeps_diag 'help accepts no arguments'
        return 2
      }
      __bashdeps_usage
      ;;
    version | --version)
      (($# == 0)) || {
        __bashdeps_diag 'version accepts no arguments'
        return 2
      }
      __bashdeps_cmd_version
      ;;
    *)
      __bashdeps_diag "unknown command: $command"
      __bashdeps_usage >&2
      return 2
      ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  __bashdeps_main "$@"
  exit $?
fi
