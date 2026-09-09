#!/usr/bin/env bash
# shellcheck shell=bash
## @file src/manifest-manager.bash
## @brief Maintains and inspects bashdeps manifests through deliberate commands.
## @details
## `manifest-manager.bash` is a maintainer-side companion to `bashdeps.bash`. It
## prepares deliberate source changes to dependency declarations and provides
## validated read-only inspection without participating in runtime artifact
## synchronization.
##
## The executable is intentionally separate from the bashdeps synchronization
## runtime.  It may discover GitHub's latest release and calculate proposed
## trust data for `update`, while `add` requires complete declaration data from
## the caller.  `bashdeps.bash` continues to consume only already-reviewed
## manifest declarations.  The `list` command reads validated complete identity
## values without reserializing manifest source.
##
## Maintained source loads manager-only implementation modules from
## `lib/manifest-manager/`.  Release assembly incorporates that explicit source
## closure into each generated manager artifact and removes the repository-only
## import block.  No manager module is incorporated into `bashdeps.bash`.
## @note The public interface is this executable CLI.  Private functions
## beginning with `__manifest_manager_` are not a supported sourceable API.
## @warning Successful mutations propose new trusted manifest source.  Review
## and commit of those source changes remain the authorization boundary.
## @see doc/manifest-manager-spec.md
## @see doc/adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md
## @see doc/adr/ADR-021-extend-manifest-manager-with-list-add-and-remove.md
## @par Examples
## @code
## manifest-manager.bash list
## manifest-manager.bash add id=acme/tool@v1 \
##   url=https://example.test/tool dest=vendor/tool \
##   digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
## manifest-manager.bash update wesley-dean/bash-doxygen
## @endcode

# BEGIN MANIFEST_MANAGER_SOURCE_IMPORTS
__manifest_manager_source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=lib/manifest-manager/state.bash
source "$__manifest_manager_source_root/lib/manifest-manager/state.bash"
# shellcheck source=lib/manifest-manager/manifest.bash
source "$__manifest_manager_source_root/lib/manifest-manager/manifest.bash"
# shellcheck source=lib/manifest-manager/github.bash
source "$__manifest_manager_source_root/lib/manifest-manager/github.bash"
# shellcheck source=lib/manifest-manager/transaction.bash
source "$__manifest_manager_source_root/lib/manifest-manager/transaction.bash"
# shellcheck source=lib/manifest-manager/update.bash
source "$__manifest_manager_source_root/lib/manifest-manager/update.bash"
# shellcheck source=lib/manifest-manager/list.bash
source "$__manifest_manager_source_root/lib/manifest-manager/list.bash"
# shellcheck source=lib/manifest-manager/add.bash
source "$__manifest_manager_source_root/lib/manifest-manager/add.bash"
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
## @brief Writes the complete currently supported manager CLI surface to STDOUT.
## @details
## Top-level help summarizes the implemented `update`, `list`, and `add` commands
## and directs callers to command-specific help for operation details.  Commands
## defined by ADR-021 but not yet implemented are intentionally not advertised.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Human-readable public CLI help is written.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Multi-line human-readable help text.
## @retval 0 Help text was written successfully.
## @note A non-zero output status may be propagated if STDOUT cannot be written.
## @par Examples
## @code
## __manifest_manager_usage
## @endcode
__manifest_manager_usage() {
  cat <<'USAGE'
Usage:
  manifest-manager.bash COMMAND [OPTIONS]
  manifest-manager.bash help
  manifest-manager.bash version

Commands:
  update    Update one or all existing GitHub-backed dependency declarations.
  add       Append one complete explicit dependency declaration.
  list      List complete validated dependency identity values.

Informational forms:
  -h, --help             Show this help and exit successfully.
  -V, --version          Show version/build information and exit successfully.

Use 'manifest-manager.bash COMMAND --help' for command-specific syntax,
file/stream behavior, output, and exit statuses.
USAGE
}

## @fn __manifest_manager_update_usage()
## @brief Writes complete public help for the `update` subcommand.
## @details
## Update help documents positional forms, option meanings, omitted-version
## behavior, transactional stream rollback, and relevant public exit categories.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Human-readable `update` help is written.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Multi-line human-readable help text.
## @retval 0 Help text was written successfully.
## @note A non-zero output status may be propagated if STDOUT cannot be written.
## @par Examples
## @code
## __manifest_manager_update_usage
## @endcode
__manifest_manager_update_usage() {
  cat <<'USAGE'
Usage:
  manifest-manager.bash update [OPTIONS] ID [VERSION]
  manifest-manager.bash update [OPTIONS] ID@VERSION
  manifest-manager.bash update [OPTIONS] --all

Options:
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
## This compatibility-local wrapper delegates to the shared command pre-scan so
## update behavior remains unchanged while other commands use the same
## informational-option rule.
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
## __manifest_manager_update_has_help "$@"
## @endcode
__manifest_manager_update_has_help() {
  __manifest_manager_args_have_help "$@"
}

## @fn __manifest_manager_update_has_version()
## @brief Tests whether update arguments request informational version output.
## @details
## This wrapper preserves the established update call structure while delegating
## detection to the command-agnostic helper introduced for the expanded CLI.
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
## __manifest_manager_update_has_version "$@"
## @endcode
__manifest_manager_update_has_version() {
  __manifest_manager_args_have_version "$@"
}

## @fn __manifest_manager_update_has_stream_hint()
## @brief Detects whether raw update arguments unambiguously request filename
## `-`.
## @details
## The wrapper retains the existing update runner contract while sharing stream
## filename recognition with other manager commands.
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
  __manifest_manager_args_have_stream_filename "$@"
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
    __manifest_manager_update_usage
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
## Top-level help/version forms succeed without manifest input.  `update` and
## `add` delegate to transactional mutation runners, while `list` delegates to
## its read-only validated identity runner.  Unknown or missing commands fail
## with status 2 and a concise diagnostic.
## @param args[] Public command arguments excluding the executable name.
## @par STDIN
## Depends on the selected command; mutating `-f -` forms and `list -f -`
## consume a manifest stream.
## @par STDOUT
## Help/version text, list output, or a transactional manifest stream when
## selected.
## @par STDERR
## A diagnostic is written for unknown or missing commands and operational
## errors.
## @returns Command-specific public output.
## @retval 0 The selected command succeeded.
## @retval 2 The public command name or invocation was invalid.
## @note Other documented public command statuses from 3 through 6 are
## propagated when relevant.
## @par Examples
## @code
## __manifest_manager_main list
## __manifest_manager_main add id=tool@1 url=https://example.test/tool \
##   dest=vendor/tool digest=sha256:0123...
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
    add)
      shift
      __manifest_manager_run_add "$@"
      ;;
    list)
      shift
      __manifest_manager_run_list "$@"
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
