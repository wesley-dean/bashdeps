# ADR-007: Define CLI, Diagnostics, and Exit Statuses

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the version 1 command surface, output channels, stable executable
name, and exit status categories for `bashdeps`.

## Context

`bashdeps` is intended for direct human use and for Make/CI automation.  Those
callers need to distinguish invalid input, unsatisfied local state, missing
runtime capabilities, network failure, integrity failure, and filesystem failure
without scraping prose diagnostics.

ADR-003 defines `install`, `sync`, and `verify`.  The CLI also needs ordinary
help and version behavior.  ADR-009 defines the distributed executable artifact
as `bashdeps.bash`, and ADR-013 adds the optional destination-root policy.

## Decision Drivers

- Keep the public command surface small.
- Make successful automation quiet and predictable.
- Keep diagnostics separate from machine-consumable or informational output.
- Provide stable failure categories without exposing private helper structure.
- Distinguish an unsatisfied verification from malformed input or failed repair.
- Make documentation match the actual executable filename consumers receive.

## Decision

The version 1 public executable name SHALL be:

```text
bashdeps.bash
```

The version 1 public commands SHALL be:

```text
bashdeps.bash install [--dest-root PATH] KEY=VALUE...
bashdeps.bash sync [--dest-root PATH] [MANIFEST]
bashdeps.bash verify [--dest-root PATH] [MANIFEST]
bashdeps.bash help
bashdeps.bash version
```

The option aliases `-h` and `--help` SHALL be equivalent to `help`.
The option `--version` SHALL be equivalent to `version`.

`sync` and `verify` SHALL use `dependencies.txt` when `MANIFEST` is omitted.

`install` SHALL accept one declaration expressed with the same named fields used
by a manifest record.  It SHALL require exactly one each of `id`, `url`, `dest`,
and `digest`, subject to ADR-002 validation.

`install`, `sync`, and `verify` MAY receive `--dest-root PATH` in the position and
with the semantics defined by ADR-013.  An invalid destination-root value or a
declaration outside the selected root is invalid CLI/declaration policy.

Normal successful `install`, `sync`, and `verify` operations SHOULD produce no
standard output unless a later documented feature explicitly defines output.
Diagnostics SHALL be written to standard error and SHALL identify the program as
`bashdeps.bash`.

Explicit help and version requests SHALL write to standard output.  Version output
SHALL identify the program as `bashdeps.bash`.

### Exit statuses

Version 1 SHALL use these public status categories:

```text
0  success, help, or version output
1  verify completed but one or more declared destinations are absent or mismatched
2  invalid CLI usage, invalid manifest, invalid dependency declaration, or invalid destination-root policy
3  required runtime capability is unavailable or unusable
4  network acquisition failed
5  acquired candidate bytes do not match the approved digest
6  filesystem safety, staging, or publication failed
```

Status 1 is intentionally specific to verification of existing state.  A missing
or mismatched destination is not itself an error for `install` or `sync`; those
operations attempt convergence.  If convergence subsequently fails, they return
the status corresponding to the actual failure.

A malformed digest declaration is status 2.  A syntactically valid digest whose
downloaded candidate does not match is status 5.

Failure to locate either supported downloader is status 3.  A selected downloader
that attempts retrieval and encounters DNS, TLS, HTTP, timeout, or transfer
failure returns status 4 through the public command layer.

Unsafe destination paths, rejected symbolic-link traversal, inability to create a
staging path, or inability to publish verified bytes return status 6.

The implementation MAY use more detailed private return codes internally, but the
public dispatcher SHALL map them into the documented categories above.

### Diagnostic posture

Diagnostics SHOULD identify:

- the operation that failed;
- the dependency identity when a record is involved;
- the destination or URL when disclosing it is useful and safe;
- the actionable failure category.

Diagnostics SHALL NOT print downloaded artifact contents, execute manifest text,
or expose secret-bearing configuration that version 1 does not otherwise support.

Usage errors SHOULD include concise usage guidance.  Operational failures SHOULD
not dump the complete help text by default.

## Considered Alternatives

### Use an extensionless `bashdeps` command name

An extensionless command resembles a conventionally installed system utility, but
the project distributes a standalone Bash artifact named `bashdeps.bash` for
vendoring and bootstrap use.  Using the actual artifact filename in the public
contract avoids requiring consumers to create an undocumented wrapper or rename
the file before following examples.

### Return 1 for every failure

This is conventional for small shell tools but would force Makefiles and CI
systems to parse diagnostics when they need to distinguish malformed input from
network or integrity failures.

### Use sysexits values

`sysexits.h` provides established categories, but its meanings do not map cleanly
to dependency convergence and it is not a Bash-specific portability convention.
A compact project-specific contract is clearer.

### Print progress on standard output

Progress output is useful interactively but makes command composition noisier.
Version 1 keeps successful data channels quiet; future optional verbosity can be
added without changing failure semantics.

## Consequences

Make and CI integrations can branch on broad failure class while remaining
independent of diagnostic wording.

The executable filename and exit status mapping become public API and should
change only through a future architectural decision.

A future `--quiet`, `--verbose`, or machine-readable reporting mode can build on
this contract without redefining success and failure.

## Open Questions and Follow-Ups

Human-friendly verbosity and structured reporting are deliberately deferred until
a demonstrated consumer needs them.

## Related Decisions

- Related to: ADR-002
- Related to: ADR-003
- Related to: ADR-004
- Related to: ADR-005
- Related to: ADR-006
- Related to: ADR-009
- Related to: ADR-013
