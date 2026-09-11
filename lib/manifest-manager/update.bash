#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/update.bash
## @brief Coordinates transactional manifest-manager update operations.
## @details
## This module connects validated manifest records, GitHub release discovery,
## candidate retrieval, SHA-256 calculation, optional upstream checksum
## corroboration, surgical literal substitution, and reverse preservation proof.
## All selected dependencies are planned before a complete candidate is emitted,
## so `--all` remains a whole-manifest source transaction.  Shared stream emission
## and file publication are owned by `transaction.bash` and do not form part of
## the update-specific mutation proof.
## @see doc/adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md
## @see doc/adr/ADR-023-add-supplemental-upstream-sha256-verification.md
## @see doc/manifest-manager-spec.md
## @par Examples
## @code
## source lib/manifest-manager/update.bash
## __manifest_manager_update_transaction dependencies.txt 0 owner/repo '' 0
## @endcode

## @var __manifest_manager_selected_indices
## @brief Logical record indexes selected for the current update transaction.
declare -a __manifest_manager_selected_indices=()

## @var __manifest_manager_option_filename
## @brief Manifest path selected by the parsed `update` CLI.
__manifest_manager_option_filename='dependencies.txt'

## @var __manifest_manager_option_all
## @brief Whether the parsed update CLI requested whole-manifest `--all` behavior.
__manifest_manager_option_all=0

## @var __manifest_manager_option_package
## @brief Single package selected by the parsed update CLI when not using `--all`.
__manifest_manager_option_package=''

## @var __manifest_manager_option_version
## @brief Explicit target tag supplied by the caller, when present.
__manifest_manager_option_version=''

## @var __manifest_manager_option_version_supplied
## @brief Whether target version selection is explicit rather than latest-release.
__manifest_manager_option_version_supplied=0

