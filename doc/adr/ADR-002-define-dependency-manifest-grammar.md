# ADR-002: Define the Dependency Manifest Grammar

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the version 1 syntax and validation rules for the dependency
manifest consumed by `bashdeps`.

The format is deliberately small, line-oriented, human-readable, and parseable
with ordinary Bash primitives.  It uses named fields so records remain
self-describing and can be extended deliberately without relying on positional
field meaning.  It is not intended to become a general package metadata
language.

## Context

`bashdeps` needs a committed source of truth that declares the exact external
artifacts a consuming repository expects.  The format must communicate four
separate concerns without requiring JSON, YAML, `jq`, shell evaluation, or a
custom parser for a hierarchical syntax:

- dependency identity for people and automation;
- retrieval location;
- repository-relative installation destination;
- approved SHA-256 byte identity.

The original handoff proposed four positional fields separated by horizontal
whitespace.  During architecture review, the project chose named `KEY=VALUE`
fields instead.  Named fields improve readability, allow field order to be
irrelevant, align naturally with a single-artifact `bashdeps install` command,
and provide a deliberate extension path for future metadata such as an optional
file mode without requiring positional-column changes.

The project has also established that SHA-256 remains mandatory even when
upstream does not publish checksums, destinations may be any repository-relative
path, dependency identity remains opaque to the Bash implementation, and managed
artifacts are not assumed to be executable or textual.

## Decision Drivers

- Keep parsing deterministic and inspectable.
- Avoid shell evaluation of manifest content.
- Keep records convenient and self-describing for human review.
- Make field ordering irrelevant.
- Keep the format straightforward for tools such as Renovate to inspect later.
- Preserve exact byte verification as a mandatory property.
- Permit destinations outside `vendor/` without permitting path escape.
- Permit `=` characters inside field values, especially URLs.
- Provide a controlled path for adding future named fields.
- Reject ambiguous or permissive syntax rather than guessing user intent.
- Keep version 1 small enough to specify completely.

## Decision

The conventional manifest filename SHALL be:

```text
dependencies.txt
```

Each dependency SHALL occupy one logical line.

A version 1 dependency record SHALL contain exactly these four named fields,
each exactly once:

```text
id=VALUE
url=VALUE
dest=VALUE
digest=VALUE
```

A conventional record may therefore look like:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

Field order SHALL NOT be significant.  For example, these records are
semantically equivalent:

```text
id=dep@1.0.0 url=https://example.com/dep dest=vendor/dep digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa dest=vendor/dep url=https://example.com/dep id=dep@1.0.0
```

Fields SHALL be separated by one or more horizontal whitespace characters:
spaces or tabs.  Field values SHALL NOT contain literal spaces or tabs in version
1.

Conceptually, the record is first split into components using:

```text
[[:blank:]]+
```

Each component SHALL then be split into a field name and value at the first,
left-most `=` character only.

For example:

```text
url=https://example.com/download?foo=bar&baz=quux
```

parses as:

```text
name  = url
value = https://example.com/download?foo=bar&baz=quux
```

Additional `=` characters after the first one belong to the value unchanged.

An implementation may express this operation using Bash parameter expansion
similar to:

```bash
name=${component%%=*}
value=${component#*=}
```

This example describes parsing semantics; it does not make manifest content shell
code.

A component without `=` SHALL be invalid.  A field name or value that is empty
SHALL be invalid.

Version 1 field names SHALL be exactly:

```text
id
url
dest
digest
```

Field names are lowercase and case-sensitive.  Duplicate field names SHALL be
errors.  Unknown field names SHALL be errors in version 1 rather than being
silently ignored.

Rejecting unknown fields allows an older `bashdeps` release to fail closed when
it encounters manifest semantics introduced by a newer release.  Future ADRs may
add named fields such as `mode=0775` without changing the fundamental
`KEY=VALUE` record structure.

Blank lines SHALL be ignored.

A line whose first non-horizontal-whitespace character is `#` SHALL be treated
as a comment and ignored.

Inline comments SHALL NOT be part of version 1.  Once parsing of a dependency
record begins, every whitespace-delimited component SHALL be a `KEY=VALUE` field.
A trailing token beginning with `#` SHALL therefore make the record invalid.

### `id`

The `id` value SHALL be a non-empty, non-whitespace token.

The `id` value SHALL be unique within a manifest.

`bashdeps` SHALL otherwise treat `id` as opaque metadata.  It SHALL NOT interpret
semantic versions, package ecosystems, GitHub repository names, tags, or release
naming from the value.

The recommended convention is:

```text
PACKAGE@VERSION
```

For example:

```text
id=wesley-dean/mktext@0.0.7
```

This convention exists for people and external automation and is not a package
resolution contract enforced by `bashdeps`.

### `url`

The `url` value SHALL be an absolute HTTPS URL beginning with:

```text
https://
```

Other schemes, including `http://`, `file://`, `ftp://`, and scheme-relative
URLs, SHALL be rejected in version 1.

The URL MAY contain additional `=` characters because only the first `=` in the
complete `url=VALUE` component separates the field name from its value.

Detailed redirect, timeout, retry, and transport behavior SHALL be defined by a
separate acquisition-policy ADR.

### `dest`

The `dest` value SHALL identify a repository-relative path.

Absolute paths SHALL be rejected.

Paths containing a `..` path component SHALL be rejected.

