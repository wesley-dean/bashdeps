# ADR-003: Define Install, Sync, and Verify Semantics

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the three core dependency-state operations exposed by the
`bashdeps.bash` CLI: single-artifact installation, manifest synchronization, and
manifest verification.

The central invariant is that dependency state is judged by the bytes declared
through named dependency fields.  Presence, filename, version labels, or
previous successful runs do not establish that a dependency is current.

The `install` command provides the single-record operation whose named arguments
mirror one record in `dependencies.txt`.  The `sync` command applies the same
record semantics to a complete manifest while preserving whole-manifest preflight
and staged publication behavior.

## Context

The design handoff originally described acquisition behavior, then refined that
model around convergence.  The refinement matters because a dependency can be
present locally and still fail to satisfy the current declaration.

Examples include:

- an older version remaining at the same destination;
- a locally edited dependency;
- corrupted bytes;
- an interrupted previous update;
- a changed URL with the same destination;
- a manifest update that changes only the approved digest.

The named-field grammar established by ADR-002 also creates a useful relationship
between a manifest record and an explicit one-artifact CLI operation.  For
example, this manifest record:

```text
id=dep@1.0.0 url=https://example.com/dep dest=vendor/dep digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

corresponds conceptually to:

```text
bashdeps.bash install id=dep@1.0.0 url=https://example.com/dep dest=vendor/dep digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

This relationship should be preserved because it keeps the file format and CLI
model easy to understand.  It must not, however, weaken whole-manifest safety by
turning `sync` into a shell loop that publishes one record before later records
have been validated and staged.

A separate verification operation is also needed for offline or diagnostic use.
Verification should answer whether the current local state already satisfies the
manifest without attempting to repair it.

The project has also decided that bashdeps does not claim ownership of a
consumer's `vendor/` directory or any other broad tree.  Version 1 therefore
manages only destinations explicitly declared by the current operation and does
not prune undeclared files.

ADR-013 adds a destination-root security policy around these operations.  The
complete `dest=` value remains part of the declaration, while `vendor/` is the
default permitted root unless the caller explicitly supplies `--dest-root`.

Concurrency control is intentionally outside the version 1 problem space.  This
ADR neither guarantees correctness for concurrent mutating invocations nor adds a
locking protocol.

## Decision Drivers

- Make stale local state detectable and repairable.
- Provide a direct single-artifact operation that mirrors manifest records.
- Preserve whole-manifest validation and staging during synchronization.
- Avoid unnecessary network access when approved bytes are already present.
- Keep verification useful in offline and air-gapped workflows.
- Preserve existing destination bytes until verified replacements are ready.
- Detect predictable multi-dependency failures before intentional publication.
- Avoid broad filesystem ownership or deletion semantics.
- Make successful operations prove resulting state rather than infer it.
- Keep command intent clear and separate from ordinary builds.
- Avoid evaluating manifest records as shell commands.

## Decision

The initial public dependency-state commands SHALL be:

```text
bashdeps.bash install [--dest-root PATH] id=VALUE url=VALUE dest=VALUE digest=VALUE
bashdeps.bash sync [--dest-root PATH] [MANIFEST]
bashdeps.bash verify [--dest-root PATH] [MANIFEST]
```

The four named `install` fields SHALL use the same names, field-specific grammar,
and order-independent semantics defined for one manifest record by ADR-002.

Destination-root selection and containment semantics SHALL follow ADR-013.

When `MANIFEST` is omitted, `sync` and `verify` SHALL use:

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
   declared by the operation.

The implementation SHALL NOT use dependency identity, URL text, destination
filename, file timestamp, embedded version text, file mode, or previous run
state as a substitute for digest comparison.

### `install`

`install` SHALL materialize one explicitly declared artifact.

It SHALL:

1. parse and validate the complete set of named arguments before network access
   or destination mutation;
2. require each version 1 field exactly once;
3. enforce the selected destination-root policy before acquisition;
4. inspect the declared destination and calculate its digest when present;
5. return success without network access when the destination already contains
   the approved bytes;
6. acquire a missing or mismatched artifact into project-controlled staging;
7. verify the candidate against the declared SHA-256 digest before publication;
8. preserve an existing mismatched destination until a verified replacement is
   ready;
9. create missing destination parent directories only after argument validation
   and candidate verification have succeeded and when needed for publication;
10. publish only verified candidate bytes;
11. verify the resulting destination after publication;
12. return success only when the destination contains the approved bytes.

`install` MAY use the network when the declared artifact is missing or does not
match its approved digest.

A failed download or digest mismatch SHALL NOT destroy an existing destination.

`install` SHALL treat the artifact as bytes.  It SHALL NOT execute the downloaded
file or infer that the file should be executable.

### `verify`

`verify` SHALL:

1. parse and validate the complete manifest;
2. enforce the selected destination-root policy for every declaration;
3. inspect every declared destination;
4. calculate each existing destination's SHA-256 digest;
5. confirm that every declared dependency is present and matches its approved
   digest;
6. return success only when all declared dependencies satisfy the manifest.

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

Conceptually, each manifest record has the same dependency semantics as one
`install` operation.  Operationally, however, `sync` SHALL treat the manifest as
a set requiring complete preflight rather than invoking the public `install`
command sequentially for each line.

`sync` SHALL:

1. parse and validate the complete manifest before dependency acquisition or
   publication;
2. enforce the selected destination-root policy for every declaration;
3. detect duplicate identities, duplicate destinations, malformed records, and
   other manifest errors before mutation;
