#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/github.bash
## @brief Implements GitHub release discovery and immutable artifact retrieval.
## @details
## This module contains the GitHub-specific behavior permitted only to the
## manifest-manager product by ADR-020.  It uses curl directly, follows HTTPS
## redirects, derives omitted target versions from GitHub's canonical
## `releases/latest` redirect, transforms only explicitly supported immutable
## URL families, and downloads candidate bytes into private staging.
##
## The module never calls the GitHub CLI or a JSON API parser, and downloaded
## artifacts are treated as data only.  No function in this module executes a
## retrieved dependency artifact.
## @see doc/adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md
## @see doc/manifest-manager-spec.md
## @par Examples
## @code
## source lib/manifest-manager/github.bash
## __manifest_manager_latest_release_tag owner/repo tag
## @endcode

## @fn __manifest_manager_require_curl()
## @brief Verifies that the manifest manager can invoke curl.
## @details
## Curl is a manager-specific runtime requirement used for both latest-release
## discovery and candidate artifact retrieval.  Its presence does not alter the
## separate downloader contract of `bashdeps.bash`.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when curl is unavailable.
## @returns Nothing is written to STDOUT.
## @retval 0 Curl is available in PATH.
## @retval 3 Curl is unavailable.
## @par Examples
## @code
## __manifest_manager_require_curl
## @endcode
__manifest_manager_require_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  __manifest_manager_diag 'curl is required by manifest-manager.bash'
  return 3
}

