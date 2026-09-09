#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/manifest.bash
## @brief Parses manifests while retaining exact physical source bytes.
## @details
## This module implements the validation view needed by the manifest manager and
## separately retains raw source chunks used for surgical mutation.  Logical
## records follow the bashdeps version-1 named-field grammar and ADR-015
## physical line folding.  Parsed fields are never serialized back into source;
## generated candidates are assembled from untouched raw chunks plus explicitly
## approved replacement records.
##
## The module also owns manager-specific identity selection and the final
## reverse preservation proof.  It is incorporated only into the
## manifest-manager product source closure under ADR-020.
## @see doc/adr/ADR-002-define-dependency-manifest-grammar.md
## @see doc/adr/ADR-015-define-manifest-physical-line-folding.md
## @see doc/adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md
## @par Examples
## @code
## source lib/manifest-manager/manifest.bash
## __manifest_manager_parse_manifest dependencies.txt
## @endcode

## @var __manifest_manager_ids
## @brief Validated dependency identities in logical manifest order.
declare -a __manifest_manager_ids=()

## @var __manifest_manager_urls
## @brief Validated dependency URLs aligned with dependency identities.
declare -a __manifest_manager_urls=()

## @var __manifest_manager_dests
## @brief Validated dependency destinations aligned with dependency identities.
declare -a __manifest_manager_dests=()

## @var __manifest_manager_digests
## @brief Validated complete `sha256:` digest declarations in manifest order.
declare -a __manifest_manager_digests=()

## @var __manifest_manager_raw_records
## @brief Exact physical source bytes for each logical dependency record.
declare -a __manifest_manager_raw_records=()

## @var __manifest_manager_chunk_kinds
## @brief Raw manifest chunk kinds used to reproduce untouched source structure.
declare -a __manifest_manager_chunk_kinds=()

## @var __manifest_manager_chunk_values
## @brief Exact raw bytes for comment, blank, and logical-record source chunks.
declare -a __manifest_manager_chunk_values=()

## @var __manifest_manager_chunk_records
## @brief Record index associated with each raw chunk or `-1` for non-record
## data.
declare -a __manifest_manager_chunk_records=()

## @var __manifest_manager_update_old_raw
## @brief Original raw record bytes keyed by changed logical record index.
declare -a __manifest_manager_update_old_raw=()

## @var __manifest_manager_update_new_raw
## @brief Candidate raw record bytes keyed by changed logical record index.
declare -a __manifest_manager_update_new_raw=()

## @fn __manifest_manager_reset_manifest_state()
## @brief Clears parsed manifest and raw-chunk state before one validation pass.
## @details
## Update replacement arrays are intentionally not cleared here because the
## candidate-validation pass needs to retain the original old/new replacement
## pairs for the reverse preservation proof.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 Parsed manifest state was reset.
## @par Examples
## @code
## __manifest_manager_reset_manifest_state
## @endcode
__manifest_manager_reset_manifest_state() {
  __manifest_manager_ids=()
  __manifest_manager_urls=()
  __manifest_manager_dests=()
  __manifest_manager_digests=()
  __manifest_manager_raw_records=()
  __manifest_manager_chunk_kinds=()
  __manifest_manager_chunk_values=()
  __manifest_manager_chunk_records=()
}

## @fn __manifest_manager_reset_update_state()
## @brief Clears all planned raw-record substitutions for a new transaction.
## @details
## Replacement state is separate from parser state because a candidate manifest
## must be reparsed while the original replacement pairs remain available for
## the reverse byte-preservation proof.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 Planned replacement state was reset.
## @par Examples
## @code
## __manifest_manager_reset_update_state
## @endcode
__manifest_manager_reset_update_state() {
  __manifest_manager_update_old_raw=()
  __manifest_manager_update_new_raw=()
}

