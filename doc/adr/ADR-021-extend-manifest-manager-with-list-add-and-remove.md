# ADR-021: Extend Manifest Manager with List, Add, and Remove

Date: 2026-09-09

## Status

Accepted

## Intent and Scope

This Architecture Decision Record extends `manifest-manager.bash` beyond the
initial `update` operation introduced by ADR-020.  It defines conservative
maintainer-facing contracts for three additional subcommands:

```text
manifest-manager.bash list ...
manifest-manager.bash add ...
manifest-manager.bash remove ...
```

Issue #17 requested these operations after the manifest-manager foundation from
issue #16 was complete.  This decision keeps all three operations within the
source-maintenance boundary already established by ADR-020.  They do not change
`bashdeps.bash`, its runtime trust model, the manifest grammar, or the separation
between approved manifest source and runtime artifact synchronization.

This ADR defines all three command contracts so their relationship is deliberate
rather than accumulated independently.  The first implementation increment adds
`list`.  `add` and `remove` may land in later reviewable increments while remaining
governed by this decision.

## Context

ADR-020 introduced `manifest-manager.bash` as a second first-class executable and
intentionally limited its initial mutation behavior to surgical updates of
already-declared dependencies.  That implementation now provides a validated
logical view of each manifest record while retaining exact physical record and
surrounding source bytes.

The distinction between logical and physical representations is important for the
new operations.  `list` needs a stable inspection form without serializing the
manifest.  `add` needs to append one deliberately supplied declaration without
changing any pre-existing byte.  `remove` needs to delete exactly one logical
record without silently treating nearby comments or blank lines as part of that
record.

The manager must also continue to support human use, Make, CI, shell pipelines,
and stdin/stdout workflows without introducing JSON or another serialization
layer.  The existing `-f, --filename FILE` convention should remain coherent
across commands even though read-only and mutating stream operations have
different output contracts.

## Decision Drivers

- Preserve the ADR-001 and ADR-020 runtime trust boundary.
- Keep existing manifest bytes reviewable and unchanged unless a requested
  mutation explicitly targets them.
- Avoid interpreting opaque bashdeps identities more narrowly than necessary.
- Make output deterministic and useful in ordinary Unix pipelines.
- Fail rather than guess when selection or mutation is ambiguous.
- Avoid package-manager behavior, semantic-version logic, registries, or
  transitive dependency resolution.
- Avoid JSON output and unnecessary runtime dependencies.
- Keep command-specific help part of the supported public CLI contract.
- Reuse validated manifest parsing without reserializing existing records.
- Keep future implementation increments small enough to review independently.

## Decision

### Keep the source-maintenance boundary

`list`, `add`, and `remove` SHALL remain operations of `manifest-manager.bash`.
They SHALL NOT be added to `bashdeps.bash`.

`bashdeps.bash` continues to consume already-approved declarations and verify exact
artifact bytes.  Manifest-manager mutations prepare source changes for review and
commit.  No new command authorizes retrieved bytes dynamically during bashdeps
runtime synchronization.

### Define `list` as complete identity inspection

The public form is:

```text
manifest-manager.bash list [OPTIONS]
```

with:

```text
-f, --filename FILE
-h, --help
-V, --version
```

The default filename remains `dependencies.txt`.

On success, `list` SHALL emit each complete validated `id` value exactly as it
appears logically in the manifest, one identity per line, in manifest order.
An empty valid manifest produces no output and succeeds.

`list` SHALL NOT strip version text, reinterpret identities as GitHub package
coordinates, emit complete logical records, or normalize source merely to display
it.  The `id` field is opaque to `bashdeps.bash`; a read-only inspection command
has no reason to impose the narrower `OWNER/REPO@VERSION` convention used by
`update`.

`list` SHALL parse and validate the complete manifest before emitting the first
identity.  Invalid input therefore produces no partial list.

`-f -` is meaningful for `list`: the complete manifest is read from STDIN and the
identity list is written to STDOUT.  Unlike mutating stream operations, a failed
`list` operation emits no manifest rollback representation because STDOUT belongs
to list data, not transformed source.

