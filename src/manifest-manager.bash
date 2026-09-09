#!/usr/bin/env bash
# shellcheck shell=bash
## @file src/manifest-manager.bash
## @brief Maintains existing bashdeps manifests through transactional updates.
## @details
## `manifest-manager.bash` is a maintainer-side companion to `bashdeps.bash`. It
## prepares deliberate source changes to existing dependency declarations by
## coordinating an identity tag, immutable GitHub artifact URL, and SHA-256
## digest while preserving every unrelated manifest byte.
##
## The executable is intentionally separate from the bashdeps synchronization
## runtime.  It may discover GitHub's latest release and calculate proposed
## trust data, while `bashdeps.bash` continues to consume only already-reviewed
## manifest declarations.  The initial public mutation subcommand is `update`.
##
## Maintained source loads manager-only implementation modules from
## `lib/manifest-manager/`.  Release assembly incorporates that explicit source
## closure into each generated manager artifact and removes the repository-only
## import block.  No manager module is incorporated into `bashdeps.bash`.
## @note The public interface is this executable CLI.  Private functions
## beginning with `__manifest_manager_` are not a supported sourceable API.
## @warning A successful update proposes new trusted bytes in repository source.
## Review and commit of that source change remain the authorization boundary.
## @see doc/manifest-manager-spec.md
## @see doc/adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md
## @par Examples
## @code
## manifest-manager.bash update wesley-dean/bash-doxygen
## manifest-manager.bash update -f - wesley-dean/bash-doxygen \
##   v0.0.14 < dependencies.txt
## @endcode

# BEGIN MANIFEST_MANAGER_SOURCE_IMPORTS
__manifest_manager_source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=lib/manifest-manager/state.bash
source "$__manifest_manager_source_root/lib/manifest-manager/state.bash"
# shellcheck source=lib/manifest-manager/manifest.bash
source "$__manifest_manager_source_root/lib/manifest-manager/manifest.bash"
# shellcheck source=lib/manifest-manager/github.bash
source "$__manifest_manager_source_root/lib/manifest-manager/github.bash"
# shellcheck source=lib/manifest-manager/update.bash
source "$__manifest_manager_source_root/lib/manifest-manager/update.bash"
unset __manifest_manager_source_root
# END MANIFEST_MANAGER_SOURCE_IMPORTS

## @var __manifest_manager_version
## @brief Shared bashdeps project version reported by the manager executable.
__manifest_manager_version=${__manifest_manager_version:-0.0.0-dev}

## @var __manifest_manager_build_date
## @brief Source revision date injected into generated manager artifacts.
__manifest_manager_build_date=${__manifest_manager_build_date:-unknown}

## @var __manifest_manager_build_commit
## @brief Source commit identifier injected into generated manager artifacts.
__manifest_manager_build_commit=${__manifest_manager_build_commit:-unknown}

## @fn __manifest_manager_usage()
## @brief Writes the complete supported manifest-manager CLI surface to STDOUT.
## @details
## Help documents the `update` forms, option meanings, omitted-version behavior,
## transactional stream rollback rule, and stable public exit categories.  The
## function is used only for explicit help so operational diagnostics can remain
## confined to STDERR.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Human-readable public CLI help is written.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Multi-line human-readable help text.
## @retval 0 Help text was written successfully.
## @note A non-zero `printf` status may be propagated if STDOUT cannot be
## written.
## @par Examples
## @code
## __manifest_manager_usage
## @endcode
__manifest_manager_usage() {
  cat <<'USAGE'
Usage:
  manifest-manager.bash update [OPTIONS] ID [VERSION]
  manifest-manager.bash update [OPTIONS] ID@VERSION
  manifest-manager.bash update [OPTIONS] --all
  manifest-manager.bash help
  manifest-manager.bash version

Update options:
  -a, --all              Update every declared dependency to its GitHub latest release.
  -f, --filename FILE    Select a manifest; FILE '-' reads STDIN and writes STDOUT.
  -h, --help             Show this help and exit successfully.
  -V, --version          Show version/build information and exit successfully.

Version selection:
  Omitting VERSION uses GitHub's canonical latest release.  An explicit VERSION
  is used exactly as supplied; the literal word 'latest' has no special meaning.

Stream mode:
  With -f -, STDIN is captured completely before update work.  Success writes the
  complete updated manifest to STDOUT.  Failure after capture writes the complete
  original input to STDOUT and returns a non-zero status.  Inspect the exit status.

Exit statuses:
  0  success, help, version, or successful no-op
  2  invalid CLI, manifest, dependency selection, or update declaration
  3  required runtime capability unavailable or unusable
  4  latest-release discovery or network acquisition failed
  5  exact-substitution or preservation safety check failed
  6  input, staging, filesystem, or publication failed
USAGE
}