## @fn __manifest_manager_trim_leading_blank()
## @brief Removes leading ASCII spaces and tabs from a caller-supplied string.
## @details
## ADR-015 ignores leading horizontal whitespace only on physical continuation
## lines.  The helper writes into a caller variable so embedded and trailing
## bytes remain intact.
## @param value String whose leading horizontal whitespace should be removed.
## @param output_name Caller variable that receives the trimmed value.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 The resulting string was assigned.
## @par Examples
## @code
## __manifest_manager_trim_leading_blank $'  \tvalue' trimmed
## @endcode
__manifest_manager_trim_leading_blank() {
  local __mm_value=$1
  local __mm_output_name=$2

  while [[ $__mm_value == ' '* || $__mm_value == $'\t'* ]]; do
    __mm_value=${__mm_value#?}
  done
  printf -v "$__mm_output_name" '%s' "$__mm_value"
}

## @fn __manifest_manager_trim_trailing_blank()
## @brief Removes trailing ASCII spaces and tabs from a caller-supplied string.
## @details
## This is used only to remove the horizontal whitespace that separates a
## logical record fragment from ADR-015's standalone trailing continuation
## marker.
## @param value String whose trailing horizontal whitespace should be removed.
## @param output_name Caller variable that receives the trimmed value.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 The resulting string was assigned.
## @par Examples
## @code
## __manifest_manager_trim_trailing_blank $'value \t' trimmed
## @endcode
__manifest_manager_trim_trailing_blank() {
  local __mm_value=$1
  local __mm_output_name=$2

  while [[ $__mm_value == *' ' || $__mm_value == *$'\t' ]]; do
    __mm_value=${__mm_value%?}
  done
  printf -v "$__mm_output_name" '%s' "$__mm_value"
}

## @fn __manifest_manager_validate_dest_text()
## @brief Validates canonical project-relative destination path text.
## @details
## The manager validates destination syntax but does not impose bashdeps'
## invocation-selected destination root because manifest-manager has no
## `--dest-root` policy option.  Empty, absolute, whitespace-bearing, repeated
## separator, trailing separator, `.` component, and `..` component forms fail.
## @param dest Destination field value to validate.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 The destination uses canonical project-relative text.
## @retval 1 The destination text is invalid.
## @par Examples
## @code
## __manifest_manager_validate_dest_text vendor/tool.bash
## @endcode
__manifest_manager_validate_dest_text() {
  local __mm_dest=$1
  local __mm_component
  local -a __mm_components

  [[ -n $__mm_dest ]] || return 1
  [[ $__mm_dest != /* ]] || return 1
  [[ $__mm_dest != */ ]] || return 1
  [[ $__mm_dest != *//* ]] || return 1
  [[ ! $__mm_dest =~ [[:space:]] ]] || return 1

  IFS='/' read -r -a __mm_components <<<"$__mm_dest"
  for __mm_component in "${__mm_components[@]}"; do
    [[ -n $__mm_component ]] || return 1
    [[ $__mm_component != '.' && $__mm_component != '..' ]] || return 1
  done
}

## @fn __manifest_manager_parse_record()
## @brief Parses one folded logical dependency declaration into validated
## fields.
## @details
## Tokens are separated only by horizontal whitespace and each token is split at
## its first `=`.  Exactly one each of `id`, `url`, `dest`, and `digest` is
## required.  Unknown and duplicate fields fail closed.  The function appends a
## successful record to the parallel parsed arrays while leaving its raw
## physical representation under the caller's control.
## @param logical Folded logical dependency record.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A field-specific diagnostic is written for the first invalid declaration.
## @returns Nothing is written to STDOUT.
## @retval 0 The logical record was valid and appended.
## @retval 2 The record violated the version-1 manifest grammar.
## @par Examples
## @code
## __manifest_manager_parse_record \
##   'id=owner/repo@v1 url=https://example.test/x' \
##   'dest=vendor/x digest=sha256:...'
## @endcode
__manifest_manager_parse_record() {
  local __mm_logical=$1
  local __mm_token __mm_name __mm_value __mm_id='' __mm_url=''
  local __mm_dest='' __mm_digest=''
  local __mm_seen_id=0 __mm_seen_url=0 __mm_seen_dest=0 __mm_seen_digest=0
  local __mm_existing
  local -a __mm_tokens

  IFS=$' \t' read -r -a __mm_tokens <<<"$__mm_logical"
  ((${#__mm_tokens[@]} > 0)) || {
    __manifest_manager_diag 'empty dependency record'
    return 2
  }

  for __mm_token in "${__mm_tokens[@]}"; do
    [[ $__mm_token == *=* ]] || {
      __manifest_manager_diag "dependency field is missing '=': $__mm_token"
      return 2
    }
    __mm_name=${__mm_token%%=*}
    __mm_value=${__mm_token#*=}
    [[ -n $__mm_name && -n $__mm_value ]] || {
      __manifest_manager_diag "dependency field is empty: $__mm_token"
      return 2
    }

    case $__mm_name in
      id)
        ((__mm_seen_id == 0)) || {
          __manifest_manager_diag 'duplicate id field'
          return 2
        }
        __mm_seen_id=1
        __mm_id=$__mm_value
        ;;
      url)
        ((__mm_seen_url == 0)) || {
          __manifest_manager_diag 'duplicate url field'
          return 2
        }
        __mm_seen_url=1
        __mm_url=$__mm_value
        ;;
      dest)
        ((__mm_seen_dest == 0)) || {
          __manifest_manager_diag 'duplicate dest field'
          return 2
        }
        __mm_seen_dest=1
        __mm_dest=$__mm_value
        ;;
      digest)
        ((__mm_seen_digest == 0)) || {
          __manifest_manager_diag 'duplicate digest field'
          return 2
        }
        __mm_seen_digest=1
        __mm_digest=$__mm_value
        ;;
      *)
        __manifest_manager_diag "unknown dependency field: $__mm_name"
        return 2
        ;;
    esac
  done

  ((__mm_seen_id && __mm_seen_url && __mm_seen_dest && __mm_seen_digest)) || {
    __manifest_manager_diag 'dependency record is missing one or more required fields'
    return 2
  }
  [[ $__mm_url == https://* ]] || {
    __manifest_manager_diag "dependency $__mm_id has a non-HTTPS url"
    return 2
  }
  __manifest_manager_validate_dest_text "$__mm_dest" || {
    __manifest_manager_diag "dependency $__mm_id has an invalid destination: $__mm_dest"
    return 2
  }
  [[ $__mm_digest =~ ^sha256:[0-9a-f]{64}$ ]] || {
    __manifest_manager_diag "dependency $__mm_id has an invalid digest"
    return 2
  }

  for __mm_existing in "${__manifest_manager_ids[@]}"; do
    [[ $__mm_existing != "$__mm_id" ]] || {
      __manifest_manager_diag "duplicate dependency identity: $__mm_id"
      return 2
    }
  done
  for __mm_existing in "${__manifest_manager_dests[@]}"; do
    [[ $__mm_existing != "$__mm_dest" ]] || {
      __manifest_manager_diag "duplicate dependency destination: $__mm_dest"
      return 2
    }
  done

  __manifest_manager_ids+=("$__mm_id")
  __manifest_manager_urls+=("$__mm_url")
  __manifest_manager_dests+=("$__mm_dest")
  __manifest_manager_digests+=("$__mm_digest")
}

## @fn __manifest_manager_parse_manifest()
## @brief Validates a manifest and retains exact source chunks and raw records.
## @details
## The complete input is first checked for a lossless Bash round trip.  Physical
## lines are then classified as blank/comment chunks or dependency-record bytes.
## ADR-015 continuation markers join logical fragments with one ASCII space
## while the original physical bytes, line endings, indentation, and
## final-newline state remain stored separately for surgical candidate
## generation.
## @param source Captured manifest file to parse.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies malformed continuation or record content.
## @returns Nothing is written to STDOUT.
## @retval 0 The complete manifest is valid and parsed.
## @retval 2 The manifest grammar or lossless representation requirement failed.
## @retval 6 The input could not be read.
## @par Examples
## @code
## __manifest_manager_parse_manifest "$__manifest_manager_original_file"
## @endcode
__manifest_manager_parse_manifest() {
  local __mm_source=$1
  local __mm_line __mm_semantic __mm_fragment __mm_raw_line
  local __mm_raw_record='' __mm_logical='' __mm_had_newline
  local __mm_continuing=0 __mm_line_continues __mm_record_index
  local __mm_record_status

  __manifest_manager_assert_lossless_text "$__mm_source" || return $?
  __manifest_manager_reset_manifest_state

  exec 3<"$__mm_source" || {
    __manifest_manager_diag "unable to read manifest: $__mm_source"
    return 6
  }

  while :; do
    __mm_line=''
    if IFS= read -r __mm_line <&3; then
      __mm_had_newline=1
    elif [[ -n $__mm_line ]]; then
      __mm_had_newline=0
    else
      break
    fi

    __mm_raw_line=$__mm_line
    if ((__mm_had_newline)); then
      __mm_raw_line+=$'\n'
    fi

    __mm_semantic=$__mm_line
    if [[ $__mm_semantic == *$'\r' ]]; then
      __mm_semantic=${__mm_semantic%$'\r'}
    fi

    if ((__mm_continuing == 0)); then
      if [[ $__mm_semantic =~ ^[[:blank:]]*$ || $__mm_semantic =~ ^[[:blank:]]*# ]]; then
        __manifest_manager_chunk_kinds+=(literal)
        __manifest_manager_chunk_values+=("$__mm_raw_line")
        __manifest_manager_chunk_records+=(-1)
        continue
      fi
      __mm_raw_record=''
      __mm_logical=''
    else
      if [[ $__mm_semantic =~ ^[[:blank:]]*$ || $__mm_semantic =~ ^[[:blank:]]*# ]]; then
        exec 3<&-
        __manifest_manager_diag \
          'blank or comment line cannot immediately follow a continuation marker'
        return 2
      fi
    fi

    __mm_raw_record+=$__mm_raw_line
    __mm_fragment=$__mm_semantic
    if ((__mm_continuing)); then
      __manifest_manager_trim_leading_blank "$__mm_fragment" __mm_fragment
    fi

    __mm_line_continues=0
    if [[ $__mm_fragment == *\\ ]]; then
      __mm_fragment=${__mm_fragment%\\}
      if [[ $__mm_fragment == *' ' || $__mm_fragment == *$'\t' ]]; then
        __manifest_manager_trim_trailing_blank "$__mm_fragment" __mm_fragment
        __mm_line_continues=1
      else
        __mm_fragment+=$'\\'
      fi
    fi

    if ((__mm_continuing)); then
      __mm_logical+=" $__mm_fragment"
    else
      __mm_logical=$__mm_fragment
    fi

    if ((__mm_line_continues)); then
      __mm_continuing=1
      continue
    fi

    __mm_continuing=0
    __manifest_manager_parse_record "$__mm_logical" || {
      __mm_record_status=$?
      exec 3<&-
      return "$__mm_record_status"
    }
    __mm_record_index=$((${#__manifest_manager_ids[@]} - 1))
    __manifest_manager_raw_records+=("$__mm_raw_record")
    __manifest_manager_chunk_kinds+=(record)
    __manifest_manager_chunk_values+=("$__mm_raw_record")
    __manifest_manager_chunk_records+=("$__mm_record_index")
  done
  exec 3<&-

  if ((__mm_continuing)); then
    __manifest_manager_diag 'manifest ends with an unterminated continuation marker'
    return 2
  fi
}

## @fn __manifest_manager_split_identity()
## @brief Splits one manager-compatible `OWNER/REPO@VERSION` identity.
## @details
## Core bashdeps treats identity as opaque.  The manifest manager interprets
## only the maintenance convention needed for GitHub release updates.  Exactly
## one `@` separator is required, the package must contain exactly one slash,
## and neither component may contain whitespace.
## @param identity Complete manifest identity to inspect.
## @param package_output Caller variable that receives `OWNER/REPO`.
## @param version_output Caller variable that receives `VERSION`.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 The identity has an unambiguous manager-compatible shape.
## @retval 1 The identity cannot be interpreted safely by the manager.
## @par Examples
## @code
## __manifest_manager_split_identity owner/repo@v1 package version
## @endcode
__manifest_manager_split_identity() {
  local __mm_identity=$1
  local __mm_package_output=$2
  local __mm_version_output=$3
  local __mm_identity_package __mm_identity_version __mm_identity_rest

  [[ $__mm_identity == *@* ]] || return 1
  __mm_identity_package=${__mm_identity%%@*}
  __mm_identity_rest=${__mm_identity#*@}
  [[ $__mm_identity_rest != *@* ]] || return 1
  __mm_identity_version=$__mm_identity_rest

  [[ $__mm_identity_package =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  [[ -n $__mm_identity_version && ! $__mm_identity_version =~ [[:space:]@] ]] || return 1

  printf -v "$__mm_package_output" '%s' "$__mm_identity_package"
  printf -v "$__mm_version_output" '%s' "$__mm_identity_version"
}

## @fn __manifest_manager_validate_target_tag()
## @brief Validates target tag text that will become part of a manifest
## identity.
## @details
## The initial CLI forbids empty tags, whitespace, and `@` because those bytes
## would make `OWNER/REPO@TAG` ambiguous to the maintenance interface.  No
## semantic version parsing or leading-`v` normalization is performed.
## @param tag Explicitly supplied or GitHub-discovered target tag.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 The target tag is safe for the maintenance identity grammar.
## @retval 1 The tag is empty or contains whitespace or `@`.
## @par Examples
## @code
## __manifest_manager_validate_target_tag v1.2.3
## @endcode
__manifest_manager_validate_target_tag() {
  local __mm_tag=$1
  [[ -n $__mm_tag && ! $__mm_tag =~ [[:space:]@] ]]
}

## @fn __manifest_manager_identity_matches_url_ref()
## @brief Tests the accepted compatibility relationship between identity and URL
## versions.
## @details
## The initial updater accepts exact equality or exactly one leading `v`
## difference in either direction.  This keeps existing `id=@0.0.6` with
## `url=/v0.0.6/` declarations updateable without normalizing either field.
## @param identity_version Version text from `id`.
## @param url_ref Ref/tag text parsed from the immutable GitHub URL.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 The values correspond exactly or by one leading `v`.
## @retval 1 The values do not satisfy the compatibility rule.
## @par Examples
## @code
## __manifest_manager_identity_matches_url_ref 1.2.3 v1.2.3
## @endcode
__manifest_manager_identity_matches_url_ref() {
  local __mm_identity_version=$1
  local __mm_url_ref=$2

  [[ $__mm_identity_version == "$__mm_url_ref" ]] && return 0
  [[ v$__mm_identity_version == "$__mm_url_ref" ]] && return 0
  [[ $__mm_identity_version == v"$__mm_url_ref" ]] && return 0
  return 1
}

## @fn __manifest_manager_find_package_record()
## @brief Resolves one update package name to exactly one parsed record index.
## @details
## Each identity is interpreted through the manager maintenance convention.
## Unsupported identities do not match a single-package request.  The requested
## package must occur exactly once; zero or multiple matches fail rather than
## guessing which declaration the maintainer intended.
## @param package Requested `OWNER/REPO` package name.
## @param index_output Caller variable receiving the zero-based record index.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A concise diagnostic identifies zero or ambiguous package matches.
## @returns Nothing is written to STDOUT.
## @retval 0 Exactly one record matched and its index was assigned.
## @retval 2 Selection was missing or ambiguous.
## @par Examples
## @code
## __manifest_manager_find_package_record owner/repo index
## @endcode
__manifest_manager_find_package_record() {
  local __mm_package=$1
  local __mm_index_output=$2
  local __mm_index __mm_identity_package __mm_identity_version
  local __mm_matches=0 __mm_match_index=-1

  for ((__mm_index = 0; __mm_index < ${#__manifest_manager_ids[@]}; __mm_index++)); do
    if __manifest_manager_split_identity \
      "${__manifest_manager_ids[__mm_index]}" \
      __mm_identity_package __mm_identity_version &&
      [[ $__mm_identity_package == "$__mm_package" ]]; then
      __mm_matches=$((__mm_matches + 1))
      __mm_match_index=$__mm_index
    fi
  done

  ((__mm_matches == 1)) || {
    if ((__mm_matches == 0)); then
      __manifest_manager_diag "dependency package not found: $__mm_package"
    else
      __manifest_manager_diag "dependency package is ambiguous: $__mm_package"
    fi
    return 2
  }

  printf -v "$__mm_index_output" '%s' "$__mm_match_index"
}

## @fn __manifest_manager_emit_candidate()
## @brief Writes the complete candidate manifest from preserved raw chunks.
## @details
## Literal chunks are always written byte-for-byte.  A logical record chunk is
## written from the planned replacement array only when that record index was
## deliberately updated; otherwise its original raw bytes are emitted exactly.
## @param output_path Staging path that receives the candidate manifest.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when candidate staging cannot be completed.
## @returns Nothing is written to STDOUT.
## @retval 0 The complete candidate manifest was written.
## @retval 6 Candidate output failed.
## @par Examples
## @code
## __manifest_manager_emit_candidate "$__manifest_manager_candidate_file"
## @endcode
__manifest_manager_emit_candidate() {
  local __mm_output_path=$1
  local __mm_chunk_index __mm_record_index __mm_value

  : >"$__mm_output_path" || {
    __manifest_manager_diag 'unable to create candidate manifest'
    return 6
  }

  for ((__mm_chunk_index = 0; __mm_chunk_index < ${#__manifest_manager_chunk_kinds[@]}; __mm_chunk_index++)); do
    __mm_record_index=${__manifest_manager_chunk_records[__mm_chunk_index]}
    __mm_value=${__manifest_manager_chunk_values[__mm_chunk_index]}
    if [[ ${__manifest_manager_chunk_kinds[__mm_chunk_index]} == record &&
      -n ${__manifest_manager_update_new_raw[__mm_record_index]+x} ]]; then
      __mm_value=${__manifest_manager_update_new_raw[__mm_record_index]}
    fi
    printf '%s' "$__mm_value" >>"$__mm_output_path" || {
      __manifest_manager_diag 'unable to stage complete candidate manifest'
      return 6
    }
  done
}

## @fn __manifest_manager_reverse_candidate()
## @brief Reverses every planned record substitution for byte-preservation proof.
## @details
## The complete candidate is read losslessly into a Bash string and each new raw
## record is replaced once with its old raw record in reverse record order.
## Reverse order avoids one planned replacement affecting a later old/new pair.
## The caller compares the reversed result with the captured original file.
## @param candidate_path Complete candidate manifest staging path.
## @param output_path File that receives the reversed candidate bytes.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when reversal cannot be performed exactly.
## @returns Nothing is written to STDOUT.
## @retval 0 Every planned replacement reversed exactly once.
## @retval 5 Reverse substitution could not prove exact preservation.
## @retval 6 Candidate input or proof output could not be processed.
## @par Examples
## @code
## __manifest_manager_reverse_candidate candidate.manifest reversed.manifest
## @endcode
__manifest_manager_reverse_candidate() {
  local __mm_candidate_path=$1
  local __mm_output_path=$2
  local __mm_candidate='' __mm_line __mm_index __mm_transformed

  while IFS= read -r __mm_line || [[ -n $__mm_line ]]; do
    __mm_candidate+="$__mm_line"
    if [[ ! -z $__mm_line || -s $__mm_candidate_path ]]; then
      __mm_candidate+=$'\n'
    fi
  done <"$__mm_candidate_path"

  if [[ -s $__mm_candidate_path && $(tail -c 1 "$__mm_candidate_path" 2>/dev/null | od -An -tu1 | tr -d ' ') != 10 ]]; then
    __mm_candidate=${__mm_candidate%$'\n'}
  fi

  for ((__mm_index = ${#__manifest_manager_update_new_raw[@]} - 1; __mm_index >= 0; __mm_index--)); do
    [[ -n ${__manifest_manager_update_new_raw[__mm_index]+x} ]] || continue
    __manifest_manager_literal_replace_once \
      "$__mm_candidate" \
      "${__manifest_manager_update_new_raw[__mm_index]}" \
      "${__manifest_manager_update_old_raw[__mm_index]}" \
      __mm_transformed || {
      __manifest_manager_diag 'unable to reverse planned manifest substitution'
      return 5
    }
    __mm_candidate=$__mm_transformed
  done

  printf '%s' "$__mm_candidate" >"$__mm_output_path" || return 6
}
