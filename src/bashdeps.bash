#!/usr/bin/env bash

## @file src/bashdeps.bash
## @brief Materializes exact SHA-256-pinned external artifacts for a project.
## @details
## bashdeps.bash provides the maintained implementation of the bashdeps command-line
## interface.  The tool reads explicit dependency declarations, verifies local or
## acquired bytes against committed SHA-256 digests, and materializes only verified
## candidates beneath an invocation-selected project-relative destination root.
##
## The implementation deliberately separates declaration parsing, runtime capability
## selection, acquisition, hashing, filesystem safety, staging, publication, and
## command dispatch.  That separation keeps security-sensitive policy visible and
## allows each operation to fail conservatively without treating filenames, network
## success, or metadata as proof of artifact identity.
##
## The supported consumer interface is the executable CLI.  Functions and variables
## whose names begin with `__bashdeps_` are private implementation details even though
## they are documented here for maintainers and reference generation.  Sourcing this
## file leaves those private definitions available but does not create a supported
## sourced-function API.
##
## `verify` is intentionally network-free and non-mutating.  `install` and `sync`
## acquire bytes only when local destinations do not already match their approved
## digests.  Acquired bytes are staged and verified before publication, and final
## destinations are hashed again before mutating operations report success.
##
## @note The physical current working directory is the project root for one command
## invocation.  The manifest location does not redefine that root.
## @warning Version 1 does not coordinate concurrent mutating invocations.  Path
## checks reduce ordinary symlink and traversal risk but do not claim `openat`-style
## race resistance against a hostile process changing the filesystem concurrently.
## @see doc/bashdeps-spec.md
## @see doc/adr/ADR-014-documentation-first-source-code-commenting-standard.md
## @par Examples
## @code
## bash src/bashdeps.bash --help
## bash src/bashdeps.bash verify dependencies.txt
## bash src/bashdeps.bash sync --dest-root vendor dependencies.txt
## @endcode

## @var __bashdeps_version
## @brief Semantic version reported by the version command.
## @details
## Release builds inject this value before the maintained source is appended to a
## generated artifact.  Direct execution of maintained source uses `0.0.0-dev`
## unless a caller intentionally defines the variable first.
__bashdeps_version=${__bashdeps_version:-0.0.0-dev}

## @var __bashdeps_build_date
## @brief Source revision timestamp or build date reported by the version command.
## @details
## Generated artifacts inject release metadata.  Maintained source uses `unknown`
## when no build layer has supplied a value.
__bashdeps_build_date=${__bashdeps_build_date:-unknown}

## @var __bashdeps_build_commit
## @brief Source commit identifier reported by the version command.
## @details
## The build system supplies this metadata for generated artifacts.  Runtime
## behavior does not otherwise depend on Git or on this value.
__bashdeps_build_commit=${__bashdeps_build_commit:-unknown}

## @var __bashdeps_record_id
## @brief Scratch identity for the dependency record currently being parsed.
## @details
## Record parsing resets this value before reading a new declaration.  The value is
## opaque metadata after validation and is not used as proof of artifact identity.
__bashdeps_record_id=''

## @var __bashdeps_record_url
## @brief Scratch HTTPS URL for the dependency record currently being parsed.
## @details
## The parser preserves the field value literally after the first `=` delimiter.
## Validation later requires the value to begin with `https://`.
__bashdeps_record_url=''

## @var __bashdeps_record_dest
## @brief Scratch project-relative destination for the record currently being parsed.
## @details
## Validation requires canonical relative path text and containment beneath the
## invocation's selected destination root before this value can enter loaded state.
__bashdeps_record_dest=''

## @var __bashdeps_record_digest
## @brief Scratch `sha256:` declaration for the record currently being parsed.
## @details
## A valid value contains exactly 64 lowercase hexadecimal characters after the
## `sha256:` prefix.  Loaded state stores only that hexadecimal portion.
__bashdeps_record_digest=''

## @var __bashdeps_ids
## @brief Loaded dependency identities in manifest order.
## @details
## This array is kept index-aligned with the URL, destination, and digest arrays.
## Duplicate identities are rejected before a record is appended.
__bashdeps_ids=()

## @var __bashdeps_urls
## @brief Loaded dependency acquisition URLs in manifest order.
## @details
## Element indexes correspond directly to `__bashdeps_ids`, `__bashdeps_dests`, and
## `__bashdeps_digests`.
__bashdeps_urls=()

## @var __bashdeps_dests
## @brief Loaded project-relative dependency destinations in manifest order.
## @details
## Duplicate destinations are rejected so one synchronization set cannot contain
## two declarations competing to manage the same path.
__bashdeps_dests=()

## @var __bashdeps_digests
## @brief Loaded lowercase SHA-256 hexadecimal digests in manifest order.
## @details
## Values omit the manifest's `sha256:` prefix because the selected hash adapters
## already produce bare hexadecimal digests for comparison.
__bashdeps_digests=()

## @var __bashdeps_stage_dir
## @brief Active bashdeps-owned candidate staging directory for the current process.
## @details
## The value is empty until staging is required.  A successful staging allocation
## uses a private directory beneath the project root with mode `0700`; cleanup
## removes that known path on ordinary shell exit after synchronization begins.
__bashdeps_stage_dir=''

## @var __bashdeps_hash_backend
## @brief Cached name of the selected SHA-256 command adapter.
## @details
## Selection prefers `sha256sum`, falls back to `shasum`, and fails when neither
## supported capability is available.  An already selected value avoids repeated
## command discovery within one process.
__bashdeps_hash_backend=''

## @var __bashdeps_download_backend
## @brief Cached name of the selected HTTPS download command adapter.
## @details
## Selection prefers `curl`.  `wget` is eligible only when curl is absent and the
## local Wget help surface advertises the timeout and tries controls required by
## the version 1 acquisition policy.
__bashdeps_download_backend=''

## @var __bashdeps_dest_root
## @brief Project-relative containment root permitted for dependency destinations.
## @details
## Command handlers reset this policy to `vendor` for every operation and replace
## it only after validating an explicit `--dest-root` value.  The root constrains
## complete `dest=` values; it is never prepended to or used to relocate them.
__bashdeps_dest_root='vendor'

## @fn __bashdeps_usage()
## @brief Writes the supported command forms to standard output.
## @details
## The helper centralizes usage wording so explicit help and usage-error paths show
## the same command surface.  Callers that need usage on standard error redirect
## this helper rather than maintaining a second copy of the text.
## @returns Human-readable CLI usage text.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_usage
## @endcode
__bashdeps_usage() {
  printf '%s\n' \
    'Usage:' \
    '  bashdeps.bash install [--dest-root PATH] id=IDENTITY url=HTTPS_URL dest=RELATIVE_PATH digest=sha256:HEX' \
    '  bashdeps.bash sync [--dest-root PATH] [MANIFEST]' \
    '  bashdeps.bash verify [--dest-root PATH] [MANIFEST]' \
    '  bashdeps.bash help' \
    '  bashdeps.bash version'
}