## @fn __manifest_manager_validate_package()
## @brief Validates a package argument as one GitHub `OWNER/REPO` coordinate.
## @details
## The maintenance interface is intentionally provider-specific in its first
## version.  Package validation accepts the conservative ASCII repository shape
## used by identity parsing and rejects whitespace, extra path components, and
## `@` syntax that belongs to the combined explicit-version form.
## @param package Package text supplied by the caller.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies an invalid package coordinate.
## @returns Nothing is written to STDOUT.
## @retval 0 The package has the supported GitHub shape.
## @retval 2 The package is invalid or ambiguous.
## @par Examples
## @code
## __manifest_manager_validate_package wesley-dean/bash-doxygen
## @endcode
__manifest_manager_validate_package() {
  local __mm_package=$1

  [[ $__mm_package =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
    __manifest_manager_diag "invalid GitHub package: $__mm_package"
    return 2
  }
}

## @fn __manifest_manager_parse_checksum_file()
## @brief Extracts one SHA-256 value from a narrowly formatted checksum resource.
## @details
## ADR-023 permits exactly one non-blank checksum entry.  The digest token may be
## bare or prefixed with `sha256:`; an omitted algorithm therefore defaults to
## SHA-256.  Conventional text or binary-marker filename suffixes are accepted but
## ignored as trust input.  Other explicit algorithms, multiple entries, comments,
## and malformed syntax fail closed.  Hexadecimal digest text is normalized to
## lowercase before it is returned.
## @param path Downloaded checksum-resource path in private staging.
## @param identity Dependency identity used only for diagnostics.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## The normalized 64-character lowercase SHA-256 digest is written on success.
## @par STDERR
## A diagnostic identifies empty, multi-entry, or malformed checksum content.
## @returns The normalized SHA-256 digest followed by a newline on success.
## @retval 0 Exactly one supported checksum entry was parsed.
## @retval 5 The checksum resource was unreadable or syntactically unusable.
## @par Examples
## @code
## digest=$(__manifest_manager_parse_checksum_file checksum.txt owner/repo@v1)
## @endcode
__manifest_manager_parse_checksum_file() {
  local __mm_path=$1
  local __mm_identity=$2
  local __mm_line='' __mm_entry='' __mm_digest='' __mm_filename=''
  local __mm_nonblank=0

  [[ -f $__mm_path && -r $__mm_path ]] || {
    __manifest_manager_diag "upstream checksum resource is not readable for: $__mm_identity"
    return 5
  }

  while IFS= read -r __mm_line || [[ -n $__mm_line ]]; do
    if [[ $__mm_line == *$'\r' ]]; then
      __mm_line=${__mm_line%$'\r'}
    fi
    [[ $__mm_line =~ ^[[:blank:]]*$ ]] && continue

    __mm_nonblank=$((__mm_nonblank + 1))
    if ((__mm_nonblank > 1)); then
      __manifest_manager_diag \
        "upstream checksum resource contains multiple entries for: $__mm_identity"
      return 5
    fi
    __mm_entry=$__mm_line
  done <"$__mm_path"

  ((__mm_nonblank == 1)) || {
    __manifest_manager_diag "upstream checksum resource is empty for: $__mm_identity"
    return 5
  }

  if [[ $__mm_entry =~ ^(sha256:)?([0-9A-Fa-f]{64})$ ]]; then
    __mm_digest=${BASH_REMATCH[2]}
  elif [[ $__mm_entry =~ ^(sha256:)?([0-9A-Fa-f]{64})[[:blank:]]+\*?(.+)$ ]]; then
    __mm_digest=${BASH_REMATCH[2]}
    __mm_filename=${BASH_REMATCH[3]}
    [[ $__mm_filename =~ [^[:blank:]] ]] || {
      __manifest_manager_diag "upstream checksum filename is empty for: $__mm_identity"
      return 5
    }
  else
    __manifest_manager_diag "upstream checksum resource is malformed for: $__mm_identity"
    return 5
  fi

  printf '%s\n' "${__mm_digest,,}"
}

## @fn __manifest_manager_preflight_record()
## @brief Verifies that one record is release-updateable before network activity.
## @details
## The record identity must satisfy the manager convention, must not be a 40- or
## 64-character hexadecimal commit pin, and its existing URL must be one of the
## supported GitHub immutable forms related to the current identity version.
## When `digest_url` is present, that URL must independently satisfy the same
## package/version relationship.  Using the current version as a provisional target
## exercises URL recognition without selecting or retrieving a new release.
## @param index Logical dependency record index to inspect.
## @param package_output Caller variable that receives the record package.
## @param version_output Caller variable receiving the current identity version.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies unsupported identity, commit pin, or URL state.
## @returns Nothing is written to STDOUT.
## @retval 0 The record is structurally eligible for release update planning.
## @retval 2 The record is unsupported or ambiguous.
## @par Examples
## @code
## __manifest_manager_preflight_record 0 package version
## @endcode
__manifest_manager_preflight_record() {
  local __mm_index=$1
  local __mm_package_output=$2
  local __mm_version_output=$3
  local __mm_record_package='' __mm_record_version='' __mm_probe=''

  __manifest_manager_split_identity \
    "${__manifest_manager_ids[__mm_index]}" __mm_record_package __mm_record_version || {
      __manifest_manager_diag \
        "dependency identity is not updateable: ${__manifest_manager_ids[__mm_index]}"
      return 2
    }

  if __manifest_manager_is_commit_pin "$__mm_record_version"; then
    __manifest_manager_diag \
      "commit-pinned dependency is not release-updateable: ${__manifest_manager_ids[__mm_index]}"
    return 2
  fi

  __manifest_manager_transform_github_url \
    "$__mm_record_package" \
    "$__mm_record_version" \
    "$__mm_record_version" \
    "${__manifest_manager_urls[__mm_index]}" \
    __mm_probe || return $?

  if [[ -n ${__manifest_manager_digest_urls[__mm_index]} ]]; then
    __manifest_manager_transform_github_url \
      "$__mm_record_package" \
      "$__mm_record_version" \
      "$__mm_record_version" \
      "${__manifest_manager_digest_urls[__mm_index]}" \
      __mm_probe || return $?
  fi

  printf -v "$__mm_package_output" '%s' "$__mm_record_package"
  printf -v "$__mm_version_output" '%s' "$__mm_record_version"
}

## @fn __manifest_manager_preflight_all()
## @brief Selects every record only after complete non-network eligibility checks.
## @details
## `--all` means every dependency.  The helper therefore validates every record's
## manager identity, rejects commit pins and unsupported artifact/checksum URL
## forms, and requires package names to be unique before curl or hashing capability
## is consulted.  Unsupported dependencies are never silently skipped.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies the first unsupported or duplicate package.
## @returns Nothing is written to STDOUT.
## @retval 0 Every record was eligible and selected; empty is allowed.
## @retval 2 At least one record cannot participate safely in `--all`.
## @par Examples
## @code
## __manifest_manager_preflight_all
## @endcode
__manifest_manager_preflight_all() {
  local __mm_index __mm_package='' __mm_version=''
  local -A __mm_seen_packages=()

  __manifest_manager_selected_indices=()
  for __mm_index in "${!__manifest_manager_ids[@]}"; do
    __manifest_manager_preflight_record \
      "$__mm_index" __mm_package __mm_version || return $?
    if [[ -n ${__mm_seen_packages[$__mm_package]+set} ]]; then
      __manifest_manager_diag "dependency package is not unique: $__mm_package"
      return 2
    fi
    __mm_seen_packages[$__mm_package]=1
    __manifest_manager_selected_indices+=("$__mm_index")
  done
}

## @fn __manifest_manager_plan_record_update()
## @brief Plans one fully verified raw-record replacement without publishing it.
## @details
## The helper derives the candidate artifact URL and, when already declared, the
## candidate `digest_url`; retrieves exact candidate bytes; calculates SHA-256;
## requires an upstream checksum to corroborate those bytes when applicable;
## rejects changed bytes at an unchanged immutable artifact URL; and applies
## literal field-value substitutions only when each changed old value occurs
## exactly once in the evolving raw record.  `dest` is never changed.  The
## resulting old/new raw pair is stored by record index for later whole-manifest
## emission.
## @param index Logical dependency record index to update.
## @param target_tag Exact requested or GitHub-discovered target tag.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Diagnostics identify URL, acquisition, checksum, hashing, or surgical-safety failures.
## @returns Nothing is written to STDOUT.
## @retval 0 The record update was fully planned or is a verified no-op.
## @retval 2 The target or existing declaration is not updateable.
## @retval 3 A required runtime capability is unavailable.
## @retval 4 Artifact or checksum-resource acquisition failed.
## @retval 5 Integrity, exact-substitution, or immutable-location safety failed.
## @retval 6 Staging or hashing I/O failed.
## @par Examples
## @code
## __manifest_manager_plan_record_update 0 v1.2.3
## @endcode
__manifest_manager_plan_record_update() {
  local __mm_index=$1
  local __mm_target_tag=$2
  local __mm_package='' __mm_current_version='' __mm_new_url=''
  local __mm_current_digest_url='' __mm_new_digest_url=''
  local __mm_artifact __mm_checksum __mm_hash __mm_upstream_hash
  local __mm_new_digest __mm_new_id
  local __mm_old_raw __mm_new_raw __mm_work

  __manifest_manager_validate_target_tag "$__mm_target_tag" || return $?
  __manifest_manager_preflight_record \
    "$__mm_index" __mm_package __mm_current_version || return $?
  __manifest_manager_transform_github_url \
    "$__mm_package" \
    "$__mm_current_version" \
    "$__mm_target_tag" \
    "${__manifest_manager_urls[__mm_index]}" \
    __mm_new_url || return $?

  __mm_current_digest_url=${__manifest_manager_digest_urls[__mm_index]}
  if [[ -n $__mm_current_digest_url ]]; then
    __manifest_manager_transform_github_url \
      "$__mm_package" \
      "$__mm_current_version" \
      "$__mm_target_tag" \
      "$__mm_current_digest_url" \
      __mm_new_digest_url || return $?
  fi

  __mm_artifact=$__manifest_manager_stage_dir/artifact.$__mm_index
  __manifest_manager_download_candidate "$__mm_new_url" "$__mm_artifact" || return $?
  __mm_hash=$(__manifest_manager_sha256 "$__mm_artifact") || return $?

  if [[ -n $__mm_current_digest_url ]]; then
    __mm_checksum=$__manifest_manager_stage_dir/checksum.$__mm_index
    __manifest_manager_download_candidate "$__mm_new_digest_url" "$__mm_checksum" || return $?
    __mm_upstream_hash=$(__manifest_manager_parse_checksum_file "$__mm_checksum" "${__manifest_manager_ids[__mm_index]}") || return $?
    if [[ $__mm_hash != "$__mm_upstream_hash" ]]; then
      __manifest_manager_diag \
        "downloaded bytes do not match upstream checksum for: ${__manifest_manager_ids[__mm_index]}"
      return 5
    fi
  fi

  __mm_new_digest=sha256:$__mm_hash
  __mm_new_id=$__mm_package@$__mm_target_tag

  if [[ $__mm_new_url == "${__manifest_manager_urls[__mm_index]}" && \
    $__mm_new_digest != "${__manifest_manager_digests[__mm_index]}" ]]; then
    __manifest_manager_diag \
      "bytes changed at an already-declared immutable URL: $__mm_new_url"
    return 5
  fi

  __mm_old_raw=${__manifest_manager_raw_records[__mm_index]}
  __mm_new_raw=$__mm_old_raw

  if [[ $__mm_new_id != "${__manifest_manager_ids[__mm_index]}" ]]; then
    __manifest_manager_literal_replace_once \
      "$__mm_new_raw" "${__manifest_manager_ids[__mm_index]}" "$__mm_new_id" __mm_work || return $?
    __mm_new_raw=$__mm_work
  fi

  # Update digest_url before url.  A conventional checksum URL often contains the
  # artifact URL as a literal prefix, and replacing it first preserves the exact-once
  # proof for the shorter artifact URL value.
  if [[ -n $__mm_current_digest_url && $__mm_new_digest_url != "$__mm_current_digest_url" ]]; then
    __manifest_manager_literal_replace_once \
      "$__mm_new_raw" "$__mm_current_digest_url" "$__mm_new_digest_url" __mm_work || return $?
    __mm_new_raw=$__mm_work
  fi
  if [[ $__mm_new_url != "${__manifest_manager_urls[__mm_index]}" ]]; then
    __manifest_manager_literal_replace_once \
      "$__mm_new_raw" "${__manifest_manager_urls[__mm_index]}" "$__mm_new_url" __mm_work || return $?
    __mm_new_raw=$__mm_work
  fi
  if [[ $__mm_new_digest != "${__manifest_manager_digests[__mm_index]}" ]]; then
    __manifest_manager_literal_replace_once \
      "$__mm_new_raw" "${__manifest_manager_digests[__mm_index]}" "$__mm_new_digest" __mm_work || return $?
    __mm_new_raw=$__mm_work
  fi

  if [[ $__mm_new_raw != "$__mm_old_raw" ]]; then
    __manifest_manager_update_old_raw[__mm_index]=$__mm_old_raw
    __manifest_manager_update_new_raw[__mm_index]=$__mm_new_raw
  fi
}

## @fn __manifest_manager_finalize_candidate()
## @brief Emits, reparses, reverses, and proves the complete candidate manifest.
## @details
## Candidate generation starts from the original raw chunk model and planned
## record substitutions.  The complete candidate is then parsed again.  The
## changed records are reversed only when each candidate raw record equals its
## exact expected new value, and the reversed file must compare byte-for-byte
## equal with the captured original.  This establishes the surgical preservation
## invariant before any caller-visible publication.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies candidate validation or preservation-proof failure.
## @returns Nothing is written to STDOUT.
## @retval 0 The complete candidate passed syntax and preservation validation.
## @retval 5 Candidate mutation or reverse-preservation validation failed.
## @retval 6 Staging I/O failed.
## @par Examples
## @code
## __manifest_manager_finalize_candidate
## @endcode
__manifest_manager_finalize_candidate() {
  local __mm_proof=$__manifest_manager_stage_dir/reversed.manifest
  local __mm_status

  __manifest_manager_emit_candidate "$__manifest_manager_candidate_file" || return $?

  if __manifest_manager_parse_manifest "$__manifest_manager_candidate_file"; then
    :
  else
    __mm_status=$?
    if ((__mm_status == 2)); then
      __manifest_manager_diag 'candidate manifest became invalid after surgical mutation'
      return 5
    fi
    return "$__mm_status"
  fi

  __manifest_manager_reverse_candidate "$__mm_proof" || return $?
  if ! cmp -s "$__manifest_manager_original_file" "$__mm_proof"; then
    __manifest_manager_diag \
      'candidate manifest failed byte-for-byte reverse preservation proof'
    return 5
  fi
}

## @fn __manifest_manager_update_transaction()
## @brief Executes all non-publication work for one parsed update request.
## @details
## The captured original manifest is parsed first.  Single-package mode selects
## exactly one record; `--all` preflights every record before network access.
## Required curl and SHA-256 capabilities are selected only when at least one
## dependency needs planning.  All records, including any declared upstream
## checksum corroboration, are fully planned before the candidate is emitted and
## preservation-proved.
## @param all_mode `1` for `--all`, otherwise `0`.
## @param package Single selected package when `all_mode` is `0`.
## @param explicit_version Explicit tag text when supplied.
## @param version_supplied `1` when explicit version selection is requested.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Diagnostics identify selection, discovery, acquisition, or safety failures.
## @returns Nothing is written to STDOUT.
## @retval 0 A complete validated candidate is ready for publication/output.
## @retval 2 The manifest, selection, or update declaration is invalid.
## @retval 3 A required runtime capability is unavailable.
## @retval 4 Release discovery or candidate/checksum acquisition failed.
## @retval 5 Integrity, surgical, or immutable-location safety validation failed.
## @retval 6 Input, staging, or hashing I/O failed.
## @par Examples
## @code
## __manifest_manager_update_transaction 0 owner/repo v1.2.3 1
## @endcode
__manifest_manager_update_transaction() {
  local __mm_all_mode=$1
  local __mm_requested_package=$2
  local __mm_explicit_version=$3
  local __mm_version_supplied=$4
  local __mm_index __mm_package='' __mm_current_version='' __mm_target=''

  __manifest_manager_reset_update_state
  __manifest_manager_parse_manifest "$__manifest_manager_original_file" || return $?

  if ((__mm_all_mode)); then
    __manifest_manager_preflight_all || return $?
    if ((${#__manifest_manager_selected_indices[@]} == 0)); then
      cp "$__manifest_manager_original_file" "$__manifest_manager_candidate_file" || return 6
      return 0
    fi
  else
    __manifest_manager_validate_package "$__mm_requested_package" || return $?
    __manifest_manager_find_package_record "$__mm_requested_package" __mm_index || return $?
    __manifest_manager_preflight_record \
      "$__mm_index" __mm_package __mm_current_version || return $?
    __manifest_manager_selected_indices=("$__mm_index")
  fi

  __manifest_manager_require_curl || return $?
  __manifest_manager_select_hash_backend || return $?

  for __mm_index in "${__manifest_manager_selected_indices[@]}"; do
    __manifest_manager_preflight_record \
      "$__mm_index" __mm_package __mm_current_version || return $?

    if ((__mm_all_mode)); then
      __manifest_manager_latest_release_tag "$__mm_package" __mm_target || return $?
    elif ((__mm_version_supplied)); then
      __mm_target=$__mm_explicit_version
    else
      __manifest_manager_latest_release_tag "$__mm_package" __mm_target || return $?
    fi

    __manifest_manager_validate_target_tag "$__mm_target" || return $?
    __manifest_manager_plan_record_update "$__mm_index" "$__mm_target" || return $?
  done

  __manifest_manager_finalize_candidate
}

## @fn __manifest_manager_parse_update_cli()
## @brief Parses the public arguments that follow the `update` subcommand.
## @details
## The parser supports `-a/--all`, `-f/--filename`, one package with omitted
## version, `PACKAGE VERSION`, and combined `PACKAGE@VERSION`.  It does not
## reserve the word `latest`.  Help/version are handled by the executable before
## this function so stream-mode input is not consumed for informational
## operations.
## @param args[] Arguments following the `update` subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies invalid, missing, duplicate, or conflicting arguments.
## @returns Nothing is written to STDOUT.
## @retval 0 Public option globals were populated successfully.
## @retval 2 The update invocation is invalid or ambiguous.
## @par Examples
## @code
## __manifest_manager_parse_update_cli --filename dependencies.txt owner/repo v1
## @endcode
__manifest_manager_parse_update_cli() {
  local __mm_filename_count=0 __mm_arg __mm_combined_rest
  local -a __mm_positionals=()

  __manifest_manager_option_filename=dependencies.txt
  __manifest_manager_option_all=0
  __manifest_manager_option_package=''
  __manifest_manager_option_version=''
  __manifest_manager_option_version_supplied=0

  while (($#)); do
    __mm_arg=$1
    case $__mm_arg in
      -a | --all)
        __manifest_manager_option_all=1
        shift
        ;;
      -f | --filename)
        (($# >= 2)) || {
          __manifest_manager_diag "$__mm_arg requires a filename"
          return 2
        }
        ((__mm_filename_count == 0)) || {
          __manifest_manager_diag 'manifest filename was specified more than once'
          return 2
        }
        __manifest_manager_option_filename=$2
        __mm_filename_count=1
        shift 2
        ;;
      --filename=*)
        ((__mm_filename_count == 0)) || {
          __manifest_manager_diag 'manifest filename was specified more than once'
          return 2
        }
        __manifest_manager_option_filename=${__mm_arg#--filename=}
        __mm_filename_count=1
        shift
        ;;
      --)
        shift
        while (($#)); do
          __mm_positionals+=("$1")
          shift
        done
        ;;
      -*)
        __manifest_manager_diag "unknown update option: $__mm_arg"
        return 2
        ;;
      *)
        __mm_positionals+=("$__mm_arg")
        shift
        ;;
    esac
  done

  [[ -n $__manifest_manager_option_filename ]] || {
    __manifest_manager_diag 'manifest filename cannot be empty'
    return 2
  }

  if ((__manifest_manager_option_all)); then
    ((${#__mm_positionals[@]} == 0)) || {
      __manifest_manager_diag '--all cannot be combined with a dependency or version'
      return 2
    }
    return 0
  fi

  if ((${#__mm_positionals[@]} == 1)); then
    if [[ ${__mm_positionals[0]} == *@* ]]; then
      __manifest_manager_option_package=${__mm_positionals[0]%%@*}
      __mm_combined_rest=${__mm_positionals[0]#*@}
      [[ $__mm_combined_rest != *@* ]] || {
        __manifest_manager_diag 'combined dependency form contains more than one @ separator'
        return 2
      }
      __manifest_manager_option_version=$__mm_combined_rest
      __manifest_manager_option_version_supplied=1
    else
      __manifest_manager_option_package=${__mm_positionals[0]}
    fi
  elif ((${#__mm_positionals[@]} == 2)); then
    [[ ${__mm_positionals[0]} != *@* ]] || {
      __manifest_manager_diag 'dependency and separate version cannot also use PACKAGE@VERSION form'
      return 2
    }
    __manifest_manager_option_package=${__mm_positionals[0]}
    __manifest_manager_option_version=${__mm_positionals[1]}
    __manifest_manager_option_version_supplied=1
  else
    __manifest_manager_diag 'update requires one dependency or --all'
    return 2
  fi

  __manifest_manager_validate_package "$__manifest_manager_option_package" || return $?
  if ((__manifest_manager_option_version_supplied)); then
    __manifest_manager_validate_target_tag "$__manifest_manager_option_version" || return $?
  fi
}
