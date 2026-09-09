#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/list.bash
## @brief Implements deterministic read-only manifest identity listing.
## @details
## The `list` command validates the complete selected manifest before emitting
## any output, then writes each complete logical `id` value in manifest order.
## Existing source is never reserialized or mutated.  Stream input is supported
## through `-f -`, but failures do not echo rollback source because STDOUT is
## reserved for list data rather than a transformed manifest.
## @see doc/adr/ADR-021-extend-manifest-manager-with-list-add-and-remove.md
## @see doc/manifest-manager-spec.md
## @par Examples
## @code
## manifest-manager.bash list
## manifest-manager.bash list -f dependencies-build.txt
## manifest-manager.bash list -f - < dependencies.txt
## @endcode

## @var __manifest_manager_list_filename
## @brief Manifest filename selected for the current list invocation.
__manifest_manager_list_filename=dependencies.txt

## @fn __manifest_manager_list_usage()
## @brief Writes complete public help for the `list` subcommand.
## @details
## The help text documents syntax, filename selection, stream semantics, output,
## and the public exit categories relevant to read-only listing.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Human-readable `list` help is written.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Multi-line human-readable help text.
## @retval 0 Help text was written successfully.
## @note A non-zero output status may be propagated if STDOUT cannot be written.
## @par Examples
## @code
## __manifest_manager_list_usage
## @endcode
__manifest_manager_list_usage() {
  cat <<'USAGE'
Usage:
  manifest-manager.bash list [OPTIONS]

Options:
  -f, --filename FILE    Select a manifest; FILE '-' reads STDIN.
  -h, --help             Show this help and exit successfully.
  -V, --version          Show version/build information and exit successfully.

Output:
  The complete validated id value for each dependency is written to STDOUT,
  one identity per line, in manifest order.  An empty valid manifest writes
  nothing.  The complete manifest is validated before the first identity is
  emitted, so invalid input never produces a partial list.

Stream mode:
  With -f -, the complete manifest is read from STDIN and the identity list is
  written to STDOUT.  On failure, no rollback manifest is written because STDOUT
  belongs to list data rather than transformed source.

Exit statuses:
  0  success, help, version, or a valid empty manifest
  2  invalid CLI or manifest
  6  input, staging, filesystem, or output failed
USAGE
}

## @fn __manifest_manager_parse_list_cli()
## @brief Parses `list` options without consuming manifest input.
## @details
## The command accepts only filename and informational options.  Help and version
## are normally intercepted by the public runner before this parser is called;
## encountering them here remains harmless and successful.  Positional arguments
## and unknown options fail closed.
## @param args[] Arguments following the public `list` subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A concise diagnostic is written for invalid command syntax.
## @returns Nothing is written to STDOUT.
## @retval 0 The list CLI is valid.
## @retval 2 The list CLI is invalid.
## @par Examples
## @code
## __manifest_manager_parse_list_cli -f dependencies-build.txt
## @endcode
__manifest_manager_parse_list_cli() {
  local __mm_arg

  __manifest_manager_list_filename=dependencies.txt

  while (($# > 0)); do
    __mm_arg=$1
    case $__mm_arg in
      -f | --filename)
        (($# >= 2)) || {
          __manifest_manager_diag "option requires an argument: $__mm_arg"
          return 2
        }
        __manifest_manager_list_filename=$2
        shift 2
        ;;
      --filename=*)
        __manifest_manager_list_filename=${__mm_arg#*=}
        shift
        ;;
      -h | --help | -V | --version)
        shift
        ;;
      --)
        shift
        (($# == 0)) || {
          __manifest_manager_diag 'list does not accept positional arguments'
          return 2
        }
        ;;
      -*)
        __manifest_manager_diag "unknown list option: $__mm_arg"
        return 2
        ;;
      *)
        __manifest_manager_diag 'list does not accept positional arguments'
        return 2
        ;;
    esac
  done

  [[ -n $__manifest_manager_list_filename ]] || {
    __manifest_manager_diag 'manifest filename cannot be empty'
    return 2
  }
}

## @fn __manifest_manager_emit_identity_list()
## @brief Writes validated complete manifest identities in source order.
## @details
## The parser has already validated the complete manifest before this function is
## called.  Values come directly from the logical `id` fields and are not split,
## normalized, or interpreted as repository coordinates.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## One complete identity value per line is written in manifest order.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Newline-delimited complete manifest identities.
## @retval 0 Every identity was written successfully.
## @retval 6 STDOUT could not be written completely.
## @par Examples
## @code
## __manifest_manager_emit_identity_list
## @endcode
__manifest_manager_emit_identity_list() {
  local __mm_id

  for __mm_id in "${__manifest_manager_ids[@]}"; do
    printf '%s\n' "$__mm_id" || {
      __manifest_manager_diag 'unable to write complete identity list'
      return 6
    }
  done
}

## @fn __manifest_manager_run_list()
## @brief Executes one complete read-only list invocation.
## @details
## Informational options return before staging or input consumption.  The selected
## manifest is then captured in private staging and fully validated before any
## identity is emitted.  Unlike mutation commands, list failures do not reproduce
## source on STDOUT because no transformed-manifest stream contract applies.
## @param args[] Arguments following the public `list` subcommand.
## @par STDIN
## The complete manifest only when `-f -` is selected.
## @par STDOUT
## Help/version text or one complete dependency identity per line.
## @par STDERR
## Diagnostics are written for invalid requests, invalid manifests, and I/O
## failures.
## @returns Informational text or newline-delimited dependency identities.
## @retval 0 The command succeeded.
## @retval 2 The CLI or manifest was invalid.
## @retval 6 Input, staging, filesystem, or output failed.
## @par Examples
## @code
## __manifest_manager_run_list -f dependencies.txt
## @endcode
__manifest_manager_run_list() {
  local __mm_status=0

  if __manifest_manager_args_have_help "$@"; then
    __manifest_manager_list_usage
    return $?
  fi
  if __manifest_manager_args_have_version "$@"; then
    __manifest_manager_version_output
    return $?
  fi

  __manifest_manager_parse_list_cli "$@" || return $?
  __manifest_manager_stage_create || return $?
  trap '__manifest_manager_stage_cleanup >/dev/null 2>&1 || :' EXIT

  if [[ $__manifest_manager_list_filename == - ]]; then
    __manifest_manager_capture_stdin || __mm_status=$?
  else
    __manifest_manager_capture_file "$__manifest_manager_list_filename" || __mm_status=$?
  fi

  if ((__mm_status == 0)); then
    __manifest_manager_parse_manifest "$__manifest_manager_original_file" || __mm_status=$?
  fi
  if ((__mm_status == 0)); then
    __manifest_manager_emit_identity_list || __mm_status=$?
  fi

  __manifest_manager_stage_cleanup >/dev/null 2>&1 || {
    ((__mm_status != 0)) || __mm_status=6
  }
  trap - EXIT
  return "$__mm_status"
}