## @fn __bashdeps_diag()
## @brief Writes one bashdeps-prefixed diagnostic to standard error.
## @details
## All arguments are joined using the shell's normal `$*` semantics and emitted as
## one diagnostic line.  Centralizing the prefix makes operational errors easy to
## identify without requiring each caller to repeat program-name formatting.
## @param message[] Words that form the diagnostic message.
## @par Standard Error
## One line beginning with `bashdeps.bash: ` followed by the supplied message.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_diag "manifest is not readable: dependencies.txt"
## @endcode
__bashdeps_diag() {
  printf 'bashdeps.bash: %s\n' "$*" >&2
}

## @fn __bashdeps_reset_record()
## @brief Clears scratch fields used while parsing one dependency declaration.
## @details
## Parsing is intentionally stateful inside one shell process so manifest records
## and explicit install arguments can share validation logic.  Resetting every
## scratch field before a new parse prevents omitted fields from inheriting values
## from a previous record.
## @retval 0 The scratch record fields were cleared.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_record_id='old@1'
## __bashdeps_reset_record
## @endcode
__bashdeps_reset_record() {
  __bashdeps_record_id=''
  __bashdeps_record_url=''
  __bashdeps_record_dest=''
  __bashdeps_record_digest=''
}

## @fn __bashdeps_validate_path_text()
## @brief Validates the canonical textual form required for project-relative paths.
## @details
## The check rejects empty paths, absolute paths, trailing separators, repeated
## separators, whitespace, and components equal to `.` or `..`.  This lexical
## normalization rule prevents multiple textual aliases from bypassing containment
## or duplicate-destination checks without introducing a `realpath` dependency.
##
## This helper validates text only.  Symlink and file-type checks are performed
## separately against the filesystem before inspection or publication.
## @param path Project-relative path text to validate.
## @retval 0 The path uses the accepted canonical relative form.
## @retval 1 The path is empty, absolute, aliased, traversal-bearing, or contains whitespace.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_validate_path_text 'vendor/tool.bash'
## ! __bashdeps_validate_path_text '../outside/tool.bash'
## @endcode
__bashdeps_validate_path_text() {
  local path component
  local -a components

  path=$1
  [[ -n $path ]] || return 1
  [[ $path != /* ]] || return 1
  [[ $path != */ ]] || return 1
  [[ $path != *//* ]] || return 1
  [[ ! $path =~ [[:space:]] ]] || return 1

  IFS='/' read -r -a components <<<"$path"
  for component in "${components[@]}"; do
    [[ -n $component ]] || return 1
    [[ $component != '.' && $component != '..' ]] || return 1
  done
}

## @fn __bashdeps_validate_dest_text()
## @brief Applies the canonical project-relative path grammar to a destination.
## @details
## Destination text currently has the same lexical requirements as destination-root
## text.  This wrapper preserves a destination-specific call boundary so future
## destination validation can evolve without spreading generic path checks through
## the parser.
## @param dest Project-relative dependency destination to validate.
## @retval 0 The destination uses the accepted canonical relative form.
## @retval 1 The destination violates the canonical relative-path grammar.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_validate_dest_text 'vendor/mktext.bash'
## @endcode
__bashdeps_validate_dest_text() {
  __bashdeps_validate_path_text "$1"
}

## @fn __bashdeps_set_dest_root()
## @brief Validates and stores an explicit destination containment root.
## @details
## One or more trailing slashes are removed before validation so common directory
## spellings such as `vendor/` and `vendor` select the same policy.  The normalized
## value must still satisfy the canonical relative-path grammar.  Invalid input is
## rejected before the global policy changes.
## @param root Project-relative root supplied by `--dest-root`.
## @par Standard Error
## A diagnostic naming the invalid root when validation fails.
## @retval 0 The normalized destination root was stored.
## @retval 2 The supplied root is invalid CLI policy.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_set_dest_root 'third_party/'
## printf '%s\n' "${__bashdeps_dest_root}"
## @endcode
__bashdeps_set_dest_root() {
  local root
  root=$1

  while [[ $root == */ ]]; do
    root=${root%/}
  done

  __bashdeps_validate_path_text "$root" || {
    __bashdeps_diag "invalid destination root: $1"
    return 2
  }

  __bashdeps_dest_root=$root
}

## @fn __bashdeps_dest_within_root()
## @brief Tests whether a complete destination is strictly beneath the selected root.
## @details
## Containment uses a path-component boundary by requiring the destination to begin
## with the selected root followed by `/`.  This permits `vendor/tool` while
## rejecting both the root itself and look-alike prefixes such as `vendor-old/tool`.
## @param dest Complete project-relative destination to test.
## @retval 0 The destination is strictly beneath the selected root.
## @retval 1 The destination is outside the root or names the root itself.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_dest_root='vendor'
## __bashdeps_dest_within_root 'vendor/tool.bash'
## ! __bashdeps_dest_within_root 'vendor-old/tool.bash'
## @endcode
__bashdeps_dest_within_root() {
  local dest
  dest=$1
  [[ $dest == "$__bashdeps_dest_root/"* ]]
}

## @fn __bashdeps_validate_record()
## @brief Validates the complete dependency record held in scratch globals.
## @details
## A valid record has non-empty identity, URL, destination, and digest fields.  The
## URL must use HTTPS, the destination must use canonical relative text and remain
## strictly beneath the selected destination root, and the digest must be
## `sha256:` followed by exactly 64 lowercase hexadecimal characters.
##
## Identity text remains opaque after non-emptiness is established.  This function
## therefore validates declaration syntax and write policy without pretending that
## labels or URLs prove artifact identity; the digest remains authoritative.
## @par Standard Error
## A field-specific diagnostic explaining the first validation failure.
## @retval 0 The scratch record is valid for the selected destination policy.
## @retval 2 The record is incomplete or contains an invalid URL, destination, or digest.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_record_id='tool@1'
## __bashdeps_record_url='https://example.test/tool'
## __bashdeps_record_dest='vendor/tool'
## __bashdeps_record_digest='sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
## __bashdeps_validate_record
## @endcode
__bashdeps_validate_record() {
  [[ -n $__bashdeps_record_id ]] || {
    __bashdeps_diag 'dependency declaration is missing id'
    return 2
  }
  [[ -n $__bashdeps_record_url ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id is missing url"
    return 2
  }
  [[ -n $__bashdeps_record_dest ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id is missing dest"
    return 2
  }
  [[ -n $__bashdeps_record_digest ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id is missing digest"
    return 2
  }

  [[ $__bashdeps_record_url == https://* ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id has a non-HTTPS url"
    return 2
  }

  __bashdeps_validate_dest_text "$__bashdeps_record_dest" || {
    __bashdeps_diag "dependency $__bashdeps_record_id has an invalid destination: $__bashdeps_record_dest"
    return 2
  }

  __bashdeps_dest_within_root "$__bashdeps_record_dest" || {
    __bashdeps_diag "dependency $__bashdeps_record_id destination is outside allowed root $__bashdeps_dest_root: $__bashdeps_record_dest"
    return 2
  }

  [[ $__bashdeps_record_digest =~ ^sha256:[0-9a-f]{64}$ ]] || {
    __bashdeps_diag "dependency $__bashdeps_record_id has an invalid digest"
    return 2
  }
}

## @fn __bashdeps_parse_tokens()
## @brief Parses and validates one dependency declaration from named field tokens.
## @details
## The parser resets prior scratch state, requires each token to contain `=`, and
## splits only at the first equals sign so additional equals characters remain data
## inside values such as URL query strings.  Field order is irrelevant.  Duplicate
## or unknown field names fail closed, and whitespace inside an already separated
## token is rejected.
##
## Successful parsing leaves the four scratch globals populated and delegates
## field-specific policy checks to `__bashdeps_validate_record`.  Manifest text is
## never sourced, evaluated, or sent back through a shell parser.
## @param fields[] Named `id=`, `url=`, `dest=`, and `digest=` tokens for one record.
## @par Standard Error
## A diagnostic describing malformed, duplicate, unknown, or invalid fields.
## @retval 0 The declaration was parsed and validated successfully.
## @retval 2 The declaration is malformed, incomplete, duplicated, unknown, or invalid.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_parse_tokens \
##   'id=tool@1' \
##   'url=https://example.test/tool?x=1&y=2' \
##   'dest=vendor/tool' \
##   'digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
## @endcode
__bashdeps_parse_tokens() {
  local token key value
  local seen_id=0 seen_url=0 seen_dest=0 seen_digest=0

  __bashdeps_reset_record

  for token in "$@"; do
    [[ $token == *=* ]] || {
      __bashdeps_diag "invalid dependency field: $token"
      return 2
    }
    [[ ! $token =~ [[:space:]] ]] || {
      __bashdeps_diag 'dependency fields must not contain whitespace'
      return 2
    }

    key=${token%%=*}
    value=${token#*=}
    [[ -n $key ]] || {
      __bashdeps_diag "invalid dependency field: $token"
      return 2
    }

    case $key in
      id)
        ((seen_id == 0)) || {
          __bashdeps_diag 'duplicate id field'
          return 2
        }
        seen_id=1
        __bashdeps_record_id=$value
        ;;
      url)
        ((seen_url == 0)) || {
          __bashdeps_diag 'duplicate url field'
          return 2
        }
        seen_url=1
        __bashdeps_record_url=$value
        ;;
      dest)
        ((seen_dest == 0)) || {
          __bashdeps_diag 'duplicate dest field'
          return 2
        }
        seen_dest=1
        __bashdeps_record_dest=$value
        ;;
      digest)
        ((seen_digest == 0)) || {
          __bashdeps_diag 'duplicate digest field'
          return 2
        }
        seen_digest=1
        __bashdeps_record_digest=$value
        ;;
      *)
        __bashdeps_diag "unknown dependency field: $key"
        return 2
        ;;
    esac
  done

  __bashdeps_validate_record
}

## @fn __bashdeps_array_contains()
## @brief Tests whether a value appears exactly in a supplied positional collection.
## @details
## The helper performs literal Bash string comparisons and does not interpret
## patterns, regular expressions, or package semantics.  Manifest loading uses it
## to detect duplicate identities and destinations before appending a record.
## @param needle Exact value to locate.
## @param values[] Values to search in order.
## @retval 0 At least one value exactly equals the needle.
## @retval 1 No supplied value equals the needle.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_array_contains 'vendor/a' 'vendor/a' 'vendor/b'
## @endcode
__bashdeps_array_contains() {
  local needle item
  needle=$1
  shift
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

## @fn __bashdeps_append_record()
## @brief Appends the validated scratch record to the loaded dependency arrays.
## @details
## Identity and destination uniqueness are set-wide manifest invariants.  This
## helper checks both before mutating the parallel arrays, then appends the record
## fields at the same index.  The stored digest has its `sha256:` prefix removed so
## later comparisons can use the raw digest produced by the hash adapter.
##
## The function assumes `__bashdeps_validate_record` has already accepted the
## scratch record; it does not repeat field-level syntax checks.
## @par Standard Error
## A diagnostic identifying a duplicate dependency identity or destination.
## @retval 0 The record was appended to every loaded array.
## @retval 2 The identity or destination duplicates a previously loaded record.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_ids=() __bashdeps_dests=() __bashdeps_urls=() __bashdeps_digests=()
## __bashdeps_parse_tokens 'id=a@1' 'url=https://example.test/a' 'dest=vendor/a' 'digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
## __bashdeps_append_record
## @endcode
__bashdeps_append_record() {
  if __bashdeps_array_contains "$__bashdeps_record_id" "${__bashdeps_ids[@]}"; then
    __bashdeps_diag "duplicate dependency id: $__bashdeps_record_id"
    return 2
  fi
  if __bashdeps_array_contains "$__bashdeps_record_dest" "${__bashdeps_dests[@]}"; then
    __bashdeps_diag "duplicate dependency destination: $__bashdeps_record_dest"
    return 2
  fi

  __bashdeps_ids+=("$__bashdeps_record_id")
  __bashdeps_urls+=("$__bashdeps_record_url")
  __bashdeps_dests+=("$__bashdeps_record_dest")
  __bashdeps_digests+=("${__bashdeps_record_digest#sha256:}")
}

## @fn __bashdeps_load_manifest()
## @brief Loads and validates an entire dependency manifest into parallel arrays.
## @details
## Loading begins by clearing previously loaded records, then requires the manifest
## to be a readable regular file.  Blank lines and lines whose first non-horizontal
## whitespace character is `#` are ignored.  Every other line is split on spaces
## and tabs into named-field tokens and parsed using the same record logic as the
## explicit install command.
##
## The complete manifest is validated before synchronization begins acquisition or
## publication.  Duplicate identities and destinations therefore fail before any
## dependency candidate is downloaded for that command invocation.
## @param manifest Path to the dependency manifest to read.
## @par Standard Error
## A diagnostic identifies an unreadable manifest or the line containing an invalid record.
## @retval 0 Every non-comment record was loaded and validated successfully.
## @retval 2 The manifest is unreadable or contains an invalid or duplicate record.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_load_manifest dependencies.txt
## printf '%s\n' "${#__bashdeps_ids[@]} dependencies loaded"
## @endcode
__bashdeps_load_manifest() {
  local manifest line line_number=0
  local -a tokens

  manifest=$1
  __bashdeps_ids=()
  __bashdeps_urls=()
  __bashdeps_dests=()
  __bashdeps_digests=()

  [[ -f $manifest && -r $manifest ]] || {
    __bashdeps_diag "manifest is not a readable regular file: $manifest"
    return 2
  }
  while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    [[ $line =~ ^[[:blank:]]*$ ]] && continue
    [[ $line =~ ^[[:blank:]]*# ]] && continue

    tokens=()
    IFS=$' \t' read -r -a tokens <<<"$line"
    if ! __bashdeps_parse_tokens "${tokens[@]}"; then
      __bashdeps_diag "invalid manifest record at $manifest:$line_number"
      return 2
    fi
    __bashdeps_append_record || return $?
  done <"$manifest"
}

## @fn __bashdeps_select_hash_backend()
## @brief Selects and caches one supported SHA-256 command implementation.
## @details
## Selection is capability-based rather than operating-system-based.  An existing
## cached selection is reused.  Otherwise `sha256sum` is preferred and `shasum` is
## the fallback.  No other command is chosen opportunistically because each
## supported adapter has explicit output and invocation semantics.
## @par Standard Error
## A diagnostic is written when neither supported SHA-256 command is available.
## @retval 0 A supported hash backend is selected in `__bashdeps_hash_backend`.
## @retval 3 No supported SHA-256 implementation is available.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_hash_backend=''
## __bashdeps_select_hash_backend
## printf '%s\n' "${__bashdeps_hash_backend}"
## @endcode
__bashdeps_select_hash_backend() {
  if [[ -n $__bashdeps_hash_backend ]]; then
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    __bashdeps_hash_backend=sha256sum
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    __bashdeps_hash_backend=shasum
    return 0
  fi
  __bashdeps_diag 'no supported SHA-256 implementation is available'
  return 3
}

## @fn __bashdeps_hash_file()
## @brief Calculates the lowercase SHA-256 digest of one local file.
## @details
## The selected hash adapter is kept behind this helper so dependency-state logic
## does not depend on command-specific output.  `sha256sum` is invoked directly;
## `shasum` is invoked with `-a 256`.  In either case the first whitespace-delimited
## output field must be exactly 64 lowercase hexadecimal characters before it is
## accepted as a usable digest.
## @param path Local file whose bytes should be hashed.
## @returns The 64-character lowercase SHA-256 digest followed by a newline.
## @retval 0 A valid SHA-256 digest was calculated and written.
## @retval 3 The hash backend is unavailable, hashing fails, or output is not a valid digest.
## @par Examples
## @code
## source src/bashdeps.bash
## digest=$(__bashdeps_hash_file vendor/tool.bash)
## printf '%s\n' "${digest}"
## @endcode
__bashdeps_hash_file() {
  local path output digest
  path=$1

  __bashdeps_select_hash_backend || return $?
  case $__bashdeps_hash_backend in
    sha256sum)
      output=$(sha256sum "$path" 2>/dev/null) || return 3
      ;;
    shasum)
      output=$(shasum -a 256 "$path" 2>/dev/null) || return 3
      ;;
    *)
      return 3
      ;;
  esac
  digest=${output%%[[:space:]]*}
  [[ $digest =~ ^[0-9a-f]{64}$ ]] || return 3
  printf '%s\n' "$digest"
}

## @fn __bashdeps_wget_has_required_controls()
## @brief Tests whether the local Wget help surface advertises required controls.
## @details
## A command named `wget` is not automatically considered a usable fallback.
## Version 1 requires `-T` timeout control and `-t` tries control so the acquisition
## layer can keep each backend invocation bounded and own the overall attempt count.
## The probe is local and performs no network request.  A nonzero `wget --help`
## status is ignored because the advertised text, when present, is the capability
## evidence this helper examines.
## @retval 0 Both `-T` and `-t` appear in recognized help forms.
## @retval 1 At least one required control is not advertised.
## @par Examples
## @code
## source src/bashdeps.bash
## if __bashdeps_wget_has_required_controls; then printf '%s\n' 'wget usable'; fi
## @endcode
__bashdeps_wget_has_required_controls() {
  local help

  help=$(wget --help 2>&1) || :
  [[ $help == *'-T '* || $help == *'-T,'* ]] || return 1
  [[ $help == *'-t '* || $help == *'-t,'* ]] || return 1
}

## @fn __bashdeps_select_download_backend()
## @brief Selects and caches one supported HTTPS downloader adapter.
## @details
## An existing selection is reused.  Otherwise curl is preferred whenever the
## command is present.  Wget is considered only when curl is unavailable and the
## local help surface exposes the required timeout and retry-count controls.  This
## keeps transport-specific capabilities behind one adapter boundary while avoiding
## operating-system assumptions.
## @par Standard Error
## A diagnostic is written when neither supported downloader is usable.
## @retval 0 A downloader is selected in `__bashdeps_download_backend`.
## @retval 3 No supported HTTPS downloader is available.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_download_backend=''
## __bashdeps_select_download_backend
## printf '%s\n' "${__bashdeps_download_backend}"
## @endcode
__bashdeps_select_download_backend() {
  if [[ -n $__bashdeps_download_backend ]]; then
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    __bashdeps_download_backend=curl
    return 0
  fi
  if command -v wget >/dev/null 2>&1 && __bashdeps_wget_has_required_controls; then
    __bashdeps_download_backend=wget
    return 0
  fi
  __bashdeps_diag 'no supported HTTPS downloader is available'
  return 3
}

## @fn __bashdeps_download_once()
## @brief Performs one transfer attempt into a caller-provided staging candidate.
## @details
## The function delegates to the selected private transport adapter and never
## targets a declared dependency destination directly.  Curl follows redirects
## while restricting both initial and redirected protocols to HTTPS, limiting
## redirects to ten, using a 10-second connection timeout, and bounding an attempt
## to 120 seconds.  Wget uses quiet mode, a 120-second timeout, and exactly one
## backend-managed try.
##
## A successful transfer establishes only that bytes were retrieved.  Digest
## acceptance happens later and remains independent of transport success.
## @param url Declared HTTPS URL to retrieve.
## @param candidate Private staging path that should receive transferred bytes.
## @retval 0 The selected downloader reported a successful transfer.
## @retval 3 No supported downloader is selected or the invoked downloader itself returns status 3.
## @note Other nonzero downloader exit statuses are propagated to the caller unchanged.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_download_once 'https://example.test/tool' '.bashdeps-stage/example'
## @endcode
__bashdeps_download_once() {
  local url candidate
  url=$1
  candidate=$2

  __bashdeps_select_download_backend || return $?
  case $__bashdeps_download_backend in
    curl)
      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --proto '=https' \
        --proto-redir '=https' \
        --max-redirs 10 \
        --connect-timeout 10 \
        --max-time 120 \
        --output "$candidate" \
        -- "$url"
      ;;
    wget)
      wget -q -T 120 -t 1 -O "$candidate" "$url"
      ;;
    *)
      return 3
      ;;
  esac
}

