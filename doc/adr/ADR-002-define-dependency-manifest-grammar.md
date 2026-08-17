# ADR-002: Define the Dependency Manifest Grammar

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the version 1 syntax and validation rules for the dependency
manifest consumed by `bashdeps`.

The format is deliberately small, line-oriented, human-readable, and parseable
with ordinary Bash primitives.  It is not intended to become a general package
metadata language.

## Context

`bashdeps` needs a committed source of truth that declares the exact external
artifacts a consuming repository expects.  The format must communicate four
separate concerns without requiring JSON, YAML, `jq`, shell evaluation, or a
custom parser for a hierarchical syntax:

- dependency identity for people and automation;
- retrieval location;
- repository-relative installation destination;
- approved SHA-256 byte identity.

The handoff documents proposed a four-field `dependencies.txt` format separated
by horizontal whitespace.  Subsequent design decisions established that SHA-256
remains mandatory even when upstream does not publish checksums, destinations
may be any repository-relative path, dependency identity remains opaque to the
Bash implementation, and the conventional manifest filename may be omitted from
ordinary CLI invocation.

## Decision Drivers

- Keep parsing deterministic and inspectable.
- Avoid shell evaluation of manifest content.
- Keep records convenient for human review.
- Keep the format straightforward for tools such as Renovate to inspect later.
- Preserve exact byte verification as a mandatory property.
- Permit destinations outside `vendor/` without permitting path escape.
- Reject ambiguous or permissive syntax rather than guessing user intent.
- Keep version 1 small enough to specify completely.

## Decision

The conventional manifest filename SHALL be:

```text
dependencies.txt
```

A dependency record SHALL contain exactly four fields:

```text
IDENTITY  URL  DESTINATION  DIGEST
```

Fields SHALL be separated by one or more horizontal whitespace characters:
spaces or tabs.  Fields themselves SHALL NOT contain literal spaces or tabs.

Conceptually, the separator grammar is:

```text
[[:blank:]]+
```

The implementation MAY use Bash `IFS` and `read` rather than a regular
expression to split records.

Blank lines SHALL be ignored.

A line whose first non-horizontal-whitespace character is `#` SHALL be treated
as a comment and ignored.

Inline comments SHALL NOT be part of version 1.  Once parsing of a dependency
record begins, every non-separator token is a field; a fifth token, even if it
begins with `#`, SHALL make the record invalid.

### Identity

`IDENTITY` SHALL be a non-empty, non-whitespace token.

Identity SHALL be unique within a manifest.

`bashdeps` SHALL otherwise treat identity as opaque metadata.  It SHALL NOT
interpret semantic versions, package ecosystems, GitHub repository names, tags,
or release naming from the field.

The recommended convention is:

```text
PACKAGE@VERSION
```

For example:

```text
wesley-dean/mktext@0.0.7
```

This convention exists for people and external automation and is not a package
resolution contract enforced by `bashdeps`.

### URL

`URL` SHALL be an absolute HTTPS URL beginning with:

```text
https://
```

Other schemes, including `http://`, `file://`, `ftp://`, and scheme-relative
URLs, SHALL be rejected in version 1.

Detailed redirect, timeout, retry, and transport behavior SHALL be defined by a
separate acquisition-policy ADR.

### Destination

`DESTINATION` SHALL identify a repository-relative path.

Absolute paths SHALL be rejected.

Paths containing a `..` path component SHALL be rejected.

A destination SHALL NOT be required to live beneath `vendor/`.  A consuming
repository may declare another repository-relative location when appropriate.

Destination paths SHALL be unique within a manifest.  Two identities SHALL NOT
map to the same destination.

Missing destination parent directories MAY be created by synchronization after
the complete manifest has passed validation.

Publication through symbolic-link path components SHALL be rejected as defined
by the filesystem-safety ADR.  This grammar ADR establishes only that the
textual destination must be repository-relative and traversal-free.

### Digest

`DIGEST` SHALL use this version 1 syntax:

```text
sha256:<64 lowercase hexadecimal characters>
```

For example:

```text
sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

The digest SHALL be mandatory for every dependency record.

Placeholders such as `-`, `none`, or `nohash` SHALL be invalid.

Uppercase hexadecimal SHALL be rejected rather than normalized.  Requiring one
canonical spelling keeps manifests deterministic and simplifies review and
machine-generated updates.

Unknown digest algorithms SHALL fail closed.

### Record count and duplicate handling

Each non-comment, non-blank record SHALL contain exactly four fields.

Too few or too many fields SHALL make the manifest invalid.

Duplicate identities SHALL be errors.

Duplicate destinations SHALL be errors.

The same URL MAY appear in multiple records when destinations and identities are
otherwise distinct.

The same digest MAY appear in multiple records.

### Parsing and evaluation safety

Manifest content SHALL be treated as data.

`bashdeps` SHALL NOT `source` or `eval` the manifest.

Shell parameter expansion, command substitution, arithmetic expansion,
backslash escapes, quoting syntax, glob expansion, or environment-variable
interpolation SHALL NOT be performed on manifest fields.

Characters that would have shell meaning in executable code SHALL remain literal
field data when they are otherwise valid under the field-specific grammar.

### Manifest path selection

The CLI SHALL accept an explicit manifest path where the operation supports a
manifest argument.

When no manifest path is supplied, `bashdeps` SHALL use:

```text
dependencies.txt
```

The manifest path itself is a CLI input and is not subject to the destination
path grammar above.

## Considered Alternatives

### JSON

JSON would support richer metadata but would require a JSON parser, a dependency
such as `jq`, or an unsafe partial parser written in Bash.  Version 1 does not
need hierarchical data, so the additional complexity is unjustified.

### YAML

YAML is even less appropriate for a deliberately tiny Bash parser because the
syntax is substantially more complex than the data model requires.

### Shell syntax

A manifest consisting of assignments, arrays, or sourced Bash code would be easy
to consume, but it would turn trusted dependency metadata into executable shell
input and unnecessarily expand the attack surface.

### Optional digests

A placeholder could represent dependencies without upstream-published hashes.
This was rejected by ADR-001 because the consuming project can compute and
commit the digest of the exact approved artifact itself.

### Restrict destinations to `vendor/`

This would create a stronger repository convention but is not required for safe
artifact materialization.  Consumers may have legitimate repository-relative
locations outside `vendor/`.  Path safety is enforced directly rather than by
requiring one directory name.

### Permit inline comments

Inline comments make human annotation convenient but introduce ambiguity because
fields are intentionally unquoted and whitespace-delimited.  Full-line comments
are sufficient for version 1.

### Require `PACKAGE@VERSION` syntax

Strictly interpreting identity would couple `bashdeps` to version semantics and
package naming that it otherwise deliberately ignores.  The convention remains
recommended rather than mandatory.

## Consequences

The manifest can be parsed using straightforward Bash primitives and validated
completely before any network or filesystem publication begins.

Human reviewers can see identity, source, destination, and approved digest in one
record without navigating nested metadata.

Consumers that need whitespace inside URLs or destination filenames cannot
represent those paths in version 1.  This is an accepted simplification.

External dependency-update tooling can build on the stable four-field record and
recommended `PACKAGE@VERSION` convention without requiring `bashdeps` itself to
understand that automation.

Changing the grammar after release may affect both Bash consumers and external
automation, so extensions should be deliberate and backward-compatible where
practical.

## Open Questions and Follow-Ups

Subsequent ADRs need to define:

- exact synchronization and verification semantics;
- URL redirect, retry, timeout, and transport behavior;
- symbolic-link and filesystem publication safety;
- diagnostics and exit statuses;
- whether a future manifest-format version marker is needed before incompatible
  grammar changes are introduced.

## Related Decisions

- Related to: ADR-000
- Related to: ADR-001
- Derived from: `bash-dependency-manifest-handoff.md`
- Derived from: `bash-dependency-convergence-handoff.md`