A destination SHALL NOT be required to live beneath `vendor/`.  A consuming
repository may declare another repository-relative location when appropriate.

Destination paths SHALL be unique within a manifest.  Two identities SHALL NOT
map to the same destination.

Missing destination parent directories MAY be created by synchronization after
the complete manifest has passed validation.

Publication through symbolic-link path components SHALL be rejected as defined
by the filesystem-safety ADR.  This grammar ADR establishes only that the textual
destination must be repository-relative and traversal-free.

### `digest`

The `digest` value SHALL use this version 1 syntax:

```text
sha256:<64 lowercase hexadecimal characters>
```

For example:

```text
digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

The digest SHALL be mandatory for every dependency record.

Placeholders such as `-`, `none`, or `nohash` SHALL be invalid.

Uppercase hexadecimal SHALL be rejected rather than normalized.  Requiring one
canonical spelling keeps manifests deterministic and simplifies review and
machine-generated updates.

Unknown digest algorithms SHALL fail closed.

### Record-level uniqueness and duplicate handling

Each non-comment, non-blank record SHALL contain all four required version 1
fields exactly once.

Missing, duplicate, or unknown fields SHALL make the manifest invalid.

Duplicate `id` values across records SHALL be errors.

Duplicate `dest` values across records SHALL be errors.

The same `url` value MAY appear in multiple records when destinations and
identities are otherwise distinct.

The same `digest` value MAY appear in multiple records.

### Parsing and evaluation safety

Manifest content SHALL be treated as data.

`bashdeps` SHALL NOT `source` or `eval` the manifest.

Shell parameter expansion, command substitution, arithmetic expansion,
backslash escapes, quoting syntax, glob expansion, or environment-variable
interpolation SHALL NOT be performed on manifest field values.

Characters that would have shell meaning in executable code SHALL remain literal
manifest data when they are otherwise valid under the field-specific grammar.

This distinction matters because a manifest record is not itself a shell command.
For example, `&` may appear literally inside a URL in `dependencies.txt` without
being treated as a shell control operator.

### Relationship to `bashdeps install`

The named manifest fields SHALL intentionally correspond to the named arguments
accepted by the single-artifact command described in ADR-003:

```text
bashdeps install id=VALUE url=VALUE dest=VALUE digest=VALUE
```

This symmetry is a usability property, not an instruction to execute manifest
lines as shell source.

When a human enters an `install` command through an interactive shell, ordinary
shell quoting rules apply before `bashdeps` receives the arguments.  A value
containing shell metacharacters may therefore require quoting, for example:

```bash
bashdeps install \
  id=example@1.0.0 \
  'url=https://example.com/download?foo=bar&baz=quux' \
  dest=vendor/example \
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

`sync` SHALL parse manifest records as data and SHALL NOT construct, `eval`, or
execute command strings by prefixing manifest lines with `bashdeps install`.
Shared implementation logic may be used internally without re-entering the shell
parser.

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

### Four positional fields

The original handoff proposed:

```text
IDENTITY URL DESTINATION DIGEST
```

This is compact and straightforward to parse, but readers and future extensions
must depend on field position.  Adding another property would create another
positional column and increase ambiguity.  Named fields preserve the same small,
line-oriented parser while making each record self-describing and extensible.

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

The chosen `KEY=VALUE` syntax resembles shell assignments visually but is parsed
as ordinary data and never sourced or evaluated.

### Silently ignore unknown named fields

Ignoring fields would make newer manifests appear compatible with older
`bashdeps` releases even when the older implementation does not understand the
new semantics.  Version 1 therefore fails closed on unknown names.  Extensions
remain possible by explicitly teaching a later version about new fields.

### Optional digests

A placeholder could represent dependencies without upstream-published hashes.
This was rejected by ADR-001 because the consuming project can compute and commit
the digest of the exact approved artifact itself.

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

Human reviewers can identify field meaning without remembering positional
columns, and field order can change without changing semantics.

URLs and other values may contain `=` without ambiguity because only the first
`=` in each component separates its name from its value.

Consumers that need literal spaces or tabs inside values cannot represent those
values in version 1.  This is an accepted simplification.

The named-field model gives the project a controlled extension path.  A later
release could define a field such as `mode=0775` while retaining the same record
structure.  Until such a field is formally defined, version 1 rejects it.

Managed artifacts remain byte-oriented rather than executable-oriented.  The
manifest can therefore describe libraries, scripts, templates, data files,
images, and other ordinary files without assigning execution semantics to them.

External dependency-update tooling can build on the stable named fields and
recommended `PACKAGE@VERSION` convention without requiring `bashdeps` itself to
understand package automation.

Changing field semantics after release may affect both Bash consumers and
external automation, so extensions should be deliberate and backward-compatible
where practical.

## Open Questions and Follow-Ups

Subsequent ADRs need to define:

- exact installation, synchronization, and verification semantics;
- URL redirect, retry, timeout, and transport behavior;
- symbolic-link and filesystem publication safety;
- diagnostics and exit statuses;
- whether a future manifest-format version marker is needed before incompatible
  grammar changes are introduced.

## Related Decisions

- Related to: ADR-000
- Related to: ADR-001
- Related to: ADR-003
- Derived from: `bash-dependency-manifest-handoff.md`
- Derived from: `bash-dependency-convergence-handoff.md`