## @fn __bashdeps_download()
## @brief Acquires one URL with bounded bashdeps-managed transfer attempts.
## @details
## The acquisition layer first requires a supported downloader, then makes at most
## three transfer attempts.  Before each attempt it removes any prior candidate so
## partial bytes from an earlier failure cannot be mistaken for the current result.
## A successful transfer returns immediately; ordinary transport failures consume
## the remaining attempts.
##
## Status 3 is treated specially because it represents the runtime-capability
## category used by backend selection.  After all attempts fail, the helper maps
## the outcome to the public network-acquisition failure category.  Digest mismatch
## is intentionally not handled here because transport does not decide byte trust.
## @param url Declared HTTPS URL to retrieve.
## @param candidate Private staging path used for each attempt.
## @par Standard Error
## A final network-acquisition diagnostic is written after all attempts fail.
## @retval 0 A transfer attempt succeeded.
## @retval 3 A required downloader capability is unavailable or status 3 is propagated.
## @retval 4 All permitted transfer attempts failed.
## @retval 6 A stale candidate could not be removed before an attempt.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_download 'https://example.test/tool' '.bashdeps-stage/tool'
## @endcode
__bashdeps_download() {
  local url candidate attempt status
  url=$1
  candidate=$2

  __bashdeps_select_download_backend || return $?
  for ((attempt = 1; attempt <= 3; attempt++)); do
    rm -f "$candidate" || return 6
    if __bashdeps_download_once "$url" "$candidate"; then
      return 0
    else
      status=$?
    fi
    ((status == 3)) && return 3
  done

  __bashdeps_diag "network acquisition failed: $url"
  return 4
}