## @fn __manifest_manager_version_output()
## @brief Writes manager identity and shared release metadata to STDOUT.
## @details
## Both bashdeps repository executables share one project version, source
## revision date, and source commit for a release.  The first line identifies
## this product specifically as `manifest-manager.bash`.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Executable name/version followed by build date and commit metadata is
## written.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Three newline-delimited version/build metadata lines.
## @retval 0 Version metadata was written successfully.
## @note A non-zero `printf` status may be propagated if STDOUT cannot be
## written.
## @par Examples
## @code
## __manifest_manager_version_output
## @endcode
__manifest_manager_version_output() {
  printf 'manifest-manager.bash %s\nbuild_date=%s\ncommit=%s\n' \
    "$__manifest_manager_version" \
    "$__manifest_manager_build_date" \
    "$__manifest_manager_build_commit"
}

## @fn __manifest_manager_update_has_help()
## @brief Tests whether update arguments request informational help output.
## @details
## Help is recognized before stream capture so `update -f - --help` does not
## consume STDIN merely because a stream filename is also present.
## @param args[] Arguments following the `update` subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 At least one `-h` or `--help` argument is present.
## @retval 1 No update help option is present.
## @par Examples
## @code
## if __manifest_manager_update_has_help "$@"; then __manifest_manager_usage; fi
## @endcode
__manifest_manager_update_has_help() {
  local __mm_arg
  for __mm_arg in "$@"; do
    [[ $__mm_arg == -h || $__mm_arg == --help ]] && return 0
  done
  return 1
}

## @fn __manifest_manager_update_has_version()
## @brief Tests whether update arguments request informational version output.
## @details
## Version is recognized before stream capture for the same reason as help:
## informational operations do not consume STDIN even if `-f -` is also present.
## @param args[] Arguments following the `update` subcommand.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 At least one `-V` or `--version` argument is present.
## @retval 1 No update version option is present.
## @par Examples
## @code
## if __manifest_manager_update_has_version "$@"; then \
##   __manifest_manager_version_output
## fi
## @endcode
__manifest_manager_update_has_version() {
  local __mm_arg
  for __mm_arg in "$@"; do
    [[ $__mm_arg == -V || $__mm_arg == --version ]] && return 0
  done
  return 1
}

