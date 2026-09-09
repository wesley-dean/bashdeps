#!/usr/bin/env bash
# shellcheck shell=bash
## @file lib/manifest-manager/state.bash
## @brief Owns manifest-manager process state, staging, hashing, and literal
## helpers.
## @details
## This module contains state and low-level helpers used only by
## `manifest-manager.bash`.  It does not participate in the `bashdeps.bash`
## runtime product.  The helpers centralize temporary-directory ownership,
## capability selection, byte-preserving input checks, SHA-256 calculation, and
## exact literal-string operations used by manager mutation contracts.
##
## The maintained source is sourced by `src/manifest-manager.bash`.  Release
## assembly incorporates this file only into the manifest-manager executable
## family, as required by ADR-020.
## @see doc/adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md
## @see doc/adr/ADR-021-extend-manifest-manager-with-list-add-and-remove.md
## @see doc/manifest-manager-spec.md
## @par Examples
## @code
## source lib/manifest-manager/state.bash
## __manifest_manager_stage_create
## @endcode

## @var __manifest_manager_stage_dir
## @brief Private temporary directory owned by the current manager process.
__manifest_manager_stage_dir=''

## @var __manifest_manager_hash_backend
## @brief Selected SHA-256 implementation for the current process.
__manifest_manager_hash_backend=''

## @var __manifest_manager_original_file
## @brief Captured original manifest used for transactional output or
## publication.
__manifest_manager_original_file=''

## @var __manifest_manager_candidate_file
## @brief Fully validated candidate manifest awaiting output or publication.
__manifest_manager_candidate_file=''

## @var __manifest_manager_stream_mode
## @brief Whether the active mutating manager invocation uses `-f -` semantics.
__manifest_manager_stream_mode=0

## @fn __manifest_manager_diag()
## @brief Writes one manifest-manager-prefixed diagnostic to STDERR.
## @details
## The function joins its arguments using normal shell `$*` semantics and emits
## one line.  Centralizing diagnostics keeps stdout available for help, version,
## list data, or transactional manifest streams.
## @param message[] Words that form the diagnostic message.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## One diagnostic line beginning with `manifest-manager.bash: ` is written.
## @returns Nothing is written to STDOUT.
## @retval 0 The diagnostic was written successfully.
## @note A non-zero `printf` status may be propagated if STDERR cannot be
## written.
## @par Examples
## @code
## __manifest_manager_diag 'dependency was not found'
## @endcode
__manifest_manager_diag() {
  printf 'manifest-manager.bash: %s\n' "$*" >&2
}

## @fn __manifest_manager_stage_create()
## @brief Allocates private staging used by one manager transaction.
## @details
## The stage is created beneath `${TMPDIR:-/tmp}` with `mktemp -d`.  Original
## and candidate manifest paths are then assigned inside that directory.  A
## caller must invoke cleanup on process exit.  Existing stage state is rejected
## so one invocation cannot accidentally reuse stale transaction files.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when private staging cannot be created.
## @returns Nothing is written to STDOUT.
## @retval 0 Private staging and transaction paths were initialized.
## @retval 6 Private staging could not be created or state was already active.
## @par Examples
## @code
## __manifest_manager_stage_create
## @endcode
__manifest_manager_stage_create() {
  local __mm_base

  if [[ -n $__manifest_manager_stage_dir ]]; then
    __manifest_manager_diag 'private staging is already active'
    return 6
  fi

  __mm_base=${TMPDIR:-/tmp}
  __manifest_manager_stage_dir=$(mktemp -d "${__mm_base%/}/manifest-manager.XXXXXX") || {
    __manifest_manager_diag 'unable to create private staging directory'
    __manifest_manager_stage_dir=''
    return 6
  }

  chmod 0700 "$__manifest_manager_stage_dir" 2>/dev/null || {
    __manifest_manager_diag 'unable to restrict private staging directory'
    rm -rf "$__manifest_manager_stage_dir"
    __manifest_manager_stage_dir=''
    return 6
  }

  __manifest_manager_original_file=$__manifest_manager_stage_dir/original.manifest
  __manifest_manager_candidate_file=$__manifest_manager_stage_dir/candidate.manifest
}

## @fn __manifest_manager_stage_cleanup()
## @brief Removes private transaction staging owned by the current manager process.
## @details
## Cleanup is idempotent.  The function removes only the exact directory
## recorded by `__manifest_manager_stage_dir`, then clears related process state
## so a later operation in the same shell cannot mistake removed paths for
## active staging.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns Nothing is written to STDOUT.
## @retval 0 Cleanup completed or no stage was active.
## @note A non-zero `rm` status may be propagated if active staging cannot be
## removed.
## @par Examples
## @code
## __manifest_manager_stage_cleanup
## @endcode
__manifest_manager_stage_cleanup() {
  local __mm_status=0

  if [[ -n $__manifest_manager_stage_dir ]]; then
    rm -rf "$__manifest_manager_stage_dir" || __mm_status=$?
  fi

  __manifest_manager_stage_dir=''
  __manifest_manager_original_file=''
  __manifest_manager_candidate_file=''
  __manifest_manager_hash_backend=''
  return "$__mm_status"
}