## @fn __bashdeps_project_root()
## @brief Reports the physical current working directory used as the project root.
## @details
## bashdeps deliberately avoids Git-root discovery and does not anchor destinations
## to the manifest's directory.  `pwd -P` resolves the invocation's current working
## directory physically so subsequent relative destination checks share one stable
## root string for the duration of the command.
## @returns The physical current working directory followed by a newline.
## @par Examples
## @code
## source src/bashdeps.bash
## root=$(__bashdeps_project_root)
## printf '%s\n' "${root}"
## @endcode
__bashdeps_project_root() {
  pwd -P
}

## @fn __bashdeps_check_existing_path()
## @brief Rejects unsafe existing components along a complete destination path.
## @details
## Starting from the physical project root, the helper examines each destination
## component that currently exists.  Any symbolic link is rejected, including a
## final symlink.  Existing parent components must be directories, and an existing
## final destination must be a regular file.
##
## Missing components are allowed because synchronization may create parent
## directories later, after candidate preflight.  This function therefore answers
## whether the existing filesystem state is safe to inspect or publish through; it
## does not require the destination to exist.
## @param root Physical project root for the invocation.
## @param dest Canonical project-relative destination to inspect.
## @par Standard Error
## A diagnostic identifies symbolic-link traversal or an incompatible file type.
## @retval 0 Existing components satisfy the version 1 path-safety policy.
## @retval 6 A symlink, non-directory parent, or non-regular final destination is present.
## @par Examples
## @code
## source src/bashdeps.bash
## root=$(__bashdeps_project_root)
## __bashdeps_check_existing_path "${root}" 'vendor/tool.bash'
## @endcode
__bashdeps_check_existing_path() {
  local root dest current component last index
  local -a components
  root=$1
  dest=$2

  IFS='/' read -r -a components <<<"$dest"
  current=$root
  last=$((${#components[@]} - 1))

  for ((index = 0; index <= last; index++)); do
    component=${components[index]}
    current=$current/$component

    if [[ -L $current ]]; then
      __bashdeps_diag "symbolic links are not permitted in destination path: $dest"
      return 6
    fi

    if ((index < last)); then
      if [[ -e $current && ! -d $current ]]; then
        __bashdeps_diag "destination parent is not a directory: $dest"
        return 6
      fi
    elif [[ -e $current && ! -f $current ]]; then
      __bashdeps_diag "destination is not a regular file: $dest"
      return 6
    fi
  done
}

## @fn __bashdeps_check_parent_path()
## @brief Rejects unsafe existing parent components without inspecting the final path.
## @details
## Parent creation needs to validate the path leading to a destination before and
## after `mkdir -p`.  This helper walks every component except the final filename,
## rejecting symbolic links and existing non-directory parents while allowing
## components that do not yet exist.
##
## The final destination is deliberately excluded because publication performs a
## separate complete-path check before replacement.
## @param root Physical project root for the invocation.
## @param dest Canonical project-relative destination whose parents should be checked.
## @par Standard Error
## A diagnostic identifies a symlink or non-directory parent component.
## @retval 0 Existing parent components are acceptable or absent.
## @retval 6 A parent component is a symlink or an existing non-directory.
## @par Examples
## @code
## source src/bashdeps.bash
## root=$(__bashdeps_project_root)
## __bashdeps_check_parent_path "${root}" 'vendor/deep/tool.bash'
## @endcode
__bashdeps_check_parent_path() {
  local root dest current component last index
  local -a components
  root=$1
  dest=$2

  IFS='/' read -r -a components <<<"$dest"
  current=$root
  last=$((${#components[@]} - 1))

  for ((index = 0; index < last; index++)); do
    component=${components[index]}
    current=$current/$component
    if [[ -L $current ]]; then
      __bashdeps_diag "symbolic links are not permitted in destination path: $dest"
      return 6
    fi
    if [[ -e $current && ! -d $current ]]; then
      __bashdeps_diag "destination parent is not a directory: $dest"
      return 6
    fi
  done
}

## @fn __bashdeps_destination_state()
## @brief Determines whether one destination already contains the approved bytes.
## @details
## The helper first applies existing-path safety checks.  A missing destination is
## an ordinary unsatisfied state rather than a filesystem error.  Existing regular
## files are hashed through the selected SHA-256 adapter and compared literally
## with the expected 64-character digest.
##
## This is the central cache-validity rule: filename presence, timestamps, embedded
## versions, and file mode do not establish satisfaction.  Only the bytes at a safe
## destination and their approved digest do.
## @param root Physical project root for the invocation.
## @param dest Canonical project-relative destination to inspect.
## @param expected Approved 64-character lowercase SHA-256 digest without a prefix.
## @retval 0 The destination exists safely and its bytes match the approved digest.
## @retval 1 The destination is absent or its bytes do not match.
## @retval 3 SHA-256 capability is unavailable or hashing fails.
## @retval 6 Existing filesystem state violates destination safety policy.
## @par Examples
## @code
## source src/bashdeps.bash
## root=$(__bashdeps_project_root)
## __bashdeps_destination_state "${root}" 'vendor/tool' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
## @endcode
__bashdeps_destination_state() {
  local root dest expected path actual
  root=$1
  dest=$2
  expected=$3
  path=$root/$dest

  __bashdeps_check_existing_path "$root" "$dest" || return $?
  [[ -e $path ]] || return 1

  actual=$(__bashdeps_hash_file "$path") || return $?
  [[ $actual == "$expected" ]] || return 1
  return 0
}

## @fn __bashdeps_make_stage()
## @brief Creates a private bashdeps-owned staging directory beneath the project root.
## @details
## Network candidates are kept away from final destinations so failed or unverified
## transfers cannot overwrite useful local bytes.  The helper tries up to five
## process-and-random-derived names and creates the first available directory with
## mode `0700`, then records that exact path for later cleanup.
## @param root Physical project root under which staging should be created.
## @retval 0 A private staging directory was created and recorded.
## @retval 6 No staging directory could be allocated after the bounded attempts.
## @par Examples
## @code
## source src/bashdeps.bash
## root=$(__bashdeps_project_root)
## __bashdeps_make_stage "${root}"
## printf '%s\n' "${__bashdeps_stage_dir}"
## @endcode
__bashdeps_make_stage() {
  local root candidate attempt
  root=$1

  for ((attempt = 1; attempt <= 5; attempt++)); do
    candidate=$root/.bashdeps-stage.$$.$RANDOM
    if mkdir -m 0700 "$candidate" 2>/dev/null; then
      __bashdeps_stage_dir=$candidate
      return 0
    fi
  done

  __bashdeps_diag 'unable to create staging directory'
  return 6
}

## @fn __bashdeps_cleanup_stage()
## @brief Removes the specifically recorded staging directory on a best-effort basis.
## @details
## Cleanup acts only on the exact path stored by `__bashdeps_make_stage`; it does not
## scan the project with broad filename patterns.  Removal errors are intentionally
## ignored during cleanup so they do not replace the command's more meaningful
## acquisition, integrity, or publication status.  The in-memory path is cleared
## after the attempt.
## @retval 0 Cleanup completes or no active staging directory is recorded.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_stage_dir='/tmp/example-stage'
## __bashdeps_cleanup_stage
## @endcode
__bashdeps_cleanup_stage() {
  if [[ -n $__bashdeps_stage_dir ]]; then
    rm -rf "$__bashdeps_stage_dir" 2>/dev/null || :
    __bashdeps_stage_dir=''
  fi
}

## @fn __bashdeps_ensure_parent()
## @brief Creates missing destination parent directories after validating their path.
## @details
## Publication is allowed to create required parent directories only after the
## calling convergence operation has completed declaration and candidate preflight.
## When a destination contains parent components, this helper checks all existing
## parents for symlinks and incompatible file types, runs `mkdir -p`, then checks
## them again before the caller writes a destination-adjacent temporary file.
##
## Destinations with no slash have no project-relative parent to create and return
## successfully without filesystem mutation.
## @param root Physical project root for the invocation.
## @param dest Canonical project-relative destination whose parents may be needed.
## @par Standard Error
## A diagnostic identifies unsafe parents or an inability to create the directory tree.
## @retval 0 Parent directories are present and pass the safety checks.
## @retval 6 Parent validation or directory creation fails.
## @par Examples
## @code
## source src/bashdeps.bash
## root=$(__bashdeps_project_root)
## __bashdeps_ensure_parent "${root}" 'vendor/deep/tool.bash'
## @endcode
__bashdeps_ensure_parent() {
  local root dest parent
  root=$1
  dest=$2

  if [[ $dest == */* ]]; then
    parent=${dest%/*}
    __bashdeps_check_parent_path "$root" "$dest" || return $?
    mkdir -p "$root/$parent" 2>/dev/null || {
      __bashdeps_diag "unable to create destination parent: $parent"
      return 6
    }
    __bashdeps_check_parent_path "$root" "$dest" || return $?
  fi
}

## @fn __bashdeps_publish_candidate()
## @brief Publishes one already-verified candidate conservatively at its destination.
## @details
## This helper is intentionally downstream of candidate digest verification.  It
## ensures the parent path exists safely, rechecks the current destination, and
## allocates a destination-adjacent temporary name so the final replacement can use
## same-directory rename behavior.  Candidate bytes are copied into that temporary
## file, assigned mode `0644`, and the destination path is checked again immediately
## before `mv -f` replaces the final file.
##
## Publication does not itself decide whether candidate bytes are trusted and does
## not hash them.  Callers must provide a verified staging candidate and perform
## final destination verification after publication.  Failure cleanup targets only
## the exact temporary path allocated by this invocation.
## @param root Physical project root for the invocation.
## @param dest Canonical project-relative final destination.
## @param candidate Staged candidate whose bytes have already passed digest verification.
## @par Standard Error
## A diagnostic identifies parent, allocation, copy, mode, path-safety, or rename failure.
## @retval 0 The candidate was replaced into the final destination.
## @retval 6 Filesystem safety, staging beside the destination, mode setting, or publication fails.
## @par Examples
## @code
## source src/bashdeps.bash
## root=$(__bashdeps_project_root)
## __bashdeps_publish_candidate "${root}" 'vendor/tool' '.bashdeps-stage/0'
## @endcode
__bashdeps_publish_candidate() {
  local root dest candidate final tmp attempt
  root=$1
  dest=$2
  candidate=$3
  final=$root/$dest

  __bashdeps_ensure_parent "$root" "$dest" || return $?
  __bashdeps_check_existing_path "$root" "$dest" || return $?

  for ((attempt = 1; attempt <= 5; attempt++)); do
    tmp=$final.bashdeps-tmp.$$.$RANDOM
    [[ ! -e $tmp && ! -L $tmp ]] && break
    tmp=''
  done
  [[ -n $tmp ]] || {
    __bashdeps_diag "unable to allocate publication path for: $dest"
    return 6
  }

  cp "$candidate" "$tmp" 2>/dev/null || {
    __bashdeps_diag "unable to stage verified bytes beside destination: $dest"
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }
  chmod 0644 "$tmp" 2>/dev/null || {
    __bashdeps_diag "unable to set destination mode: $dest"
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }

  __bashdeps_check_existing_path "$root" "$dest" || {
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }

  mv -f "$tmp" "$final" 2>/dev/null || {
    __bashdeps_diag "unable to publish dependency: $dest"
    rm -f "$tmp" 2>/dev/null || :
    return 6
  }
}

## @fn __bashdeps_verify_loaded()
## @brief Verifies every loaded dependency destination without network or mutation.
## @details
## The loaded arrays are expected to be index-aligned and already validated.  Each
## destination is inspected through the common byte-satisfaction helper.  Missing
## or mismatched bytes are accumulated as an ordinary unsatisfied verification
## result so the loop can inspect the complete declaration set; capability and
## filesystem-safety failures stop immediately because continuing cannot produce a
## trustworthy verification result.
##
## This function performs no downloader selection, acquisition, directory creation,
## chmod, or publication.  It is the state engine beneath the public `verify`
## command and the final postcondition check used by `sync`.
## @param root Physical project root for the invocation.
## @retval 0 Every loaded destination exists safely and matches its approved digest.
## @retval 1 At least one loaded destination is absent or mismatched.
## @retval 3 SHA-256 capability is unavailable or hashing fails.
## @retval 6 Filesystem safety fails or an unexpected internal state is encountered.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_load_manifest dependencies.txt
## root=$(__bashdeps_project_root)
## __bashdeps_verify_loaded "${root}"
## @endcode
__bashdeps_verify_loaded() {
  local root index state unsatisfied=0
  root=$1

  for ((index = 0; index < ${#__bashdeps_ids[@]}; index++)); do
    __bashdeps_destination_state "$root" "${__bashdeps_dests[index]}" "${__bashdeps_digests[index]}"
    state=$?
    case $state in
      0) ;;
      1)
        unsatisfied=1
        ;;
      3 | 6)
        return "$state"
        ;;
      *)
        return 6
        ;;
    esac
  done

  ((unsatisfied == 0)) || return 1
}

## @fn __bashdeps_sync_loaded()
## @brief Converges every loaded dependency to its approved byte identity.
## @details
## Synchronization first inspects every loaded destination and records only missing
## or mismatched entries as needing acquisition.  If all destinations already match,
## it returns without requiring a downloader.  Otherwise it selects hashing and
## download capabilities, creates private staging, and installs an EXIT trap for
## narrowly scoped cleanup.
##
## Every required candidate is downloaded and SHA-256 verified before intentional
## publication begins.  A single candidate mismatch therefore prevents publication
## of the entire staged replacement set.  Verified candidates are then published in
## manifest order, after which all loaded destinations are hashed again.  The final
## verification proves actual destination state rather than assuming successful copy
## or rename operations imply the intended bytes are present.
##
## Whole-set preflight reduces predictable partial updates but does not make
## multi-file publication globally atomic.  An unpredictable filesystem failure
## after publication begins can leave a partially updated set; a later sync always
## derives state from current destination bytes.
## @param root Physical project root for the invocation.
## @par Standard Error
## Diagnostics identify capability, acquisition, digest, filesystem, or final-verification failures.
## @retval 0 Every loaded destination contains its approved bytes after the operation.
## @retval 3 A required runtime hash or downloader capability is unavailable.
## @retval 4 Network acquisition exhausts its permitted attempts.
## @retval 5 An acquired candidate does not match its approved digest.
## @retval 6 Filesystem safety, staging, publication, cleanup prerequisite, or final verification fails.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_load_manifest dependencies.txt
## root=$(__bashdeps_project_root)
## __bashdeps_sync_loaded "${root}"
## @endcode
__bashdeps_sync_loaded() {
  local root index state candidate actual
  local -a needed candidates
  root=$1
  needed=()
  candidates=()

  for ((index = 0; index < ${#__bashdeps_ids[@]}; index++)); do
    __bashdeps_check_existing_path "$root" "${__bashdeps_dests[index]}" || return $?
    __bashdeps_destination_state "$root" "${__bashdeps_dests[index]}" "${__bashdeps_digests[index]}"
    state=$?
    case $state in
      0) ;;
      1)
        needed+=("$index")
        ;;
      3 | 6)
        return "$state"
        ;;
      *)
        return 6
        ;;
    esac
  done

  ((${#needed[@]} > 0)) || return 0

  __bashdeps_select_hash_backend || return $?
  __bashdeps_select_download_backend || return $?
  __bashdeps_make_stage "$root" || return $?
  trap '__bashdeps_cleanup_stage' EXIT

  for index in "${needed[@]}"; do
    candidate=$__bashdeps_stage_dir/$index
    __bashdeps_download "${__bashdeps_urls[index]}" "$candidate" || return $?
    actual=$(__bashdeps_hash_file "$candidate") || return $?
    if [[ $actual != "${__bashdeps_digests[index]}" ]]; then
      __bashdeps_diag "downloaded bytes do not match approved digest for: ${__bashdeps_ids[index]}"
      return 5
    fi
    candidates[index]=$candidate
  done

  for index in "${needed[@]}"; do
    __bashdeps_publish_candidate "$root" "${__bashdeps_dests[index]}" "${candidates[index]}" || return $?
  done

  __bashdeps_verify_loaded "$root"
  state=$?
  case $state in
    0) return 0 ;;
    3) return 3 ;;
    *)
      __bashdeps_diag 'final destination verification failed after publication'
      return 6
      ;;
  esac
}

## @fn __bashdeps_cmd_install()
## @brief Implements the public single-artifact `install` command.
## @details
## Each invocation begins with the default `vendor` containment policy.  An optional
## leading `--dest-root PATH` replaces that policy only after validation.  The
## remaining arguments must form one complete named-field dependency declaration,
## which is parsed using the same grammar and trust rules as a manifest record.
##
## The validated scratch record is converted into a one-element loaded dependency
## set and passed to the common convergence engine.  Existing correct bytes therefore
## avoid network access, while missing or mismatched bytes follow the same staged,
## verified publication path as manifest synchronization.
## @param --dest-root= Optional project-relative containment root supplied before fields.
## @param fields[] One dependency declaration using `id=`, `url=`, `dest=`, and `digest=`.
## @par Standard Error
## Usage, declaration, capability, acquisition, integrity, and filesystem failures are diagnosed here or by shared helpers.
## @retval 0 The declared destination contains the approved bytes.
## @retval 2 CLI policy or dependency declaration is invalid.
## @retval 3 A required runtime capability is unavailable.
## @retval 4 Network acquisition fails.
## @retval 5 Acquired bytes do not match the approved digest.
## @retval 6 Project-root resolution, filesystem safety, staging, publication, or final verification fails.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_cmd_install \
##   'id=tool@1' \
##   'url=https://example.test/tool' \
##   'dest=vendor/tool' \
##   'digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
## @endcode
__bashdeps_cmd_install() {
  local root
  __bashdeps_dest_root='vendor'

  if [[ ${1:-} == '--dest-root' ]]; then
    (($# >= 2)) || {
      __bashdeps_diag '--dest-root requires a path'
      return 2
    }
    __bashdeps_set_dest_root "$2" || return $?
    shift 2
  fi

  (($# > 0)) || {
    __bashdeps_diag 'install requires one dependency declaration'
    return 2
  }

  __bashdeps_parse_tokens "$@" || return $?
  __bashdeps_ids=("$__bashdeps_record_id")
  __bashdeps_urls=("$__bashdeps_record_url")
  __bashdeps_dests=("$__bashdeps_record_dest")
  __bashdeps_digests=("${__bashdeps_record_digest#sha256:}")
  root=$(__bashdeps_project_root) || return 6
  __bashdeps_sync_loaded "$root"
}

## @fn __bashdeps_cmd_sync()
## @brief Implements manifest-wide dependency convergence for the public `sync` command.
## @details
## The command resets destination containment to `vendor`, optionally validates a
## leading alternate root, accepts at most one manifest pathname, and defaults to
## `dependencies.txt`.  Manifest parsing and duplicate detection complete before
## the physical project root is resolved and the shared synchronization engine is
## entered.
##
## The loaded engine performs whole-set candidate preflight before publication and
## never implements synchronization as a shell loop that re-evaluates manifest
## records as `install` commands.
## @param --dest-root= Optional project-relative containment root supplied before the manifest.
## @param manifest Optional manifest path; defaults to `dependencies.txt`.
## @par Standard Error
## CLI, manifest, capability, acquisition, integrity, and filesystem failures are diagnosed here or by shared helpers.
## @retval 0 Every declared destination contains its approved bytes.
## @retval 2 CLI policy or manifest content is invalid.
## @retval 3 A required runtime capability is unavailable.
## @retval 4 Network acquisition fails.
## @retval 5 Acquired bytes do not match an approved digest.
## @retval 6 Project-root resolution, filesystem safety, staging, publication, or final verification fails.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_cmd_sync dependencies.txt
## __bashdeps_cmd_sync --dest-root third_party dependencies.txt
## @endcode
__bashdeps_cmd_sync() {
  local manifest root
  __bashdeps_dest_root='vendor'

  if [[ ${1:-} == '--dest-root' ]]; then
    (($# >= 2)) || {
      __bashdeps_diag '--dest-root requires a path'
      return 2
    }
    __bashdeps_set_dest_root "$2" || return $?
    shift 2
  fi

  (($# <= 1)) || {
    __bashdeps_diag 'sync accepts at most one manifest path'
    return 2
  }
  manifest=${1:-dependencies.txt}
  __bashdeps_load_manifest "$manifest" || return $?
  root=$(__bashdeps_project_root) || return 6
  __bashdeps_sync_loaded "$root"
}

## @fn __bashdeps_cmd_verify()
## @brief Implements network-free manifest verification for the public `verify` command.
## @details
## The command resets destination containment to `vendor`, optionally validates a
## leading alternate root, accepts at most one manifest pathname, and defaults to
## `dependencies.txt`.  After loading the complete manifest it resolves the physical
## project root and inspects current destination bytes through the shared verification
## engine.
##
## No downloader is selected and no destination directory, file, mode, staging
## area, or other managed state is intentionally changed.  Missing or mismatched
## destinations return the dedicated unsatisfied-verification status rather than
## being repaired.
## @param --dest-root= Optional project-relative containment root supplied before the manifest.
## @param manifest Optional manifest path; defaults to `dependencies.txt`.
## @par Standard Error
## CLI, manifest, hash-capability, and filesystem-safety failures are diagnosed here or by shared helpers.
## @retval 0 Every declared destination exists safely and matches its approved digest.
## @retval 1 At least one declared destination is absent or mismatched.
## @retval 2 CLI policy or manifest content is invalid.
## @retval 3 SHA-256 capability is unavailable or hashing fails.
## @retval 6 Project-root resolution or filesystem safety fails.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_cmd_verify dependencies.txt
## __bashdeps_cmd_verify --dest-root third_party dependencies.txt
## @endcode
__bashdeps_cmd_verify() {
  local manifest root
  __bashdeps_dest_root='vendor'

  if [[ ${1:-} == '--dest-root' ]]; then
    (($# >= 2)) || {
      __bashdeps_diag '--dest-root requires a path'
      return 2
    }
    __bashdeps_set_dest_root "$2" || return $?
    shift 2
  fi

  (($# <= 1)) || {
    __bashdeps_diag 'verify accepts at most one manifest path'
    return 2
  }
  manifest=${1:-dependencies.txt}
  __bashdeps_load_manifest "$manifest" || return $?
  root=$(__bashdeps_project_root) || return 6
  __bashdeps_verify_loaded "$root"
}

## @fn __bashdeps_cmd_version()
## @brief Writes embedded version and source-build metadata to standard output.
## @details
## Version output intentionally identifies the distributed program as
## `bashdeps.bash` and reports the semantic version, source revision timestamp or
## build date, and source commit identifier on separate lines.  Generated release
## artifacts inject these values during `make build`; direct maintained-source use
## may report development placeholders.
## @returns Three newline-terminated metadata lines: version, build date, and commit.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_cmd_version
## @endcode
__bashdeps_cmd_version() {
  printf 'bashdeps.bash %s\n' "$__bashdeps_version"
  printf 'build_date=%s\n' "$__bashdeps_build_date"
  printf 'commit=%s\n' "$__bashdeps_build_commit"
}

## @fn __bashdeps_main()
## @brief Dispatches the supported public CLI commands and aliases.
## @details
## The dispatcher requires a command, removes that token, and delegates dependency
## operations to their command handlers.  `help`, `-h`, and `--help` are equivalent
## and accept no additional arguments.  `version` and `--version` are likewise
## equivalent and argument-free.  Unknown or missing commands are usage errors and
## write concise usage guidance to standard error.
##
## The dispatcher returns command-handler statuses unchanged, preserving the public
## categories documented in ADR-007.  The direct-execution guard below this function
## invokes it only when the file is executed as a process; sourcing the file defines
## private helpers without automatically dispatching the caller's positional arguments.
## @param command Public command or supported help/version alias.
## @param arguments[] Remaining arguments for the selected command.
## @returns Help or version text when those informational commands are selected.
## @par Standard Error
## Missing and unknown commands include a diagnostic plus usage; operational diagnostics come from command handlers.
## @retval 0 The selected operation succeeds or help/version output is produced.
## @retval 1 Verification completes with one or more absent or mismatched destinations.
## @retval 2 CLI usage, manifest syntax, declaration, or destination-root policy is invalid.
## @retval 3 A required runtime capability is unavailable or unusable.
## @retval 4 Network acquisition fails.
## @retval 5 Acquired bytes fail approved-digest verification.
## @retval 6 Filesystem safety, staging, publication, or related operational handling fails.
## @par Examples
## @code
## source src/bashdeps.bash
## __bashdeps_main --help
## __bashdeps_main verify dependencies.txt
## @endcode
__bashdeps_main() {
  local command
  command=${1:-}
  [[ -n $command ]] || {
    __bashdeps_diag 'missing command'
    __bashdeps_usage >&2
    return 2
  }
  shift

  case $command in
    install)
      __bashdeps_cmd_install "$@"
      ;;
    sync)
      __bashdeps_cmd_sync "$@"
      ;;
    verify)
      __bashdeps_cmd_verify "$@"
      ;;
    help | -h | --help)
      (($# == 0)) || {
        __bashdeps_diag 'help accepts no arguments'
        return 2
      }
      __bashdeps_usage
      ;;
    version | --version)
      (($# == 0)) || {
        __bashdeps_diag 'version accepts no arguments'
        return 2
      }
      __bashdeps_cmd_version
      ;;
    *)
      __bashdeps_diag "unknown command: $command"
      __bashdeps_usage >&2
      return 2
      ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  __bashdeps_main "$@"
  exit $?
fi