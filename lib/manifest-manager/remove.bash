#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/remove.bash
## @brief Implements exact-identity manifest dependency removal.
## @details
## The `remove` command selects one complete logical `id` value and deletes only
## the raw physical source chunk that belongs to that dependency record.  The
## parser already retains dependency records, comments, and blank lines as
## independent chunks, so removal can preserve every unrelated byte without
## assigning ownership to nearby comments or whitespace.
##
## The candidate is generated from the validated chunk sequence with exactly one
## selected record omitted.  An operation-specific proof reconstructs the
## original from all chunks, independently reconstructs the expected candidate
## with one omission, compares both byte-for-byte, and reparses the candidate
## before publication.
##
## `remove` performs no provider interpretation, release discovery, network
## access, artifact retrieval, digest calculation, or package-prefix matching.
## The supplied identity is opaque and must match one complete manifest `id`
## exactly.
## @see doc/adr/ADR-021-extend-manifest-manager-with-list-add-and-remove.md
## @see doc/manifest-manager-spec.md
## @par Examples
## @code
## manifest-manager.bash remove acme/tool@v1
## manifest-manager.bash remove -f dependencies-docs.txt acme/filter@v2
## @endcode

## @var __manifest_manager_remove_filename
## @brief Manifest filename selected for the current remove invocation.
__manifest_manager_remove_filename=dependencies.txt

## @var __manifest_manager_remove_id
## @brief Complete opaque identity requested for exact removal.
__manifest_manager_remove_id=''

## @var __manifest_manager_remove_record_index
## @brief Logical record index selected for the current removal transaction.
__manifest_manager_remove_record_index=-1

## @fn __manifest_manager_remove_usage()
## @brief Writes complete public help for the `remove` subcommand.
## @details
## The help text documents exact complete-identity selection, filename behavior,
## comment/blank-line preservation, transactional stream rollback, and the
## public exit categories relevant to removal.
##
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Human-readable `remove` help is written.
## @par STDERR
## Nothing is intentionally written to STDERR.
##
## @returns Multi-line human-readable help text.
## @retval 0 Help text was written successfully.
## @note A non-zero output status may be propagated if STDOUT cannot be written.
##
## @par Examples
## @code
## __manifest_manager_remove_usage
## @endcode
__manifest_manager_remove_usage() {
  cat <<'USAGE'
Usage:
  manifest-manager.bash remove [OPTIONS] ID

Options:
  -f, --filename FILE    Select a manifest; FILE '-' reads STDIN and writes STDOUT.
  -h, --help             Show this help and exit successfully.
  -V, --version          Show version/build information and exit successfully.

Selection:
  ID is the complete logical id= value and must match exactly one dependency.
  remove does not strip versions or interpret ID as a GitHub package prefix.

Removal behavior:
  Exactly the selected logical record's physical source bytes are deleted,
  including its continuation lines and its own line terminator when present.
  Adjacent comments and blank lines remain independent and unchanged.
  Every remaining source byte is preserved exactly.

Stream mode:
  With -f -, STDIN is captured completely before mutation.  Success writes the
  complete updated manifest to STDOUT.  Failure after capture writes the complete
  original input to STDOUT and returns a non-zero status.  Inspect the exit status.

Exit statuses:
  0  success, help, or version
  2  invalid CLI, manifest, or dependency selection
  5  exact-removal or preservation safety check failed
  6  input, staging, filesystem, output, or publication failed
USAGE
}

