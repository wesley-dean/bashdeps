# ADR-003: Define Sync and Verify Semantics

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the two core dependency-state operations exposed by `bashdeps`:
`synchronize` and `verify`.

The central invariant is that dependency state is judged by the bytes declared in
the manifest.  Presence, filename, version labels, or previous successful runs do
not establish that a dependency is current.

## Context

The design handoff originally described acquisition behavior, then refined that
model around convergence.  The refinement matters because a dependency can be
present locally and still fail to satisfy the current manifest.

Examples include:

- an older version remaining at the same destination;
- a locally edited dependency;
- corrupted bytes;
- an interrupted previous update;
- a changed URL with the same destination;
- a manifest update that changes only the approved digest.

A separate verification operation is also needed for offline or diagnostic use.
Verification should answer whether the current local state already satisfies the
manifest without attempting to repair it.

The project has also decided that `bashdeps` does not claim ownership of a
consumer's `vendor/` directory or any other broad tree.  Version 1 therefore
manages only destinations explicitly declared by the current manifest and does
not prune undeclared files.

Concurrency control is intentionally outside the version 1 problem space.  This
ADR neither guarantees correctness for concurrent mutating invocations nor adds a
locking protocol.

## Decision Drivers

- Make stale local state detectable and repairable.
- Avoid unnecessary network access when approved bytes are already present.
- Keep verification useful in offline and air-gapped workflows.
- Preserve existing destination bytes until verified replacements are ready.
- Detect predictable multi-dependency failures before intentional publication.
- Avoid broad filesystem ownership or deletion semantics.
- Make successful synchronization prove resulting state rather than infer it.
- Keep command intent clear and separate from ordinary builds.

## Decision

The initial public dependency-state commands SHALL be:

```text
bashdeps sync [MANIFEST]
bashdeps verify [MANIFEST]
```

When `MANIFEST` is omitted, both commands SHALL use:

```text
dependencies.txt
```

Help and version behavior SHALL be specified separately as part of the CLI and
release contract.

### Local satisfaction rule

A declared dependency SHALL be considered satisfied only when:

1. its destination exists as an acceptable ordinary file under the filesystem
   safety policy; and
2. the SHA-256 digest of the bytes at that destination exactly matches the digest
   declared by the manifest.

The implementation SHALL NOT use dependency identity, URL text, destination
filename, file timestamp, embedded version text, or previous run state as a
substitute for digest comparison.

### `verify`

`verify` SHALL:

1. parse and validate the complete manifest;
2. inspect every declared destination;
3. calculate each existing destination's SHA-256 digest;
4. confirm that every declared dependency is present and matches its approved
   digest;
5. return success only when all declared dependencies satisfy the manifest.

`verify` SHALL perform no network access.

`verify` SHALL not create, replace, remove, chmod, or otherwise intentionally
mutate dependency destinations.

Extra files that are not declared by the manifest SHALL be ignored.  Their
presence SHALL NOT cause verification to fail.

A blank manifest SHALL verify successfully provided the manifest itself is valid
and readable.

### `sync`

`sync` SHALL converge every destination declared by the current manifest to the
approved byte identity.

It SHALL:

1. parse and validate the complete manifest before dependency acquisition or
   publication;
2. inspect each declared destination and calculate its digest when present;
3. accept already-correct destinations without downloading replacements;
4. identify missing or mismatched destinations as requiring acquisition;
5. acquire required replacement candidates into project-controlled staging;
6. verify every acquired candidate against its declared SHA-256 digest;
7. avoid intentional publication of the staged replacement set if any candidate
   fails acquisition or verification;
8. create missing destination parent directories only after manifest validation
   has succeeded and when needed for publication;
9. publish only verified candidate bytes;
10. perform a final verification of every declared destination after publication;
11. return success only when the resulting declared dependency state satisfies
    the manifest.

An existing mismatched destination SHALL remain untouched until its replacement
candidate has been acquired and verified successfully.

A failed acquisition or digest mismatch SHALL NOT destroy a previously existing
destination merely because that destination is stale.

### No pruning in version 1