## @fn __manifest_manager_percent_decode_path_component()
## @brief Percent-decodes one URL path component without form-decoding `+`.
## @details
## The decoder operates under the C locale so `%HH` parsing is byte-oriented.
## Percent escapes must contain exactly two hexadecimal digits.  Encoded NUL is
## rejected because Bash strings cannot represent that byte losslessly.  Literal
## plus signs are preserved as ordinary path data.
## @param encoded Single encoded URL path component.
## @param output_name Caller variable that receives the decoded tag.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written for malformed percent escapes or encoded NUL.
## @returns Nothing is written to STDOUT.
## @retval 0 The complete component was decoded successfully.
## @retval 4 The component contained malformed or unrepresentable percent data.
## @par Examples
## @code
## __manifest_manager_percent_decode_path_component 'v1.0%2Bmeta' tag
## @endcode
__manifest_manager_percent_decode_path_component() {
  local LC_ALL=C
  local __mm_encoded=$1
  local __mm_output_name=$2
  local __mm_decoded='' __mm_char __mm_hex __mm_oct __mm_byte
  local __mm_index=0 __mm_length=${#1}

  while ((__mm_index < __mm_length)); do
    __mm_char=${__mm_encoded:__mm_index:1}
    if [[ $__mm_char != '%' ]]; then
      __mm_decoded+=$__mm_char
      __mm_index=$((__mm_index + 1))
      continue
    fi

    if ((__mm_index + 2 >= __mm_length)); then
      __manifest_manager_diag 'GitHub latest-release URL contains a malformed percent escape'
      return 4
    fi
    __mm_hex=${__mm_encoded:__mm_index+1:2}
    [[ $__mm_hex =~ ^[0-9A-Fa-f]{2}$ ]] || {
      __manifest_manager_diag 'GitHub latest-release URL contains a malformed percent escape'
      return 4
    }
    if [[ $__mm_hex == 00 ]]; then
      __manifest_manager_diag 'GitHub latest-release tag contains encoded NUL'
      return 4
    fi

    printf -v __mm_oct '%03o' "$((16#$__mm_hex))"
    printf -v __mm_byte '%b' "\$__mm_oct"
    __mm_decoded+=$__mm_byte
    __mm_index=$((__mm_index + 3))
  done

  printf -v "$__mm_output_name" '%s' "$__mm_decoded"
}

## @fn __manifest_manager_latest_release_tag()
## @brief Resolves GitHub's canonical latest release to its exact decoded tag.
## @details
## Curl requests `https://github.com/OWNER/REPO/releases/latest`, follows only
## HTTPS redirects, discards the response body, and reports the final effective
## URL.  The final URL must remain in the requested repository and end in
## exactly one release-tag path component.  That component is
## path-percent-decoded without treating `+` as a space.
## @param package GitHub repository in `OWNER/REPO` form.
## @param output_name Caller variable receiving the exact latest release tag.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT because curl output is captured internally.
## @par STDERR
## Curl or validation diagnostics are written when release discovery fails.
## @returns Nothing is written to STDOUT.
## @retval 0 GitHub's exact latest release tag was assigned.
## @retval 3 Curl is unavailable.
## @retval 4 Discovery, redirect validation, or percent decoding failed.
## @par Examples
## @code
## __manifest_manager_latest_release_tag wesley-dean/bash-doxygen tag
## @endcode
__manifest_manager_latest_release_tag() {
  local __mm_package=$1
  local __mm_output_name=$2
  local __mm_request __mm_effective __mm_prefix __mm_encoded __mm_tag=''

  __manifest_manager_require_curl || return $?
  __mm_request="https://github.com/$__mm_package/releases/latest"
  __mm_prefix="https://github.com/$__mm_package/releases/tag/"

  __mm_effective=$(curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --proto-redir '=https' \
    --max-redirs 10 \
    --connect-timeout 10 \
    --max-time 120 \
    --output /dev/null \
    --write-out '%{url_effective}' \
    -- "$__mm_request") || {
      __manifest_manager_diag "unable to resolve latest GitHub release: $__mm_package"
      return 4
    }

  [[ $__mm_effective == "$__mm_prefix"* ]] || {
    __manifest_manager_diag \
      "latest GitHub release redirected outside the expected repository: $__mm_package"
    return 4
  }
  __mm_encoded=${__mm_effective#"$__mm_prefix"}
  [[ -n $__mm_encoded && $__mm_encoded != */* && $__mm_encoded != *'?'* && $__mm_encoded != *'#'* ]] || {
    __manifest_manager_diag \
      "latest GitHub release did not resolve to one release-tag path component: $__mm_package"
    return 4
  }

  __manifest_manager_percent_decode_path_component "$__mm_encoded" __mm_tag || return $?
  __manifest_manager_validate_target_tag "$__mm_tag" || return 4
  printf -v "$__mm_output_name" '%s' "$__mm_tag"
}

## @fn __manifest_manager_ref_corresponds_to_version()
## @brief Tests the ADR-020 compatibility relation for an existing URL ref/tag.
## @details
## Exact equality is accepted.  For compatibility with existing manifests, one
## leading `v` difference is also accepted.  No other normalization or semantic
## version interpretation occurs.
## @param version Current VERSION text from the manifest identity.
## @param ref Current REF or TAG text represented in the immutable URL.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 The URL ref/tag corresponds to the identity version.
## @retval 1 The two strings do not satisfy the accepted compatibility relation.
## @par Examples
## @code
## __manifest_manager_ref_corresponds_to_version 0.0.6 v0.0.6
## @endcode
__manifest_manager_ref_corresponds_to_version() {
  local __mm_version=$1
  local __mm_ref=$2

  [[ $__mm_ref == "$__mm_version" ]] && return 0
  [[ $__mm_ref == "v$__mm_version" ]] && return 0
  if [[ $__mm_version == v* && ${__mm_version#v} == "$__mm_ref" ]]; then
    return 0
  fi
  return 1
}

## @fn __manifest_manager_transform_github_url()
## @brief Constructs a candidate immutable URL from one supported existing URL.
## @details
## The function recognizes only raw.githubusercontent.com content URLs and
## GitHub release-download URLs for the exact selected package.  It identifies
## the existing ref/tag by testing the current identity version and the
## single-leading `v` compatibility form.  The artifact suffix is retained
## literally.  Raw content URLs reject target tags containing `/` because the
## ref/path boundary would become ambiguous.
## @param package Selected GitHub `OWNER/REPO` package.
## @param current_version Existing identity VERSION text.
## @param target_tag Exact requested or discovered target tag.
## @param current_url Existing immutable artifact URL.
## @param output_name Caller variable that receives the candidate URL.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies unsupported or ambiguous URL relationships.
## @returns Nothing is written to STDOUT.
## @retval 0 A supported candidate URL was assigned.
## @retval 2 The existing declaration cannot be transformed unambiguously.
## @par Examples
## @code
## __manifest_manager_transform_github_url owner/repo 1.0 v1.1 \
##   'https://raw.githubusercontent.com/owner/repo/v1.0/tool' candidate
## @endcode
__manifest_manager_transform_github_url() {
  local __mm_package=$1
  local __mm_current_version=$2
  local __mm_target_tag=$3
  local __mm_current_url=$4
  local __mm_output_name=$5
  local __mm_kind __mm_prefix __mm_rest __mm_candidate_ref __mm_suffix
  local __mm_matched_ref='' __mm_match_count=0
  local -a __mm_ref_candidates

  if [[ $__mm_current_url == "https://raw.githubusercontent.com/$__mm_package/"* ]]; then
    __mm_kind=raw
    __mm_prefix="https://raw.githubusercontent.com/$__mm_package/"
    [[ $__mm_target_tag != */* ]] || {
      __manifest_manager_diag \
        "raw GitHub URLs cannot use target tags containing '/': $__mm_target_tag"
      return 2
    }
  elif [[ $__mm_current_url == "https://github.com/$__mm_package/releases/download/"* ]]; then
    __mm_kind=release
    __mm_prefix="https://github.com/$__mm_package/releases/download/"
  else
    __manifest_manager_diag \
      "dependency URL is not a supported immutable GitHub form: $__mm_current_url"
    return 2
  fi

  __mm_rest=${__mm_current_url#"$__mm_prefix"}
  __mm_ref_candidates=("$__mm_current_version")
  if [[ $__mm_current_version == v* && -n ${__mm_current_version#v} ]]; then
    __mm_ref_candidates+=("${__mm_current_version#v}")
  else
    __mm_ref_candidates+=("v$__mm_current_version")
  fi

  for __mm_candidate_ref in "${__mm_ref_candidates[@]}"; do
    if [[ $__mm_rest == "$__mm_candidate_ref/"* ]]; then
      __mm_suffix=${__mm_rest#"$__mm_candidate_ref/"}
      [[ -n $__mm_suffix ]] || continue
      __manifest_manager_ref_corresponds_to_version \
        "$__mm_current_version" "$__mm_candidate_ref" || continue
      __mm_matched_ref=$__mm_candidate_ref
      __mm_match_count=$((__mm_match_count + 1))
    fi
  done

  if ((__mm_match_count != 1)); then
    __manifest_manager_diag \
      "dependency URL ref/tag does not map uniquely to identity version $__mm_current_version"
    return 2
  fi

  __mm_suffix=${__mm_rest#"$__mm_matched_ref/"}
  [[ -n $__mm_suffix ]] || return 2
  case $__mm_kind in
    raw | release)
      printf -v "$__mm_output_name" '%s%s/%s' \
        "$__mm_prefix" "$__mm_target_tag" "$__mm_suffix"
      ;;
    *)
      return 2
      ;;
  esac
}

## @fn __manifest_manager_download_candidate()
## @brief Retrieves one candidate artifact into caller-owned private staging.
## @details
## Curl follows only HTTPS redirects and writes directly to a private staging
## path, never to the manifest's declared destination.  Transport success
## establishes only that bytes were retrieved; SHA-256 calculation and manifest
## proposal logic remain separate.  The downloaded file is never executed.
## @param url Candidate immutable HTTPS artifact URL.
## @param output Private staging path that receives candidate bytes.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Curl or a manager diagnostic is written when acquisition fails.
## @returns Nothing is written to STDOUT.
## @retval 0 Candidate bytes were downloaded completely.
## @retval 3 Curl is unavailable.
## @retval 4 Candidate artifact acquisition failed.
## @par Examples
## @code
## __manifest_manager_download_candidate \
##   'https://raw.githubusercontent.com/owner/repo/v1/tool' candidate.bin
## @endcode
__manifest_manager_download_candidate() {
  local __mm_url=$1
  local __mm_output=$2

  __manifest_manager_require_curl || return $?
  rm -f "$__mm_output" || return 4
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
    --output "$__mm_output" \
    -- "$__mm_url" || {
      __manifest_manager_diag "candidate artifact acquisition failed: $__mm_url"
      return 4
    }
}