## @fn __manifest_manager_parse_remove_cli()
## @brief Parses one exact-identity removal request without reading manifest data.
## @details
## The parser accepts the shared filename option and exactly one positional
## complete identity.  The identity remains opaque; only empty and
## whitespace-bearing values are rejected at CLI parsing time.  Provider,
## package, version, and tag syntax are deliberately not interpreted.
##
## Help and version are handled before this function so recognized `-f -`
## invocations can preserve informational no-input behavior.
##
## @param args[] Arguments following the public `remove` subcommand.
##
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A concise diagnostic identifies invalid command syntax.
##
## @returns Nothing is written to STDOUT.
## @retval 0 Remove option and identity globals were populated successfully.
## @retval 2 The remove invocation is invalid or ambiguous.
##
## @par Examples
## @code
## __manifest_manager_parse_remove_cli -f dependencies.txt acme/tool@v1
## @endcode
__manifest_manager_parse_remove_cli() {
  local __mm_filename_count=0 __mm_arg __mm_options=1
  local -a __mm_positionals=()

  __manifest_manager_remove_filename=dependencies.txt
  __manifest_manager_remove_id=''
  __manifest_manager_remove_record_index=-1

  while (($#)); do
    __mm_arg=$1

    if ((__mm_options)); then
      case $__mm_arg in
        -f | --filename)
          (($# >= 2)) || {
            __manifest_manager_diag "$__mm_arg requires a filename"
            return 2
          }
          ((__mm_filename_count == 0)) || {
            __manifest_manager_diag 'manifest filename was specified more than once'
            return 2
          }
          __manifest_manager_remove_filename=$2
          __mm_filename_count=1
          shift 2
          continue
          ;;
        --filename=*)
          ((__mm_filename_count == 0)) || {
            __manifest_manager_diag 'manifest filename was specified more than once'
            return 2
          }
          __manifest_manager_remove_filename=${__mm_arg#--filename=}
          __mm_filename_count=1
          shift
          continue
          ;;
        -h | --help | -V | --version)
          shift
          continue
          ;;
        --)
          __mm_options=0
          shift
          continue
          ;;
        -*)
          __manifest_manager_diag "unknown remove option: $__mm_arg"
          return 2
          ;;
      esac
    fi

    __mm_positionals+=("$__mm_arg")
    shift
  done

  [[ -n $__manifest_manager_remove_filename ]] || {
    __manifest_manager_diag 'manifest filename cannot be empty'
    return 2
  }

  ((${#__mm_positionals[@]} == 1)) || {
    __manifest_manager_diag 'remove requires exactly one complete dependency identity'
    return 2
  }

  __manifest_manager_remove_id=${__mm_positionals[0]}
  [[ -n $__manifest_manager_remove_id && \
    ! $__manifest_manager_remove_id =~ [[:space:]] ]] || {
    __manifest_manager_diag 'remove identity cannot be empty or contain whitespace'
    return 2
  }
}

## @fn __manifest_manager_select_remove_record()
## @brief Selects exactly one parsed record by complete opaque identity.
## @details
## Every parsed `id` is compared byte-for-byte with the requested identity.
## Package prefixes, `@` separators, semantic versions, and hosting providers
## have no special meaning.  The manifest parser already rejects duplicate IDs,
## but this helper still counts matches defensively and requires exactly one.
##
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies zero or unexpectedly multiple exact matches.
##
## @returns Nothing is written to STDOUT.
## @retval 0 Exactly one logical record was selected.
## @retval 2 The requested complete identity did not select exactly one record.
##
## @par Examples
## @code
## __manifest_manager_select_remove_record
## @endcode
__manifest_manager_select_remove_record() {
  local __mm_index __mm_matches=0

  __manifest_manager_remove_record_index=-1
  for __mm_index in "${!__manifest_manager_ids[@]}"; do
    [[ ${__manifest_manager_ids[__mm_index]} == \
      "$__manifest_manager_remove_id" ]] || continue
    __manifest_manager_remove_record_index=$__mm_index
    __mm_matches=$((__mm_matches + 1))
  done

  ((__mm_matches == 1)) || {
    if ((__mm_matches == 0)); then
      __manifest_manager_diag \
        "dependency identity was not found: $__manifest_manager_remove_id"
    else
      __manifest_manager_diag \
        "dependency identity is not unique: $__manifest_manager_remove_id"
    fi
    return 2
  }
}

## @fn __manifest_manager_emit_remove_candidate()
## @brief Emits all parsed source chunks except the selected dependency record.
## @details
## The parser represents comments and blank lines as independent literal chunks
## and each logical dependency as one record chunk containing all of its physical
## continuation lines.  Candidate generation copies every chunk exactly except
## the one record whose logical index matches the removal selection.
##
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies candidate staging failure.
##
## @returns Nothing is written to STDOUT.
## @retval 0 The complete candidate was staged.
## @retval 6 Candidate staging or write I/O failed.
##
## @par Examples
## @code
## __manifest_manager_emit_remove_candidate
## @endcode
__manifest_manager_emit_remove_candidate() {
  local __mm_chunk

  : >"$__manifest_manager_candidate_file" || {
    __manifest_manager_diag 'unable to initialize remove candidate staging'
    return 6
  }

  for __mm_chunk in "${!__manifest_manager_chunk_values[@]}"; do
    if [[ ${__manifest_manager_chunk_kinds[__mm_chunk]} == record && \
      ${__manifest_manager_chunk_records[__mm_chunk]} -eq \
      $__manifest_manager_remove_record_index ]]; then
      continue
    fi

    printf '%s' "${__manifest_manager_chunk_values[__mm_chunk]}" \
      >>"$__manifest_manager_candidate_file" || {
      __manifest_manager_diag 'unable to write remove candidate manifest'
      return 6
    }
  done
}

## @fn __manifest_manager_prove_remove_candidate()
## @brief Proves exact chunk preservation around one omitted record.
## @details
## The proof reconstructs the original manifest independently from every parsed
## source chunk and requires byte-for-byte equality with the captured input.  It
## simultaneously constructs an expected candidate from the same ordered chunk
## sequence while omitting only the selected record chunk, requires exactly one
## omission, verifies that omitted bytes equal the parser's raw record bytes,
## and compares the expected candidate with the staged candidate.
##
## This proves both that the parser's chunk model represents the complete source
## exactly and that candidate generation removed only the requested physical
## record chunk.  It does not infer ownership of adjacent comments or whitespace.
##
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies a chunk-model or candidate-preservation failure.
##
## @returns Nothing is written to STDOUT.
## @retval 0 The exact one-record omission relationship was proved.
## @retval 5 The source reconstruction, omission, or candidate comparison failed.
## @retval 6 Proof staging or write I/O failed.
##
## @par Examples
## @code
## __manifest_manager_prove_remove_candidate
## @endcode
__manifest_manager_prove_remove_candidate() {
  local __mm_reconstructed=$__manifest_manager_stage_dir/remove.original.proof
  local __mm_expected=$__manifest_manager_stage_dir/remove.candidate.proof
  local __mm_chunk __mm_omissions=0

  : >"$__mm_reconstructed" || return 6
  : >"$__mm_expected" || return 6

  for __mm_chunk in "${!__manifest_manager_chunk_values[@]}"; do
    printf '%s' "${__manifest_manager_chunk_values[__mm_chunk]}" \
      >>"$__mm_reconstructed" || return 6

    if [[ ${__manifest_manager_chunk_kinds[__mm_chunk]} == record && \
      ${__manifest_manager_chunk_records[__mm_chunk]} -eq \
      $__manifest_manager_remove_record_index ]]; then
      __mm_omissions=$((__mm_omissions + 1))
      [[ ${__manifest_manager_chunk_values[__mm_chunk]} == \
        "${__manifest_manager_raw_records[__manifest_manager_remove_record_index]}" ]] || {
        __manifest_manager_diag \
          'selected record chunk does not match retained raw record bytes'
        return 5
      }
      continue
    fi

    printf '%s' "${__manifest_manager_chunk_values[__mm_chunk]}" \
      >>"$__mm_expected" || return 6
  done

  ((__mm_omissions == 1)) || {
    __manifest_manager_diag \
      'remove preservation proof did not identify exactly one record chunk'
    return 5
  }

  if ! cmp -s "$__manifest_manager_original_file" "$__mm_reconstructed"; then
    __manifest_manager_diag \
      'parsed chunk sequence does not reconstruct the original manifest'
    return 5
  fi

  if ! cmp -s "$__manifest_manager_candidate_file" "$__mm_expected"; then
    __manifest_manager_diag \
      'candidate manifest failed exact one-record removal proof'
    return 5
  fi
}

## @fn __manifest_manager_remove_transaction()
## @brief Builds, proves, and validates one exact-record removal candidate.
## @details
## The complete captured original is parsed first so malformed manifests and
## duplicate identities fail before selection.  One exact complete ID is then
## selected, the corresponding raw record chunk is omitted, and the
## operation-specific preservation proof verifies both source reconstruction and
## candidate bytes.  The complete candidate is reparsed before publication.
##
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Diagnostics identify invalid manifests, missing selection, preservation
## failures, or candidate validation failures.
##
## @returns Nothing is written to STDOUT.
## @retval 0 A complete validated removal candidate is ready.
## @retval 2 The original manifest or dependency selection is invalid.
## @retval 5 Exact-removal preservation or candidate safety validation failed.
## @retval 6 Staging or file I/O failed.
##
## @par Examples
## @code
## __manifest_manager_remove_transaction
## @endcode
__manifest_manager_remove_transaction() {
  local __mm_status

  __manifest_manager_parse_manifest "$__manifest_manager_original_file" || return $?
  __manifest_manager_select_remove_record || return $?
  __manifest_manager_emit_remove_candidate || return $?
  __manifest_manager_prove_remove_candidate || return $?

  if __manifest_manager_parse_manifest "$__manifest_manager_candidate_file"; then
    return 0
  else
    __mm_status=$?
  fi

  if ((__mm_status == 2)); then
    __manifest_manager_diag \
      'candidate manifest became invalid after exact record removal'
    return 5
  fi
  return "$__mm_status"
}

## @fn __manifest_manager_run_remove()
## @brief Executes one complete remove invocation including transactional I/O.
## @details
## Help and version return before staging or input consumption.  Recognizable
## stream mode captures STDIN before full CLI parsing so later invalid arguments
## can reproduce the original bytes, matching the mutating stream contract from
## ADR-020 and ADR-021.  File mode parses arguments before capturing the selected
## manifest.  Candidate publication uses the shared transaction helpers.
##
## @param args[] Arguments following the public `remove` subcommand.
##
## @par STDIN
## The complete manifest only when `-f -` stream mode is selected.
## @par STDOUT
## Help/version text, a complete transactional manifest in stream mode, or
## nothing for ordinary successful file-mode operation.
## @par STDERR
## Diagnostics are written for invalid requests and failed removal operations.
##
## @returns Informational text, a stream manifest, or no data by mode.
## @retval 0 The operation succeeded.
## @retval 2 The CLI, manifest, or dependency selection was invalid.
## @retval 5 Exact-removal preservation or candidate validation failed.
## @retval 6 Input, staging, filesystem, output, or publication failed.
##
## @par Examples
## @code
## __manifest_manager_run_remove acme/tool@v1
## @endcode
__manifest_manager_run_remove() {
  local __mm_status=0 __mm_stream_hint=0

  if __manifest_manager_args_have_help "$@"; then
    __manifest_manager_remove_usage
    return $?
  fi
  if __manifest_manager_args_have_version "$@"; then
    __manifest_manager_version_output
    return $?
  fi
  if __manifest_manager_args_have_stream_filename "$@"; then
    __mm_stream_hint=1
  fi

  __manifest_manager_stage_create || return $?
  trap '__manifest_manager_stage_cleanup >/dev/null 2>&1 || :' EXIT

  if ((__mm_stream_hint)); then
    __manifest_manager_stream_mode=1
    __manifest_manager_capture_stdin || {
      __mm_status=$?
      __manifest_manager_stage_cleanup >/dev/null 2>&1 || :
      trap - EXIT
      return "$__mm_status"
    }
  else
    __manifest_manager_stream_mode=0
  fi

  if __manifest_manager_parse_remove_cli "$@"; then
    :
  else
    __mm_status=$?
    if ((__manifest_manager_stream_mode)); then
      __manifest_manager_stream_emit "$__mm_status"
      __mm_status=$?
    fi
    __manifest_manager_stage_cleanup >/dev/null 2>&1 || :
    trap - EXIT
    return "$__mm_status"
  fi

  if [[ $__manifest_manager_remove_filename == - ]]; then
    if ((!__manifest_manager_stream_mode)); then
      __manifest_manager_diag 'unable to establish transactional stream mode'
      __mm_status=2
    fi
  else
    __manifest_manager_stream_mode=0
    __manifest_manager_capture_file "$__manifest_manager_remove_filename" || \
      __mm_status=$?
  fi

  if ((__mm_status == 0)); then
    __manifest_manager_remove_transaction || __mm_status=$?
  fi

  if ((__manifest_manager_stream_mode)); then
    __manifest_manager_stream_emit "$__mm_status"
    __mm_status=$?
  elif ((__mm_status == 0)); then
    __manifest_manager_publish_file "$__manifest_manager_remove_filename" || \
      __mm_status=$?
  fi

  __manifest_manager_stage_cleanup >/dev/null 2>&1 || {
    ((__mm_status != 0)) || __mm_status=6
  }
  trap - EXIT
  return "$__mm_status"
}
