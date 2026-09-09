#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/transaction.bash
## @brief Shares command lifecycle helpers without generalizing mutation proofs.
## @details
## This module owns command-agnostic argument pre-scans used by multiple
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
