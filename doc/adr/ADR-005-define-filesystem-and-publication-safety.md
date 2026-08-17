# ADR-005: Define Filesystem and Publication Safety

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines how `bashdeps` interprets repository-relative destinations and
how verified candidate bytes are published without allowing obvious path escape,
symlink redirection, or destructive replacement behavior.

The project cannot honestly promise filesystem-wide transactionality or immunity
from every race that can occur when another process mutates the same paths
concurrently.  Version 1 instead defines a conservative single-process
publication model and explicitly leaves concurrent mutation outside its contract.

## Context

ADR-002 allows a dependency destination to be any repository-relative path rather
than restricting all artifacts to `vendor/`.  That flexibility is useful for
libraries, templates, data files, images, and other build inputs, but it means the
tool must enforce the repository boundary directly.

Textual rejection of absolute paths and `..` traversal is necessary but not
sufficient.  A destination such as `vendor/file` can still escape the apparent
repository tree if `vendor` is a symbolic link to another location.  Likewise,
downloading directly over an existing destination can destroy usable bytes before
a replacement has been verified.

The project therefore needs explicit path, file-type, staging, replacement, and
cleanup rules.

## Decision Drivers

- Keep declared destinations within the invocation's project root.
- Reject path aliases that can bypass duplicate-destination checks.
- Reject symbolic-link redirection through destination paths.
- Preserve existing files until verified replacement bytes are ready.
- Avoid writing network output directly to final destinations.
- Make each individual replacement as conservative as ordinary portable
  filesystem operations permit.
- Avoid claiming multi-file atomicity.
- Keep file purpose and executability outside the byte-identity contract.
- Permit arbitrary ordinary files rather than only Bash libraries.

## Decision

### Project root

The project root for one `bashdeps` invocation SHALL be the physical current
working directory from which `bashdeps` is invoked.

Destination paths SHALL be interpreted relative to that root, not relative to the
manifest file's directory and not by discovering a Git repository root.

`bashdeps` SHALL NOT require Git metadata to determine destination placement.

Consumers are therefore expected to invoke `bashdeps` from the repository or
project root whose paths the manifest describes.  Make integration SHOULD do so
explicitly.

### Canonical textual destination form

A version 1 `dest` SHALL be a relative slash-separated path containing one or
more non-empty path components.

The following SHALL be rejected:

- absolute paths;
- an empty destination;
- a leading `/`;
- a trailing `/`;
- repeated `/` characters that create empty components;
- a component equal to `.`;
- a component equal to `..`.

Rejecting `.` components and repeated separators prevents multiple textual forms
such as `vendor/file`, `./vendor/file`, and `vendor//file` from naming the same
logical destination while evading duplicate checks.

Names beginning with `.` remain valid when the entire component is not exactly
`.` or `..`.  For example, `.config/template` is a valid relative destination.

### Destination containment

Before publication, `bashdeps` SHALL resolve the project root physically and
inspect the existing destination path component by component.

No existing destination component below the project root may be a symbolic link.

The final destination itself, when it already exists, SHALL NOT be a symbolic
link.

A destination whose existing path crosses a symbolic link SHALL be rejected even
when the symlink ultimately points back inside the project tree.  Version 1 uses
a simple fail-closed rule rather than attempting to distinguish safe and unsafe
symlink targets.

### Existing destination types

An existing destination is acceptable for digest inspection only when it is an
ordinary regular file and is not a symbolic link.

Existing directories, FIFOs, sockets, device nodes, or other special file types
at the declared destination SHALL cause the operation to fail.

`bashdeps` SHALL NOT replace a directory or special file with downloaded bytes.

### Parent directory creation

Missing parent directories MAY be created when publication is required.

For `sync`, missing parent directories SHALL NOT be created until the complete
manifest has been parsed and validated and all required network candidates have
been acquired and verified successfully.

For `install`, missing parent directories SHALL NOT be created until the complete
single-artifact declaration has been validated and its required candidate has
been acquired and verified successfully.

Before creating a missing directory, every existing ancestor between the project
root and that directory SHALL pass the no-symlink rule.

Directories created by `bashdeps` MAY remain after an unpredictable failure
during publication.  Version 1 does not attempt to roll back directory creation
as a filesystem-wide transaction.

### Staging

Network downloads SHALL be written to a project-controlled staging location and
not directly to declared destinations.

Staging names SHALL be private implementation details but MUST be unambiguously
associated with `bashdeps` so ordinary failure cleanup cannot target unrelated
files.

For multi-record `sync`, all required candidates SHALL be acquired and verified
in staging before intentional publication of any replacement begins.

Staging content SHALL be removed after ordinary success or handled failure where
practical.

A later invocation MAY remove clearly identifiable stale `bashdeps` staging state
left by an interrupted prior invocation.  Cleanup SHALL be narrowly scoped and
SHALL NOT use broad filename matching that could remove unrelated project files.

### Publication

A verified candidate SHALL be copied or materialized to a temporary ordinary
file in the final destination's parent directory before final replacement when
that is necessary to obtain same-filesystem rename behavior.

The destination-adjacent temporary file SHALL itself be treated as generated
`bashdeps` state and SHALL not be exposed as a successful final dependency.

