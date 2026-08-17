# ADR-009: Define Build and Release Artifact Contract

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the maintained source, generated consumer artifacts, build
metadata, checksums, and transformation boundary for bashdeps releases.

## Context

The project needs one maintained implementation while serving two useful release
forms: a developer-oriented artifact retaining source comments and a smaller
ordinary consumer artifact with full-line source comments removed.

An earlier design discussion also considered minification.  Minification has been
removed from this project and belongs to a separate concern.  Bashdeps will not
carry a minifier dependency or generate a minified release artifact.

Generated files must not become independent source copies.  The build should be
narrow, deterministic from explicit inputs where practical, and validated through
the same public behavior tests as maintained source.

During version 1 review, the release checksum convention was changed from one
aggregate `SHA256SUMS` file to one checksum companion per published Bash artifact.
This keeps each artifact and its approved SHA-256 identity adjacent and makes the
relationship explicit from the filename.

## Decision Drivers

- Preserve one maintained Bash implementation.
- Provide a readable release artifact for debugging and review.
- Provide a normal consumer artifact without source-comment bulk.
- Avoid minification or broader source rewriting inside bashdeps.
- Embed sufficient release identity to diagnose the artifact in use.
- Verify generated artifacts independently rather than assuming transformation
  correctness.
- Publish a directly associated SHA-256 identity for every Bash release artifact.
- Keep release asset naming predictable for bootstrap consumers.

## Decision

The canonical maintained implementation SHALL be:

```text
src/bashdeps.bash
```

Maintainers SHALL edit that file rather than generated distribution artifacts.

The executable program name SHALL be `bashdeps.bash`.  Documentation and public
CLI examples SHALL use that filename rather than an extensionless `bashdeps`
command name.

`make build` SHALL generate:

```text
dist/bashdeps.dev.bash
dist/bashdeps.dev.bash.256
dist/bashdeps.bash
dist/bashdeps.bash.256
```

It SHALL NOT generate `dist/SHA256SUMS`.

### bashdeps.dev.bash

`dist/bashdeps.dev.bash` SHALL retain the maintained implementation's explanatory
and source-documentation comments, while receiving generated release metadata and
a canonical executable shebang/header as necessary.

It is a release artifact, not maintained source.

Its checksum companion SHALL be:

```text
bashdeps.dev.bash.256
```

### bashdeps.bash

`dist/bashdeps.bash` SHALL be the normal consumer artifact and the canonical
release filename for ordinary use.

It SHALL contain the same executable implementation and release metadata as the
developer artifact, with full-line source comments removed by the build process.
The transformation SHALL NOT deliberately rewrite executable statements,
expressions, quoting, whitespace inside executable lines, strings, or embedded
data.

The artifact SHALL retain a valid Bash shebang and SHALL be executable.

Its checksum companion SHALL be:

```text
bashdeps.bash.256
```

### No minified artifact

Bashdeps SHALL NOT generate `bashdeps.min.bash` and SHALL NOT depend on a Bash
minifier as part of its build.

If a separate project later minifies Bash artifacts, that output is outside the
bashdeps release contract unless a future ADR explicitly changes this decision.

### Behavioral equivalence

The maintained source, `dist/bashdeps.dev.bash`, and `dist/bashdeps.bash` SHALL be
subject to the same public behavior suite.

A generated artifact SHALL NOT be considered valid merely because maintained
source tests pass.  Any comment-removal transformation that changes observable
behavior is a build failure.

### Build metadata

Generated artifacts SHALL embed:

- semantic version;
- source revision timestamp/build date;
- source commit identifier.

Release builds SHALL receive the release version explicitly from automation or
Make inputs.  Development builds MAY use a documented development version.

Git MAY be used at build time to derive source metadata when available.  Runtime
operation SHALL NOT require Git.

### Per-artifact SHA-256 files

`make build` SHALL calculate SHA-256 digests after each Bash artifact has been
fully generated and SHALL write one companion checksum file for each artifact:

```text
bashdeps.dev.bash.256
bashdeps.bash.256
```

Each checksum file SHALL use conventional checksum-tool syntax containing the
SHA-256 digest and the corresponding artifact filename, for example:

```text
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  bashdeps.bash
```

This permits direct verification from the distribution directory with commands
such as:

```text
sha256sum -c bashdeps.bash.256
```

or the supported `shasum` equivalent.

The checksum files SHALL describe final published bytes, not intermediate files.

Release automation SHOULD publish each Bash artifact together with its matching
`.256` companion.  Consumers are expected to pin the SHA-256 digest of the
specific `bashdeps.bash` artifact they bootstrap rather than treating a remotely
retrieved checksum file as an automatically trusted source.

### Generated-state discipline

`dist/` SHALL be treated as generated state.  Generated Bash artifacts and `.256`
files SHALL NOT be edited directly.

The build SHALL use temporary output paths and rename-style publication so an
interrupted build does not intentionally leave a partially written final
artifact or checksum file.

## Considered Alternatives

### Publish only bashdeps.bash

One artifact is operationally smaller, but retaining a comment-rich generated
artifact is useful for release debugging, inspection, and downstream review while
still preserving one maintained source.

### Commit generated artifacts as maintained files

This creates multiple editable sources of truth and invites drift.  Generated
artifacts remain build products.

### Generate a minified artifact

Minification can provide smaller bytes but introduces a substantially stronger
source transformation and another build dependency.  That concern has been moved
to a separate project.

### Strip inline comments and normalize executable whitespace

More aggressive transformation saves additional bytes but begins to overlap with
minification and can change shell semantics.  Version 1 removes only full-line
source comments.

### Publish one aggregate SHA256SUMS file

A conventional aggregate file is compact and familiar, and it was the initial v1
design.  It was replaced during review by per-artifact `.256` companions because
the latter make the relationship between an artifact and its checksum explicit in
the filename and fit the intended bootstrap workflow more directly.

### Use an extensionless executable name

An extensionless `bashdeps` command would resemble an installed system command,
but the project distributes a standalone Bash artifact intended to be vendored or
bootstrapped directly.  The `.bash` suffix makes the artifact type explicit and
matches the release filename consumers actually execute.

## Consequences

Release testing has three execution surfaces: maintained source and two generated
artifacts.

Build logic must distinguish full-line comments from executable content
conservatively.  Source constructs that make comment removal unsafe must either be
handled correctly or cause the transformed artifact tests to fail.

The ordinary consumer artifact remains readable Bash rather than minified output.

Every published Bash artifact has one directly named checksum companion.
Consumers can independently verify the exact published artifact they intend to
bootstrap.

Documentation and examples consistently invoke `bashdeps.bash`, reducing ambiguity
between the product name and the actual distributed executable filename.

## Open Questions and Follow-Ups

Release automation will need to pass semantic version metadata into the Make
build and publish the four generated assets.  Exact GitHub Actions mechanics are
an automation concern rather than part of this artifact contract.

## Related Decisions

- Related to: ADR-001
- Related to: ADR-006
- Related to: ADR-007
- Related to: ADR-008
- Related to: ADR-011
