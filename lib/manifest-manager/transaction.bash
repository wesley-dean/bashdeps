#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/transaction.bash
## @brief Shares command lifecycle and publication helpers across manager commands.
## @details
## This module owns command-agnostic argument pre-scans plus the file-publication
## and transactional stream-emission boundary shared by mutating
## manifest-manager subcommands.  It deliberately does not own record mutation
## or preservation logic: each mutating command retains the proof appropriate to
## its operation under ADR-020 and ADR-021.
## @see doc/adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md
## @see doc/adr/ADR-021-extend-manifest-manager-with-list-add-and-remove.md
## @par Examples
## @code
## __manifest_manager_args_have_help "$@"
## @endcode

## @fn __manifest_manager_args_have_help()
## @brief Tests whether command arguments request informational help output.
## @details
## Help is recognized before any possible STDIN capture so informational
## invocations never consume a manifest stream merely because `-f -` also
## appears in the argument vector.
## @param args[] Arguments following a manifest-manager subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 At least one `-h` or `--help` argument is present.
## @retval 1 No help option is present.
## @par Examples
## @code
## if __manifest_manager_args_have_help "$@"; then usage_function; fi
## @endcode
__manifest_manager_args_have_help() {
  local __mm_arg

  for __mm_arg in "$@"; do
    [[ $__mm_arg == -h || $__mm_arg == --help ]] && return 0
  done
  return 1
}

## @fn __manifest_manager_args_have_version()
## @brief Tests whether command arguments request version information.
## @details
## Version output, like help, is detected before stream capture so `-f -` does
## not turn an informational invocation into a manifest read.
## @param args[] Arguments following a manifest-manager subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 At least one `-V` or `--version` argument is present.
## @retval 1 No version option is present.
## @par Examples
## @code
## __manifest_manager_args_have_version "$@"
## @endcode
__manifest_manager_args_have_version() {
  local __mm_arg

  for __mm_arg in "$@"; do
    [[ $__mm_arg == -V || $__mm_arg == --version ]] && return 0
  done
  return 1
}

## @fn __manifest_manager_args_have_stream_filename()
## @brief Detects an unambiguous `-f -` or `--filename -` request.
## @details
## Mutating commands need this pre-scan before full CLI parsing so they can
## capture STDIN early enough to reproduce the original input after a later CLI
## failure.  Read-only commands may use the same detector for consistent syntax.
## @param args[] Arguments following a manifest-manager subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 A recognizable stream filename request is present.
## @retval 1 No recognizable stream filename request is present.
## @par Examples
## @code
## __manifest_manager_args_have_stream_filename -f -
## @endcode
__manifest_manager_args_have_stream_filename() {
  local __mm_previous='' __mm_arg

  for __mm_arg in "$@"; do
    if [[ ($__mm_previous == -f || $__mm_previous == --filename) && $__mm_arg == - ]]; then
      return 0
    fi
    [[ $__mm_arg == --filename=- ]] && return 0
    __mm_previous=$__mm_arg
  done
  return 1
}

## @fn __manifest_manager_publish_file()
## @brief Publishes one validated candidate by staged same-directory replacement.
## @details
## A successful no-op leaves the manifest path untouched.  Otherwise the helper
## rejects a symlink introduced since capture, compares current bytes with the
## captured original to detect ordinary concurrent edits, creates a temporary
## file beside the destination, attempts to preserve existing metadata with
## `cp -p`, overwrites only that temporary file with candidate bytes, and renames
## it into place after the complete command transaction has succeeded.
## @param manifest Original manifest path selected by the caller.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies concurrent modification or publication failure.
## @returns Nothing is written to STDOUT.
## @retval 0 The candidate was atomically published or was an unchanged no-op.
## @retval 6 Filesystem safety, staging, or publication failed.
## @par Examples
## @code
## __manifest_manager_publish_file dependencies.txt
## @endcode
__manifest_manager_publish_file() {
  local __mm_manifest=$1
  local __mm_dir __mm_base __mm_tmp

  if cmp -s "$__manifest_manager_original_file" "$__manifest_manager_candidate_file"; then
    return 0
  fi

  [[ ! -L $__mm_manifest ]] || {
    __manifest_manager_diag "manifest became a symbolic link before publication: $__mm_manifest"
    return 6
  }
  if ! cmp -s "$__mm_manifest" "$__manifest_manager_original_file"; then
    __manifest_manager_diag "manifest changed concurrently; refusing to overwrite: $__mm_manifest"
    return 6
  fi

  if [[ $__mm_manifest == */* ]]; then
    __mm_dir=${__mm_manifest%/*}
    [[ -n $__mm_dir ]] || __mm_dir=/
  else
    __mm_dir=.
  fi
  __mm_base=${__mm_manifest##*/}
  __mm_tmp=$(mktemp "$__mm_dir/.${__mm_base}.manifest-manager.XXXXXX") || {
    __manifest_manager_diag "unable to create adjacent publication staging for: $__mm_manifest"
    return 6
  }

  if ! cp -p "$__mm_manifest" "$__mm_tmp" 2>/dev/null; then
    cp "$__mm_manifest" "$__mm_tmp" || {
      rm -f "$__mm_tmp"
      __manifest_manager_diag "unable to prepare publication metadata for: $__mm_manifest"
      return 6
    }
  fi
  cat "$__manifest_manager_candidate_file" >"$__mm_tmp" || {
    rm -f "$__mm_tmp"
    __manifest_manager_diag "unable to write candidate manifest beside: $__mm_manifest"
    return 6
  }
  mv "$__mm_tmp" "$__mm_manifest" || {
    rm -f "$__mm_tmp"
    __manifest_manager_diag "unable to publish candidate manifest: $__mm_manifest"
    return 6
  }
}

## @fn __manifest_manager_stream_emit()
## @brief Emits the transactional stream result for one completed mutation.
## @details
## Status zero emits the complete validated candidate.  Any non-zero mutation
## status emits the complete captured original instead, preserving caller
## content after a failed transformation.  If output itself fails, status 6
## replaces the incoming status because the downstream consumer can no longer be
## guaranteed a complete representation.
## @param status Mutation status whose success or failure selects the output.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Exactly one complete candidate on success or captured original on failure.
## @par STDERR
## A diagnostic is written only if the selected complete stream cannot be
## emitted.
## @returns One complete manifest byte stream when output succeeds.
## @retval 0 The successful candidate was emitted completely.
## @retval 6 The selected manifest could not be emitted completely.
## @note When the original failure status is non-zero and rollback output
## succeeds, that original public status is returned unchanged.
## @par Examples
## @code
## __manifest_manager_stream_emit 0 > dependencies.new.txt
## @endcode
__manifest_manager_stream_emit() {
  local __mm_status=$1
  local __mm_source

  if ((__mm_status == 0)); then
    __mm_source=$__manifest_manager_candidate_file
  else
    __mm_source=$__manifest_manager_original_file
  fi

  if ! cat "$__mm_source"; then
    __manifest_manager_diag 'unable to emit complete transactional manifest stream'
    return 6
  fi
  return "$__mm_status"
}
