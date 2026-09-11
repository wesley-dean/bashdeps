#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/add.bash
## @brief Implements explicit append-only manifest dependency creation.
## @details
## The `add` command accepts exactly one complete declaration through the
## manifest's four required named fields plus an optional explicit `digest_url`
## and appends a canonical one-line record without changing any pre-existing
## manifest byte.  Existing source is parsed and validated first, the new
## declaration is validated against that state, and the complete candidate is
## reparsed before publication.
##
## The command performs no release discovery, network access, artifact-name
## inference, destination inference, digest calculation, or checksum-URL
## inference.  A caller must supply the complete required values explicitly and
## may supply `digest_url=` explicitly when upstream corroboration is desired.
##
## Append preservation is operation-specific under ADR-021.  The candidate must
## equal the captured original byte-for-byte followed only by the deliberately
## constructed separator and canonical record bytes.
## @see doc/adr/ADR-021-extend-manifest-manager-with-list-add-and-remove.md
## @see doc/adr/ADR-023-add-supplemental-upstream-sha256-verification.md
## @see doc/manifest-manager-spec.md
## @par Examples
## @code
## manifest-manager.bash add \
##   id=acme/tool@v1 \
##   url=https://example.test/tool \
##   dest=vendor/tool \
##   digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
##   digest_url=https://example.test/tool.sha256
## @endcode

## @var __manifest_manager_add_filename
## @brief Manifest filename selected for the current add invocation.
__manifest_manager_add_filename=dependencies.txt

## @var __manifest_manager_add_id
## @brief Complete explicit identity value supplied to `add`.
__manifest_manager_add_id=''

## @var __manifest_manager_add_url
## @brief Complete explicit HTTPS URL value supplied to `add`.
__manifest_manager_add_url=''

## @var __manifest_manager_add_dest
## @brief Complete explicit destination value supplied to `add`.
__manifest_manager_add_dest=''

## @var __manifest_manager_add_digest
## @brief Complete explicit `sha256:` digest value supplied to `add`.
__manifest_manager_add_digest=''

## @var __manifest_manager_add_digest_url
## @brief Optional explicit HTTPS checksum URL supplied to `add`.
## @details
## An empty value means the caller did not opt the new record into ADR-023
## acquisition-time corroboration.  The add command never derives this value.
__manifest_manager_add_digest_url=''

## @fn __manifest_manager_add_usage()
## @brief Writes complete public help for the `add` subcommand.
## @details
## The help text documents mandatory explicit fields, the optional checksum URL,
## filename selection, append/newline semantics, transactional stream behavior,
## and the public exit categories relevant to append-only mutation.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Human-readable `add` help is written.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Multi-line human-readable help text.
## @retval 0 Help text was written successfully.
## @note A non-zero output status may be propagated if STDOUT cannot be written.
## @par Examples
## @code
## __manifest_manager_add_usage
## @endcode
__manifest_manager_add_usage() {
  cat <<'USAGE'
Usage:
  manifest-manager.bash add [OPTIONS] \
    id=VALUE url=VALUE dest=VALUE digest=sha256:HEX [digest_url=HTTPS_URL]

Options:
  -f, --filename FILE    Select a manifest; FILE '-' reads STDIN and writes STDOUT.
  -h, --help             Show this help and exit successfully.
  -V, --version          Show version/build information and exit successfully.

Declaration:
  Exactly one each of id=, url=, dest=, and digest= is required.  One optional
  digest_url= may also be supplied.  Field order is arbitrary.  Values are used
  exactly as supplied after manifest validation.  add does not infer URLs,
  checksum URLs, artifact names, destinations, package conventions, or digests,
  and it performs no network access or digest calculation.

Append behavior:
  Existing manifest bytes remain an exact prefix of the candidate.  One canonical
  record is appended at absolute EOF in field order: id, url, dest, digest, then
  digest_url when supplied.  The last observed LF/CRLF line-ending style is reused;
  LF is used when none exists.  A missing final line terminator is supplied before
  the new record.  The new record always ends with the selected line terminator.

Stream mode:
  With -f -, STDIN is captured completely before mutation.  Success writes the
  complete updated manifest to STDOUT.  Failure after capture writes the complete
  original input to STDOUT and returns a non-zero status.  Inspect the exit status.

Exit statuses:
  0  success, help, or version
  2  invalid CLI, manifest, or dependency declaration
  5  append-preservation or candidate-safety check failed
  6  input, staging, filesystem, output, or publication failed
USAGE
}