Where the platform permits, final replacement SHOULD use rename-style replacement
within the destination directory so each individual file transition is as
conservative as practical.

An existing mismatched destination SHALL remain untouched until the replacement
candidate has been verified and the publication step is ready.

If publication of one file fails during a multi-file `sync`, `bashdeps` SHALL
report failure accurately.  It SHALL NOT claim that the entire dependency set was
updated atomically.

A subsequent `sync` SHALL inspect actual destination digests and converge from the
state that really exists.

### Final verification

After publication, `install` SHALL re-hash its final destination and succeed only
when the final bytes match the approved digest.

After publication, `sync` SHALL re-hash every declared destination and succeed
only when the complete declared set matches the manifest.

This final pass protects the observable destination state rather than assuming
that a successful staging digest or copy operation proves the final file.

### File mode

Version 1 SHALL treat mode as filesystem metadata separate from artifact byte
identity.

Newly published files SHALL use mode `0644`.

An already-correct existing destination SHALL be accepted based on digest and
SHALL NOT be chmodded merely to normalize its mode.

`verify` SHALL ignore mode entirely.

This asymmetry is intentional: version 1 promises exact bytes, not exact
filesystem metadata.  The explicit `0644` publication mode avoids assuming that
downloaded artifacts are executable while giving newly materialized ordinary
files a predictable non-executable mode.

A future ADR MAY add a named manifest field such as `mode=0775` if consumers need
mode to become part of the materialization contract.

### Executability and artifact type

`bashdeps` SHALL NOT infer executable permission from:

- a `.bash`, `.sh`, or other filename extension;
- a shebang;
- dependency identity;
- URL;
- file contents.

A managed dependency may be a library, script, template, data file, image, or
another ordinary file.  Consumers that need execution permission in version 1
must apply it explicitly outside `bashdeps`.

### Concurrency and race limits

Version 1 does not define safe concurrent mutation of the same destination paths.

Path validation and publication reduce predictable symlink and traversal risks in
the ordinary single-process model, but a hostile or concurrent local process may
change filesystem state between checks and writes.  A pure Bash implementation
cannot honestly claim the same race-resistant path-resolution guarantees as a
lower-level implementation using directory file descriptors and `openat`-style
APIs.

This limitation is accepted for version 1 and SHALL be documented rather than
hidden behind stronger security language.

## Considered Alternatives

### Restrict every destination to `vendor/`

This makes containment easier to describe but unnecessarily prevents legitimate
repository-relative destinations elsewhere in the project.  Direct path safety
rules provide the required boundary without coupling the tool to one directory
name.

### Allow symlinked parents when the resolved target remains inside the project

This could support more repository layouts but requires robust canonicalization
and creates additional race and policy complexity.  Version 1 rejects symlinks
uniformly.

### Follow destination symlinks

This would make `bashdeps` behave like ordinary shell redirection, but a manifest
path could then write outside the apparent project tree.  The behavior is
rejected.

### Download directly to the destination

This is simpler but can destroy a previously usable file when a transfer is
partial, fails, or has the wrong digest.  Staging is mandatory.

### Stage only beside each destination from the beginning

Destination-adjacent staging makes rename replacement convenient but may require
creating destination directories before the complete candidate set has passed
preflight.  Version 1 separates network staging from final destination-adjacent
publication so `sync` can verify all required downloads before intentionally
creating publication paths.

### Preserve upstream or executable file modes

HTTP artifact retrieval does not reliably transport Unix mode metadata, and
filename or content inspection would introduce heuristics unrelated to byte
identity.  Version 1 publishes ordinary files as `0644` and leaves richer mode
semantics for a future named field.

### Publish new files as `0600`

This is more restrictive, but the intended artifacts are repository build inputs
rather than secrets.  `0644` is a conventional non-executable ordinary-file mode
and avoids requiring every consumer to make basic downloaded inputs readable.
Private/authenticated artifact support remains outside version 1.

### Claim multi-file atomic synchronization

Portable filesystems do not provide a simple transaction covering independent
paths.  Whole-set preflight reduces predictable partial updates but does not make
publication globally atomic.

## Consequences

Manifest destinations remain flexible while obvious repository escape through
absolute paths, traversal components, textual aliases, and symlinked path
components is rejected.

Network failures and bad digests do not overwrite existing destinations.

A successful operation verifies the bytes at the actual final destination rather
than only the staged candidate.

New artifacts are non-executable by default, which allows the same mechanism to
materialize code and non-code inputs without guessing their intended use.

Consumers that need executable mode must apply it separately in version 1.

The project accepts that interruption or unexpected publication failure may leave
narrowly scoped temporary state or newly created parent directories, and that
multi-file publication is not globally atomic.

The project also accepts that version 1 does not attempt race-resistant concurrent
filesystem mutation beyond ordinary conservative Bash checks.

## Open Questions and Follow-Ups

Subsequent ADRs need to define:

- exact external command requirements used for path and file operations;
- diagnostics and exit statuses for unsafe paths and publication failures;
- Make cleanup behavior for generated dependency and staging state;
- whether future mode, cache, or project-root configuration fields become
  justified by real consumers.

## Related Decisions

- Related to: ADR-000
- Related to: ADR-001
- Related to: ADR-002
- Related to: ADR-003
- Related to: ADR-004