`list` SHALL require no network access, GitHub interpretation, or SHA-256 command.

### Define `add` as explicit declaration append

The public form SHALL accept exactly one complete declaration supplied through the
same four named fields as the manifest grammar:

```text
manifest-manager.bash add [OPTIONS] \
  id=VALUE url=VALUE dest=VALUE digest=sha256:HEX
```

The four fields are mandatory.  Field order MAY be arbitrary, matching the
manifest grammar.  Unknown, duplicate, missing, or invalid fields fail.

The initial `add` operation SHALL NOT infer or invent:

- an artifact URL;
- an artifact filename;
- a destination path;
- a repository or hosting provider;
- a package convention; or
- a digest from remotely discovered content.

In particular, `OWNER/REPO@VERSION` alone is insufficient input for `add`.

The explicitly supplied declaration SHALL be validated against the complete
existing manifest before publication.  Duplicate identity or destination values
fail under the existing grammar rules.

Only newly appended bytes may be canonicalized.  Existing source bytes SHALL
remain an exact prefix of the successful candidate.  The new record SHALL use the
canonical one-line field order:

```text
id=... url=... dest=... digest=...
```

If the original manifest does not end with a line terminator, one separator SHALL
be appended before the new record.  The implementation SHALL preserve an observed
LF or CRLF convention when it can do so unambiguously and SHALL use LF when no
existing line-ending convention can be observed, including an empty file.  The
new record SHALL end with the selected line terminator.

`-f -` SHALL use the mutating stream transaction contract established by ADR-020:
complete candidate on success, complete captured original on failure after input
capture, with callers required to inspect the exit status.

Automatic candidate acquisition or digest calculation is not part of this
initial `add` contract.  A later explicit feature may propose it under a separate
review if a concrete workflow requires it.

### Define `remove` as exact identity record deletion

The public form SHALL be:

```text
manifest-manager.bash remove [OPTIONS] ID
```

`ID` means the complete `id` field value and must match exactly one logical record.
`remove` SHALL NOT reinterpret the argument as a GitHub package prefix or remove a
version component before matching.

Zero matches fail.  More than one matching record is already invalid manifest
state under the version-1 grammar and therefore also fails.

A successful removal deletes exactly the selected record's physical bytes,
including all physical continuation lines that belong to that logical record.
Comments and blank lines before or after the record SHALL remain independent
source chunks and SHALL NOT be implicitly attached to the dependency.  Removing a
record therefore does not guess whether nearby prose "belongs" to it.

The candidate SHALL preserve every remaining byte exactly.  Implementations SHALL
prove that the candidate corresponds to the original source with exactly the
selected record chunk omitted, then revalidate the complete candidate before
publication.

`-f -` SHALL use the same mutating stream rollback contract as `update` and `add`.

### Keep command help specific and composable

These forms SHALL succeed with status 0 and write help to STDOUT:

```text
manifest-manager.bash --help
manifest-manager.bash -h
manifest-manager.bash update --help
manifest-manager.bash list --help
manifest-manager.bash add --help
manifest-manager.bash remove --help
```

Top-level help SHALL summarize the available subcommands and common informational
forms.  Subcommand help SHALL document that command's syntax, arguments, options,
file/stream behavior, output contract, and relevant public exit categories.

A command that has not yet been implemented SHALL NOT be advertised as available
merely because this ADR defines its future contract.

### Preserve the existing public exit categories

The manager SHALL continue to use the ADR-020 public status range:

```text
0  success, help, version, or successful no-op
2  invalid CLI, manifest, dependency selection, or declaration
3  required runtime capability unavailable or unusable
4  release discovery or network acquisition failed
5  exact-mutation or preservation safety check failed
6  input, staging, filesystem, output, or publication failed
```

A command uses only categories relevant to its behavior.  `list`, for example,
normally uses 0, 2, and 6 and does not manufacture network or hashing failures for
capabilities it never needs.

### Reuse parsing while keeping mutation proofs operation-specific