## @fn __manifest_manager_capture_file()
## @brief Copies a complete manifest file into private transaction staging.
## @details
## The source must be a readable regular file and must not be a symbolic link.
## Rejecting symlinks avoids replacing a link itself during later atomic
## publication.  The exact bytes are copied into the already-created original
## transaction path before command-specific mutation work occurs.
## @param source Manifest path to capture.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic identifies an unreadable, unsafe, or uncapturable input path.
## @returns Nothing is written to STDOUT.
## @retval 0 The complete manifest was captured.
## @retval 6 The input path was unsafe or could not be copied completely.
## @par Examples
## @code
## __manifest_manager_capture_file dependencies.txt
## @endcode
__manifest_manager_capture_file() {
  local __mm_source=$1

  [[ -n $__manifest_manager_original_file ]] || {
    __manifest_manager_diag 'private staging is not initialized'
    return 6
  }
  [[ ! -L $__mm_source && -f $__mm_source && -r $__mm_source ]] || {
    __manifest_manager_diag "manifest is not a readable regular file: $__mm_source"
    return 6
  }

  cp "$__mm_source" "$__manifest_manager_original_file" || {
    __manifest_manager_diag "unable to capture manifest: $__mm_source"
    return 6
  }
}

## @fn __manifest_manager_capture_stdin()
## @brief Captures the complete STDIN manifest before transactional stream work.
## @details
## Mutating stream mode cannot emit incrementally because a later failure must
## reproduce the original input byte-for-byte.  This helper therefore consumes
## STDIN into private staging before CLI validation that can depend on manifest
## contents or before command-specific mutation work begins.
## @par STDIN
## The complete manifest byte stream to capture.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when complete input capture fails.
## @returns Nothing is written to STDOUT.
## @retval 0 STDIN was captured completely.
## @retval 6 STDIN could not be captured completely.
## @par Examples
## @code
## __manifest_manager_capture_stdin < dependencies.txt
## @endcode
__manifest_manager_capture_stdin() {
  [[ -n $__manifest_manager_original_file ]] || {
    __manifest_manager_diag 'private staging is not initialized'
    return 6
  }

  cat >"$__manifest_manager_original_file" || {
    __manifest_manager_diag 'unable to capture complete manifest from STDIN'
    return 6
  }
}

## @fn __manifest_manager_assert_lossless_text()
## @brief Verifies that Bash can round-trip the complete manifest byte-for-byte.
## @details
## Bash variables cannot represent NUL bytes and `read` can therefore discard
## data that cannot safely participate in source-preserving manager operations.
## The helper reads each physical line with Bash, reproduces the exact line
## terminator state into a temporary file, and compares that reproduction with
## the source. Any difference makes the manifest invalid for this tool rather
## than allowing silent truncation or normalization.
## @param source Captured manifest file to validate.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when the manifest cannot be represented losslessly.
## @returns Nothing is written to STDOUT.
## @retval 0 The manifest round-trips through Bash without byte changes.
## @retval 2 The byte stream is not losslessly representable.
## @retval 6 Temporary-file or input I/O failed.
## @par Examples
## @code
## __manifest_manager_assert_lossless_text "$__manifest_manager_original_file"
## @endcode
__manifest_manager_assert_lossless_text() {
  local __mm_source=$1
  local __mm_roundtrip __mm_line __mm_had_newline

  [[ -n $__manifest_manager_stage_dir ]] || return 6
  __mm_roundtrip=$__manifest_manager_stage_dir/lossless-roundtrip
  : >"$__mm_roundtrip" || return 6

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

    printf '%s' "$__mm_line" >>"$__mm_roundtrip" || {
      exec 3<&-
      return 6
    }
    if ((__mm_had_newline)); then
      printf '\n' >>"$__mm_roundtrip" || {
        exec 3<&-
        return 6
      }
    fi
  done
  exec 3<&-

  if ! cmp -s "$__mm_source" "$__mm_roundtrip"; then
    __manifest_manager_diag \
      'manifest contains bytes that cannot be represented losslessly by Bash'
    return 2
  fi
}

## @fn __manifest_manager_select_hash_backend()
## @brief Selects one supported SHA-256 implementation for digest calculation.
## @details
## Selection prefers `sha256sum` and falls back to `shasum -a 256`.  The chosen
## adapter is cached for the current process.  Hash capability is intentionally
## independent from the `bashdeps.bash` downloader/hash selection
## implementation.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when no supported SHA-256 implementation is present.
## @returns Nothing is written to STDOUT.
## @retval 0 A supported SHA-256 backend is selected.
## @retval 3 No supported SHA-256 backend is available.
## @par Examples
## @code
## __manifest_manager_select_hash_backend
## @endcode
__manifest_manager_select_hash_backend() {
  if [[ -n $__manifest_manager_hash_backend ]]; then
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    __manifest_manager_hash_backend=sha256sum
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    __manifest_manager_hash_backend=shasum
    return 0
  fi

  __manifest_manager_diag 'no supported SHA-256 implementation is available'
  return 3
}