## @fn __manifest_manager_update_has_stream_hint()
## @brief Detects whether raw update arguments unambiguously request filename
## `-`.
## @details
## Stream rollback applies to CLI errors when stream mode can already be
## recognized. The pre-scan therefore understands `-f -`, `--filename -`, and
## `--filename=-` before full option validation.  Other malformed combinations
## are left to the normal CLI parser.
## @param args[] Arguments following the `update` subcommand.
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
## __manifest_manager_update_has_stream_hint -f - owner/repo
## @endcode
__manifest_manager_update_has_stream_hint() {
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

## @fn __manifest_manager_run_update()
## @brief Executes one complete update invocation including transactional I/O.
## @details
## Informational options are handled without staging.  For stream mode, complete
## STDIN capture occurs before full CLI parsing so recognized stream invocations
## can reproduce original input even when argument validation later fails.  File
## mode captures the selected manifest only after CLI parsing.  All network and
## mutation work operates on that captured original, followed by exactly one
## stream emission or one staged file publication.
## @param args[] Arguments following the public `update` subcommand.
## @par STDIN
## The complete manifest only when `-f -` stream mode is selected.
## @par STDOUT
## Help/version text, a complete transactional manifest in stream mode, or
## nothing for ordinary successful file-mode operation.
## @par STDERR
## Diagnostics are written for invalid requests and failed update operations.
## @returns Informational text, a stream manifest, or no data by mode.
## @retval 0 The operation succeeded or was a successful no-op.
## @retval 2 The CLI, manifest, selection, or declaration was invalid.
## @retval 3 A required runtime capability was unavailable.
## @retval 4 Release discovery or network acquisition failed.
## @retval 5 Surgical or preservation safety validation failed.
## @retval 6 Input, staging, filesystem, output, or publication failed.
## @par Examples
## @code
## __manifest_manager_run_update owner/repo v1.2.3
## @endcode
__manifest_manager_run_update() {
  local __mm_status=0 __mm_stream_hint=0

  if __manifest_manager_update_has_help "$@"; then
    __manifest_manager_usage
    return $?
  fi
  if __manifest_manager_update_has_version "$@"; then
    __manifest_manager_version_output
    return $?
  fi
  if __manifest_manager_update_has_stream_hint "$@"; then
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

  if __manifest_manager_parse_update_cli "$@"; then
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

  if [[ $__manifest_manager_option_filename == - ]]; then
    if ((!__manifest_manager_stream_mode)); then
      __manifest_manager_diag 'unable to establish transactional stream mode'
      __mm_status=2
    fi
  else
    __manifest_manager_stream_mode=0
    __manifest_manager_capture_file "$__manifest_manager_option_filename" || __mm_status=$?
  fi

  if ((__mm_status == 0)); then
    __manifest_manager_update_transaction \
      "$__manifest_manager_option_all" \
      "$__manifest_manager_option_package" \
      "$__manifest_manager_option_version" \
      "$__manifest_manager_option_version_supplied" || __mm_status=$?
  fi

  if ((__manifest_manager_stream_mode)); then
    __manifest_manager_stream_emit "$__mm_status"
    __mm_status=$?
  elif ((__mm_status == 0)); then
    __manifest_manager_publish_file "$__manifest_manager_option_filename" || __mm_status=$?
  fi

  __manifest_manager_stage_cleanup >/dev/null 2>&1 || {
    ((__mm_status != 0)) || __mm_status=6
  }
  trap - EXIT
  return "$__mm_status"
}

## @fn __manifest_manager_main()
## @brief Dispatches the public manifest-manager command-line interface.
## @details
## Top-level help/version forms succeed without manifest input.  `update`
## delegates to the transactional update runner.  Unknown or missing commands
## fail with status 2 and a concise diagnostic.  This function does not expose
## private Bash helpers as a supported API merely because maintained source can
## be sourced.
## @param args[] Public command arguments excluding the executable name.
## @par STDIN
## Depends on the selected command; only `update -f -` consumes a manifest
## stream.
## @par STDOUT
## Help/version text or a transactional manifest stream when selected.
## @par STDERR
## A diagnostic is written for unknown or missing commands and operational
## errors.
## @returns Command-specific public output.
## @retval 0 The selected command succeeded.
## @retval 2 The public command name or invocation was invalid.
## @note Other documented public update statuses from 3 through 6 are
## propagated.
## @par Examples
## @code
## __manifest_manager_main update owner/repo v1.2.3
## @endcode
__manifest_manager_main() {
  local __mm_command=${1:-}

  case $__mm_command in
    help | -h | --help)
      __manifest_manager_usage
      ;;
    version | -V | --version)
      __manifest_manager_version_output
      ;;
    update)
      shift
      __manifest_manager_run_update "$@"
      ;;
    '')
      __manifest_manager_diag 'a command is required'
      return 2
      ;;
    *)
      __manifest_manager_diag "unknown command: $__mm_command"
      return 2
      ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  __manifest_manager_main "$@"
fi