`sync` SHALL NOT remove files merely because they are absent from the current
manifest.

If a dependency declaration is removed, any old destination left in the working
tree becomes ordinary undeclared repository state.  Cleanup belongs to the
consumer's Makefile, `make clean`, explicit project policy, or a future operation
with separately defined deletion semantics.

This decision follows the narrower ownership model: `bashdeps` manages the paths
currently declared to it rather than claiming ownership of an entire directory
tree.

### Publication and atomicity claims

Replacement candidates SHALL be verified before publication.

Where ordinary filesystem operations permit it, publication SHOULD use
same-filesystem temporary paths and rename-style replacement so each individual
file replacement is as conservative as practical.

The project SHALL NOT describe synchronization of multiple dependency files as a
filesystem-wide atomic transaction.

Preflight of the complete replacement set reduces predictable partial updates,
but an unpredictable failure during the publication phase can still leave some
files updated and others not updated.  In that case, the command SHALL report
failure accurately.  A subsequent `sync` SHALL determine state from actual
manifest digest comparisons rather than assuming the prior operation's intent was
completed.

### File permissions

Dependency acceptance SHALL be based on byte identity, not executable mode.

Version 1 SHALL not add a permissions field to the manifest.

Publication SHALL use a conservative ordinary-file mode as defined by the
filesystem/publication ADR.  Consumers that require an executable dependency may
apply execution permissions as part of their own build or preparation policy.

### Concurrency

Version 1 SHALL make no guarantee that simultaneous `sync` processes operating on
the same destinations are safe.

The initial implementation SHALL not introduce locking, process coordination, or
repository-level concurrency management solely to address that scenario.

If a demonstrated consumer need later requires concurrent mutation semantics,
that behavior SHALL be defined by a separate ADR.

## Considered Alternatives

### Redownload every dependency during `sync`

This would simplify state inspection, but it would make repeated synchronization
needlessly network-dependent and discard the manifest digest's usefulness as a
cache-validity key.

### Accept any existing destination without hashing it

This reproduces the stale-cache failure that motivated the project.  Presence is
not proof of identity.

### Make `verify` repair incorrect state

Combining diagnosis and mutation would make offline validation impossible to
reason about and blur command intent.  Repair belongs to `sync`.

### Prune undeclared files automatically

Automatic pruning provides stronger whole-tree convergence when a tool owns a
managed root.  `bashdeps` does not claim such ownership in version 1, so deleting
undeclared repository files would be an unnecessarily broad mutation.

### Skip final verification after publication

The implementation could assume that verified candidate bytes remain correct
after publication.  A final verification pass is slightly more work but proves
the state actually present at the declared destinations and keeps successful
`sync` semantics straightforward.

### Add locking in version 1

A lock protocol could prevent simultaneous mutation of the same dependency set.
This was deferred because no current consumer requirement justifies the added
state, stale-lock handling, portability decisions, and failure semantics.

## Consequences

Repeated `sync` operations avoid network access for dependencies whose existing
bytes already match the manifest.

Stale, modified, or corrupted destinations are detected uniformly through digest
comparison without special version-upgrade logic.

Offline users can run `verify` without risk of network access or intentional
mutation.

Removing a manifest entry does not automatically remove its old destination.
Consumers that want a fully clean generated dependency tree should continue to
use their own clean target or explicit cleanup policy.

Successful `sync` has a strong and understandable postcondition: every declared
destination exists and matches its approved digest.

The project accepts that unpredictable failures during multi-file publication can
produce partial state and makes no stronger atomicity claim.

Concurrent mutation remains unspecified in version 1.

## Open Questions and Follow-Ups

Subsequent ADRs need to define:

- staging directory and temporary-file mechanics;
- symbolic-link and repository-boundary checks;
- publication file mode;
- acquisition redirects, timeouts, retry policy, and `curl` invocation;
- SHA-256 command selection;
- diagnostics and exit statuses;
- Make integration and the build/deps/deps-check/all boundary.

## Related Decisions

- Related to: ADR-000
- Related to: ADR-001
- Related to: ADR-002
- Derived from: `bash-dependency-convergence-handoff.md`