## @fn __manifest_manager_sha256()
## @brief Calculates lowercase SHA-256 for one staged artifact.
## @details
## The selected adapter hashes the exact file bytes.  Output is validated before
## being returned so malformed command output cannot become proposed manifest
## trust data.
## @param path File whose bytes should be hashed.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## The 64-character lowercase hexadecimal SHA-256 digest is written on success.
## @par STDERR
## A diagnostic is written when hashing fails or produces malformed output.
## @returns One lowercase 64-character hexadecimal digest followed by a newline.
## @retval 0 A valid SHA-256 digest was produced.
## @retval 3 No supported hashing capability is available.
## @retval 6 Hash execution or output validation failed.
## @par Examples
## @code
## digest="$(__manifest_manager_sha256 artifact.bin)"
## @endcode
__manifest_manager_sha256() {
  local __mm_path=$1
  local __mm_output __mm_digest

  __manifest_manager_select_hash_backend || return $?
  case $__manifest_manager_hash_backend in
    sha256sum)
      __mm_output=$(sha256sum "$__mm_path" 2>/dev/null) || {
        __manifest_manager_diag "unable to hash candidate artifact: $__mm_path"
        return 6
      }
      ;;
    shasum)
      __mm_output=$(shasum -a 256 "$__mm_path" 2>/dev/null) || {
        __manifest_manager_diag "unable to hash candidate artifact: $__mm_path"
        return 6
      }
      ;;
    *)
      return 3
      ;;
  esac

  __mm_digest=${__mm_output%%[[:space:]]*}
  [[ $__mm_digest =~ ^[0-9a-f]{64}$ ]] || {
    __manifest_manager_diag "SHA-256 implementation returned malformed output"
    return 6
  }
  printf '%s\n' "$__mm_digest"
}

## @fn __manifest_manager_literal_count()
## @brief Counts non-overlapping literal occurrences of one string in another.
## @details
## Pattern metacharacters in the needle are quoted inside Bash parameter
## expansion so manifest values are treated as literal data rather than glob
## syntax.  Empty needles are rejected because they have no useful occurrence
## count for surgical replacement.
## @param haystack String to inspect.
## @param needle Non-empty literal string to count.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## One decimal occurrence count is written.
## @par STDERR
## Nothing is intentionally written to STDERR.
## @returns One decimal integer followed by a newline.
## @retval 0 The occurrence count was produced.
## @retval 2 The needle was empty.
## @par Examples
## @code
## count="$(__manifest_manager_literal_count 'a+b+a+b' 'a+b')"
## @endcode
__manifest_manager_literal_count() {
  local __mm_haystack=$1
  local __mm_needle=$2
  local __mm_count=0 __mm_prefix

  [[ -n $__mm_needle ]] || return 2
  while :; do
    __mm_prefix=${__mm_haystack%%"$__mm_needle"*}
    [[ $__mm_prefix != "$__mm_haystack" ]] || break
    __mm_haystack=${__mm_haystack#*"$__mm_needle"}
    __mm_count=$((__mm_count + 1))
  done
  printf '%s\n' "$__mm_count"
}

## @fn __manifest_manager_literal_replace_once()
## @brief Replaces one literal string after proving it occurs exactly once.
## @details
## The helper enforces the exact-once substitution rule independently for each
## changed field value.  It writes the transformed string into a caller-named
## variable without routing the potentially multiline raw record through command
## substitution, which would otherwise discard trailing newline bytes.
## @param haystack Raw record string to transform.
## @param old Non-empty literal value that must occur exactly once.
## @param new Replacement value used literally without interpretation.
## @param output_name Caller variable that receives the transformed string.
## @par STDIN
## Nothing is read from STDIN.
## @par STDOUT
## Nothing is written to STDOUT.
## @par STDERR
## A diagnostic is written when the old value does not occur exactly once.
## @returns Nothing is written to STDOUT.
## @retval 0 One literal substitution was written to the output variable.
## @retval 5 The old value occurred zero times or more than once.
## @par Examples
## @code
## __manifest_manager_literal_replace_once "$raw" "$old" "$new" updated
## @endcode
__manifest_manager_literal_replace_once() {
  local __mm_haystack=$1
  local __mm_old=$2
  local __mm_new=$3
  local __mm_output_name=$4
  local __mm_count __mm_prefix __mm_suffix

  __mm_count=$(__manifest_manager_literal_count "$__mm_haystack" "$__mm_old") || return 5
  if [[ $__mm_count != 1 ]]; then
    __manifest_manager_diag \
      "surgical replacement requires exactly one occurrence; found $__mm_count"
    return 5
  fi

  __mm_prefix=${__mm_haystack%%"$__mm_old"*}
  __mm_suffix=${__mm_haystack#*"$__mm_old"}
  printf -v "$__mm_output_name" '%s%s%s' "$__mm_prefix" "$__mm_new" "$__mm_suffix"
}