## @fn __manifest_manager_parse_add_cli()
## @brief Parses one explicit add request without reading manifest input.
## @details
## Exactly one of each required named manifest field is accepted, with at most
## one optional `digest_url`.  Field order is arbitrary and values may contain
## additional `=` characters because each token is split only at its first equals
## sign.  Empty or whitespace-bearing values fail before candidate construction
## so an argument cannot inject another logical or physical manifest token.
## Unknown and duplicate fields fail closed.
## @param args[] Arguments following the public `add` subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A concise diagnostic identifies invalid command or declaration syntax.
## @returns Nothing is written to STDOUT.
## @retval 0 Add option and declaration globals were populated successfully.
## @retval 2 The add invocation is invalid or incomplete.
## @par Examples
## @code
## __manifest_manager_parse_add_cli id=tool@1 url=https://example.test/tool \
##   dest=vendor/tool digest=sha256:0123... \
##   digest_url=https://example.test/tool.sha256
## @endcode
__manifest_manager_parse_add_cli() {
  local __mm_filename_count=0 __mm_arg __mm_name __mm_value
  local __mm_seen_id=0 __mm_seen_url=0 __mm_seen_dest=0 __mm_seen_digest=0
  local __mm_seen_digest_url=0 __mm_options=1

  __manifest_manager_add_filename=dependencies.txt
  __manifest_manager_add_id=''
  __manifest_manager_add_url=''
  __manifest_manager_add_dest=''
  __manifest_manager_add_digest=''
  __manifest_manager_add_digest_url=''

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
          __manifest_manager_add_filename=$2
          __mm_filename_count=1
          shift 2
          continue
          ;;
        --filename=*)
          ((__mm_filename_count == 0)) || {
            __manifest_manager_diag 'manifest filename was specified more than once'
            return 2
          }
          __manifest_manager_add_filename=${__mm_arg#--filename=}
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
          __manifest_manager_diag "unknown add option: $__mm_arg"
          return 2
          ;;
      esac
    fi

    [[ $__mm_arg == *=* ]] || {
      __manifest_manager_diag "add requires named manifest fields: $__mm_arg"
      return 2
    }
    __mm_name=${__mm_arg%%=*}
    __mm_value=${__mm_arg#*=}
    [[ -n $__mm_value && ! $__mm_value =~ [[:space:]] ]] || {
      __manifest_manager_diag "add field is empty or contains whitespace: $__mm_name"
      return 2
    }

    case $__mm_name in
      id)
        ((__mm_seen_id == 0)) || {
          __manifest_manager_diag 'add id field was specified more than once'
          return 2
        }
        __mm_seen_id=1
        __manifest_manager_add_id=$__mm_value
        ;;
      url)
        ((__mm_seen_url == 0)) || {
          __manifest_manager_diag 'add url field was specified more than once'
          return 2
        }
        __mm_seen_url=1
        __manifest_manager_add_url=$__mm_value
        ;;
      dest)
        ((__mm_seen_dest == 0)) || {
          __manifest_manager_diag 'add dest field was specified more than once'
          return 2
        }
        __mm_seen_dest=1
        __manifest_manager_add_dest=$__mm_value
        ;;
      digest)
        ((__mm_seen_digest == 0)) || {
          __manifest_manager_diag 'add digest field was specified more than once'
          return 2
        }
        __mm_seen_digest=1
        __manifest_manager_add_digest=$__mm_value
        ;;
      digest_url)
        ((__mm_seen_digest_url == 0)) || {
          __manifest_manager_diag 'add digest_url field was specified more than once'
          return 2
        }
        __mm_seen_digest_url=1
        __manifest_manager_add_digest_url=$__mm_value
        ;;
      *)
        __manifest_manager_diag "unknown add field: $__mm_name"
        return 2
        ;;
    esac

    shift
  done

  [[ -n $__manifest_manager_add_filename ]] || {
    __manifest_manager_diag 'manifest filename cannot be empty'
    return 2
  }

  ((__mm_seen_id && __mm_seen_url && __mm_seen_dest && __mm_seen_digest)) || {
    __manifest_manager_diag 'add requires exactly one each of id, url, dest, and digest'
    return 2
  }

  [[ $__manifest_manager_add_url == https://* ]] || {
    __manifest_manager_diag 'add url must use HTTPS'
    return 2
  }
  if ((__mm_seen_digest_url)) && [[ $__manifest_manager_add_digest_url != https://* ]]; then
    __manifest_manager_diag 'add digest_url must use HTTPS'
    return 2
  fi
  __manifest_manager_validate_dest_text "$__manifest_manager_add_dest" || {
    __manifest_manager_diag \
      "add destination is invalid: $__manifest_manager_add_dest"
    return 2
  }
  [[ $__manifest_manager_add_digest =~ ^sha256:[0-9a-f]{64}$ ]] || {
    __manifest_manager_diag 'add digest must be sha256: followed by 64 lowercase hexadecimal characters'
    return 2
  }
}

## @fn __manifest_manager_add_detect_layout()
## @brief Determines separator need and line ending for one append operation.
## @details
## The complete captured original is read physically without changing it.  Each
## observed line terminator updates the selected append convention, so the last
## observed LF or CRLF style is reused.  A non-empty source whose last physical
## line lacks a terminator needs one separator before the new record.  When no
## line terminator is observable, including an empty file, LF is selected.
## @param source Captured original manifest path.
## @param eol_output Caller variable receiving LF or CRLF bytes.
## @param separator_output Caller variable receiving `1` when a separator is
## needed, otherwise `0`.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written if the captured manifest cannot be read.
## @returns Nothing is written to STDOUT.
## @retval 0 Append layout was determined.
## @retval 6 The captured manifest could not be read.
## @par Examples
## @code
## __manifest_manager_add_detect_layout "$__manifest_manager_original_file" eol sep
## @endcode
__manifest_manager_add_detect_layout() {
  local __mm_source=$1
  local __mm_eol_output=$2
  local __mm_separator_output=$3
  local __mm_line='' __mm_eol=$'\n' __mm_final_newline=0
  local __mm_separator=0

  exec 4<"$__mm_source" || {
    __manifest_manager_diag "unable to inspect manifest line endings: $__mm_source"
    return 6
  }

  while :; do
    __mm_line=''
    if IFS= read -r __mm_line <&4; then
      __mm_final_newline=1
      if [[ $__mm_line == *$'\r' ]]; then
        __mm_eol=$'\r\n'
      else
        __mm_eol=$'\n'
      fi
    elif [[ -n $__mm_line ]]; then
      __mm_final_newline=0
      break
    else
      break
    fi
  done
  exec 4<&-

  if [[ -s $__mm_source ]] && ((!__mm_final_newline)); then
    __mm_separator=1
  fi

  printf -v "$__mm_eol_output" '%s' "$__mm_eol"
  printf -v "$__mm_separator_output" '%s' "$__mm_separator"
}

## @fn __manifest_manager_add_read_exact_text()
## @brief Reads a losslessly representable manifest file into a caller variable.
## @details
## This helper is used only after manifest lossless-text validation.  It rebuilds
## each physical line including its exact LF byte; any CR byte remains part of the
## line value.  The resulting Bash string therefore preserves CRLF, LF, blank
## lines, and final-newline state exactly for the append proof.  NUL input is not
## representable and is rejected earlier by the shared parser.
## @param source Validated manifest or candidate file to read.
## @param output_name Caller variable receiving exact text bytes.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written if the file cannot be read.
## @returns Nothing is written to STDOUT.
## @retval 0 Exact text was assigned to the caller variable.
## @retval 6 The file could not be read.
## @par Examples
## @code
## __manifest_manager_add_read_exact_text candidate.manifest candidate
## @endcode
__manifest_manager_add_read_exact_text() {
  local __mm_source=$1
  local __mm_output_name=$2
  local __mm_line='' __mm_value=''

  exec 4<"$__mm_source" || {
    __manifest_manager_diag "unable to read append proof input: $__mm_source"
    return 6
  }

  while :; do
    __mm_line=''
    if IFS= read -r __mm_line <&4; then
      __mm_value+="$__mm_line"
      __mm_value+=$'\n'
    elif [[ -n $__mm_line ]]; then
      __mm_value+="$__mm_line"
      break
    else
      break
    fi
  done
  exec 4<&-

  printf -v "$__mm_output_name" '%s' "$__mm_value"
}

## @fn __manifest_manager_add_prove_candidate()
## @brief Proves that candidate bytes equal original bytes plus the exact append.
## @details
## Both files have already satisfied the manager's lossless-text boundary.  This
## helper reconstructs their exact text in Bash variables and compares the
## candidate against the captured original concatenated with only the append bytes
## deliberately constructed by `add`.  Any difference is a preservation failure.
## @param append_bytes Exact separator plus canonical record bytes expected after
## the original manifest.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written if byte-prefix/suffix preservation cannot be proved.
## @returns Nothing is written to STDOUT.
## @retval 0 Candidate bytes exactly equal original bytes plus the expected append.
## @retval 5 Candidate bytes violate the append-only preservation contract.
## @retval 6 Proof input could not be read.
## @par Examples
## @code
## __manifest_manager_add_prove_candidate "$append"
## @endcode
__manifest_manager_add_prove_candidate() {
  local __mm_append=$1
  local __mm_original='' __mm_candidate=''

  __manifest_manager_add_read_exact_text \
    "$__manifest_manager_original_file" __mm_original || return $?
  __manifest_manager_add_read_exact_text \
    "$__manifest_manager_candidate_file" __mm_candidate || return $?

  [[ $__mm_candidate == "$__mm_original$__mm_append" ]] || {
    __manifest_manager_diag \
      'candidate manifest failed exact append-only preservation proof'
    return 5
  }
}

## @fn __manifest_manager_add_transaction()
## @brief Builds and validates one complete append-only candidate manifest.
## @details
## The captured original is parsed first.  The canonical new logical record is
## then validated through the shared record parser against existing identity and
## destination uniqueness state.  Candidate construction copies the complete
## original bytes first and appends only the selected separator and canonical
## record.  The exact append relationship is proved and the complete candidate is
## reparsed before any caller-visible output or publication.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Diagnostics identify invalid declarations, preservation failures, or staging
## errors.
## @returns Nothing is written to STDOUT.
## @retval 0 A complete validated append candidate is ready.
## @retval 2 The original manifest or supplied declaration is invalid.
## @retval 5 Append-only preservation or candidate safety validation failed.
## @retval 6 Staging or file I/O failed.
## @par Examples
## @code
## __manifest_manager_add_transaction
## @endcode
__manifest_manager_add_transaction() {
  local __mm_record __mm_append='' __mm_status
  local __mm_selected_eol __mm_needs_separator

  __manifest_manager_parse_manifest "$__manifest_manager_original_file" || return $?

  printf -v __mm_record 'id=%s url=%s dest=%s digest=%s' \
    "$__manifest_manager_add_id" \
    "$__manifest_manager_add_url" \
    "$__manifest_manager_add_dest" \
    "$__manifest_manager_add_digest"
  if [[ -n $__manifest_manager_add_digest_url ]]; then
    __mm_record+=" digest_url=$__manifest_manager_add_digest_url"
  fi

  __manifest_manager_parse_record "$__mm_record" || return $?
  __manifest_manager_add_detect_layout \
    "$__manifest_manager_original_file" \
    __mm_selected_eol __mm_needs_separator || return $?

  if ((__mm_needs_separator)); then
    __mm_append+="$__mm_selected_eol"
  fi
  __mm_append+="$__mm_record$__mm_selected_eol"

  cat "$__manifest_manager_original_file" >"$__manifest_manager_candidate_file" || {
    __manifest_manager_diag 'unable to stage original bytes for add candidate'
    return 6
  }
  printf '%s' "$__mm_append" >>"$__manifest_manager_candidate_file" || {
    __manifest_manager_diag 'unable to append dependency declaration to candidate'
    return 6
  }

  __manifest_manager_add_prove_candidate "$__mm_append" || return $?

  if __manifest_manager_parse_manifest "$__manifest_manager_candidate_file"; then
    return 0
  else
    __mm_status=$?
  fi

  if ((__mm_status == 2)); then
    __manifest_manager_diag \
      'candidate manifest became invalid after append-only mutation'
    return 5
  fi
  return "$__mm_status"
}

## @fn __manifest_manager_run_add()
## @brief Executes one complete add invocation including transactional I/O.
## @details
## Help and version return before staging or input consumption.  Recognizable
## stream mode captures STDIN before full CLI parsing so later invalid arguments
## can reproduce the original bytes, matching ADR-020's mutating stream contract.
## File mode parses arguments before capturing the selected manifest.  A validated
## add candidate then uses the shared manager publication/output helpers.
## @param args[] Arguments following the public `add` subcommand.
## @par STDIN
## The complete manifest only when `-f -` stream mode is selected.
## @par STDOUT
## Help/version text, a complete transactional manifest in stream mode, or
## nothing for ordinary successful file-mode operation.
## @par STDERR
## Diagnostics are written for invalid requests and failed add operations.
## @returns Informational text, a stream manifest, or no data by mode.
## @retval 0 The operation succeeded.
## @retval 2 The CLI, manifest, or declaration was invalid.
## @retval 5 Append preservation or candidate validation failed.
## @retval 6 Input, staging, filesystem, output, or publication failed.
## @par Examples
## @code
## __manifest_manager_run_add id=tool@1 url=https://example.test/tool \
##   dest=vendor/tool digest=sha256:0123...
## @endcode
__manifest_manager_run_add() {
  local __mm_status=0 __mm_stream_hint=0

  if __manifest_manager_args_have_help "$@"; then
    __manifest_manager_add_usage
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

  if __manifest_manager_parse_add_cli "$@"; then
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

  if [[ $__manifest_manager_add_filename == - ]]; then
    if ((!__manifest_manager_stream_mode)); then
      __manifest_manager_diag 'unable to establish transactional stream mode'
      __mm_status=2
    fi
  else
    __manifest_manager_stream_mode=0
    __manifest_manager_capture_file "$__manifest_manager_add_filename" || __mm_status=$?
  fi

  if ((__mm_status == 0)); then
    __manifest_manager_add_transaction || __mm_status=$?
  fi

  if ((__manifest_manager_stream_mode)); then
    __manifest_manager_stream_emit "$__mm_status"
    __mm_status=$?
  elif ((__mm_status == 0)); then
    __manifest_manager_publish_file "$__manifest_manager_add_filename" || __mm_status=$?
  fi

  __manifest_manager_stage_cleanup >/dev/null 2>&1 || {
    ((__mm_status != 0)) || __mm_status=6
  }
  trap - EXIT
  return "$__mm_status"
}