4. inspect each declared destination and calculate its digest when present;
5. accept already-correct destinations without downloading replacements;
6. identify missing or mismatched destinations as requiring acquisition;
7. acquire every required replacement candidate into project-controlled staging;
8. verify every acquired candidate against its declared SHA-256 digest;
9. avoid intentional publication of the staged replacement set if any candidate
   fails acquisition or verification;
10. create missing destination parent directories only after complete manifest
    validation and candidate preflight have succeeded and when needed for
    publication;
11. publish only verified candidate bytes;
12. perform a final verification of every declared destination after publication;
13. return success only when the resulting declared dependency state satisfies
    the manifest.

An existing mismatched destination SHALL remain untouched until its replacement
candidate has been acquired and verified successfully.

A failed acquisition or digest mismatch SHALL NOT destroy a previously existing
destination merely because that destination is stale.

### Shared implementation without shell re-evaluation

`install` and `sync` SHOULD share parsing, validation, inspection, acquisition,
verification, and publication helpers where practical.

`sync` SHALL NOT implement that reuse by constructing shell command strings,
prefixing manifest text with `bashdeps.bash install`, invoking `eval`, sourcing
manifest lines, or otherwise passing manifest content back through a shell
parser.

The manifest syntax is data syntax.  The CLI syntax is process-argument syntax.
They intentionally share named fields, but they reach the shared implementation
through different parsing boundaries.

This distinction allows manifest values to contain characters such as `&` or
additional `=` characters without giving those characters shell control
semantics.

### No pruning in version 1

`sync` SHALL NOT remove files merely because they are absent from the current
manifest.

If a dependency declaration is removed, any old destination left in the working
tree becomes ordinary undeclared repository state.  Cleanup belongs to the
consumer's Makefile, `make clean`, explicit project policy, or a future operation
with separately defined deletion semantics.

This decision follows the narrower ownership model: bashdeps manages the paths
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

### File type and permissions

Dependency acceptance SHALL be based on byte identity, not artifact type or
executable mode.

Version 1 SHALL not add a permissions field to the manifest.

Publication SHALL use a conservative ordinary-file mode as defined by the
filesystem/publication ADR.  Consumers that require a particular mode may apply
it as part of their own build or preparation policy.

The named-field grammar intentionally leaves room for a future explicitly defined
field such as:

```text
mode=0775
```

if a demonstrated requirement later justifies making file mode part of the
materialization contract.  Until such a field is formally introduced, unknown
fields remain invalid under ADR-002.

### Concurrency

Version 1 SHALL make no guarantee that simultaneous mutating `install` or `sync`
processes operating on the same destinations are safe.

The initial implementation SHALL not introduce locking, process coordination, or
repository-level concurrency management solely to address that scenario.

If a demonstrated consumer need later requires concurrent mutation semantics,
that behavior SHALL be defined by a separate ADR.

## Considered Alternatives

### Expose only `sync` and `verify`

This keeps the command surface smaller, but the named-field grammar naturally
defines a useful one-artifact operation.  `install` gives callers a direct way to
materialize a dependency without constructing a temporary manifest and provides
a clear conceptual unit beneath manifest synchronization.

### Implement `sync` as a literal loop over `bashdeps.bash install`

This would make the relationship between manifest records and the CLI especially
literal.

It was rejected because sequential public-command invocation could publish early
records before discovering a malformed declaration, failed download, or bad
digest in a later record.  `sync` instead reuses the same semantics internally
while preserving complete manifest preflight and staged-set verification.

### Redownload every dependency during `sync` or `install`

This would simplify state inspection, but it would make repeated operations
needlessly network-dependent and discard the manifest digest's usefulness as a
cache-validity key.

### Accept any existing destination without hashing it

This reproduces the stale-cache failure that motivated the project.  Presence is
not proof of identity.

### Make `verify` repair incorrect state

Combining diagnosis and mutation would make offline validation impossible to
reason about and blur command intent.  Repair belongs to `sync` or `install`.

### Prune undeclared files automatically

Automatic pruning provides stronger whole-tree convergence when a tool owns a
managed root.  Bashdeps does not claim such ownership in version 1, so deleting
undeclared repository files would be an unnecessarily broad mutation.

### Skip final verification after publication

The implementation could assume that verified candidate bytes remain correct
after publication.  A final verification pass is slightly more work but proves
the state actually present at the declared destinations and keeps successful
operation semantics straightforward.

### Add locking in version 1

A lock protocol could prevent simultaneous mutation of the same dependency set.
This was deferred because no current consumer requirement justifies the added
state, stale-lock handling, portability decisions, and failure semantics.

## Consequences

A manifest record and an explicit `bashdeps.bash install` invocation use the same
named properties, reducing the conceptual gap between file-based and direct use.

Repeated `sync` and `install` operations avoid network access for dependencies
whose existing bytes already match their declaration.

Stale, modified, or corrupted destinations are detected uniformly through digest
comparison without special version-upgrade logic.

Offline users can run `bashdeps.bash verify` without risk of network access or
intentional mutation.

Whole-manifest `sync` retains stronger preflight behavior than a literal
line-by-line sequence of public `install` invocations.

Removing a manifest entry does not automatically remove its old destination.
Consumers that want a fully clean generated dependency tree should continue to
use their own clean target or explicit cleanup policy.

Successful `sync` has a strong and understandable postcondition: every declared
destination exists and matches its approved digest.  Successful `install` has the
same postcondition for its one declared artifact.

The project accepts that unpredictable failures during multi-file publication can
produce partial state and makes no stronger atomicity claim.

Managed dependencies can be scripts, libraries, templates, data files, images,
or other ordinary files because no executability assumption is part of the byte
identity contract.

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
- Related to: ADR-007
- Related to: ADR-013
- Derived from: `bash-dependency-convergence-handoff.md`