The existing logical parser and exact source-chunk representation SHALL remain the
shared foundation.

The implementation SHALL NOT create a generalized rewrite engine that serializes
records from parsed fields.  Each mutation shape keeps a proof appropriate to its
operation:

- `update` replaces explicitly planned raw records and retains its reverse
  substitution proof;
- `add` proves that the original bytes are an exact prefix followed only by the
  explicitly constructed append sequence; and
- `remove` proves that the candidate is the original chunk sequence with exactly
  one selected record omitted.

Shared capture, staging, stream detection, cleanup, and publication lifecycle
helpers MAY be factored for reuse when doing so does not weaken command-specific
safety properties.

### Preserve product and release isolation

These commands extend the existing `manifest-manager.bash` executable family.
They do not create additional release products or change the twelve-file release
asset count established by ADR-020.

Manager-only code remains excluded from the `bashdeps.bash` source closure and
runtime requirements.

## Alternatives Considered

### List package names without versions

Rejected because it would impose the manager's GitHub-oriented update convention
on identities that are otherwise opaque manifest data.  Complete `id` values are
provider-neutral and unambiguous.

### List complete logical records

Rejected because pipelines typically need stable identifiers, while emitting
folded logical records would either normalize source or create an output format
that looks like source without preserving its physical representation.

### Remove by `OWNER/REPO` package prefix

Rejected because deletion does not require release semantics.  Exact complete-ID
selection is safer and works for identities unrelated to GitHub.

### Automatically associate adjacent comments with a removed record

Rejected because comment ownership is not represented by the manifest grammar.
Deleting comments based on proximity would guess author intent and weaken byte
preservation.

### Infer missing add fields from repository coordinates

Rejected because package coordinates do not determine artifact filename, release
asset choice, destination, or trust data.  Explicit source is preferable to
hidden convention.

### Calculate add digests automatically in the first implementation

Deferred.  Hashing explicitly selected candidate bytes can be reasonable, but it
introduces acquisition and trust-proposal questions that are unnecessary for the
core append operation.  A later explicit option can be designed if needed.

### Generalize all mutations into parse-and-reserialize behavior

Rejected because it would rewrite formatting, comments, line endings, physical
continuations, and other review-sensitive source bytes that are unrelated to the
requested operation.

### Add JSON output

Rejected.  Newline-delimited complete identities, command exit statuses, STDERR
diagnostics, and manifest streams provide sufficient Unix-oriented interfaces.

## Consequences

The manager gains a provider-neutral inspection operation before gaining new
mutation operations.  This creates a low-risk first increment for validating the
expanded subcommand and help architecture.

Later `add` and `remove` work has a defined contract and does not need to invent
selection, newline, comment ownership, or inference semantics during
implementation.

The conservative add interface requires callers to know all declaration fields.
That is intentional: explicit input keeps trust and destination decisions visible.

Removal may leave blank lines or comments that a human later considers untidy.
That is also intentional.  Source cleanup is a separate author decision rather
than an implicit side effect of deleting a dependency.

The project retains operation-specific preservation proofs, which means some
mutation code will remain specialized instead of being compressed into a single
abstraction.  The additional code is accepted in exchange for inspectability and
stronger review guarantees.

## Expected Outcomes

- Maintainers can inspect manifest identities with a deterministic plain-text
  command suitable for pipelines.
- Future dependency creation requires explicit source data rather than inferred
  package conventions.
- Future removal can delete one logical record without surprising comment or
  whitespace cleanup.
- Existing `update` behavior and the `bashdeps.bash` runtime contract remain
  unchanged.
- The manager can grow as a conservative manifest source CLI without drifting
  into generic package-manager behavior.

## Relationships

This decision extends ADR-020 without superseding its `update`, trust-boundary,
release, or product-isolation decisions.  It relies on ADR-002 for manifest field
semantics and uniqueness, ADR-015 for logical-record folding, ADR-014 and
`doc/documentation-standard.md` for maintained Bash documentation, and ADR-011's
general principle that executable CLIs rather than private Bash helpers form the
supported interface.
