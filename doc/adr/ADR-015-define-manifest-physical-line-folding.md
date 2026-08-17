# ADR-015: Define Manifest Physical-Line Folding

Date: 2026-08-17

## Status

Proposed

## Intent and Scope

This Architecture Decision Record defines how a version 1 bashdeps manifest may
represent one logical dependency record across multiple physical lines.

ADR-002 remains authoritative for the named `KEY=VALUE` record grammar.  This ADR
does not change field names, field ordering, field validation, tokenization,
digest requirements, destination policy, or the rule that manifest data is never
sourced or evaluated.  It adds a small preprocessing step that folds indented
physical continuation lines into the same logical record before ADR-002 field
parsing begins.

The goal is to improve human readability without replacing the deliberately small
manifest grammar with a hierarchical configuration language.

## Context

ADR-002 defines each dependency as one logical line containing four named fields:

```text
id=VALUE url=VALUE dest=VALUE digest=VALUE
```

That representation is deterministic and easy to parse, but realistic URLs and
SHA-256 digests make individual physical lines long.  Long records are harder to
scan in reviews and make adjacent fields visually blend together.

A more readable representation is:

```text
id=wesley-dean/mktext@0.0.7
  url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash
  dest=vendor/mktext.bash
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

This should remain semantically identical to:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

The project considered moving to an INI-like structure, but doing so would create
a materially larger grammar and force decisions about sections, duplicate keys,
section identity, quoting, escaping, comments, continuation behavior, and parser
compatibility.  Physical-line folding provides the desired readability while
preserving the already-defined logical record grammar.

## Decision Drivers

- Improve manifest readability during ordinary review.
- Preserve the named-field grammar from ADR-002.
- Keep manifest parsing deterministic and inspectable in Bash.
- Avoid introducing a general-purpose configuration parser.
- Give indentation exactly one narrow meaning.
- Keep comments and blank lines semantically inert.
- Fail closed when indentation cannot be associated with an existing record.
- Preserve field-order independence.
- Preserve the rule that field values cannot contain literal horizontal whitespace.
- Keep future external tooling able to reason about stable `KEY=VALUE` fields.

## Decision

Version 1 manifests SHALL distinguish physical lines from logical records.

A logical record MAY occupy one physical line or multiple physical lines.

Line folding SHALL occur before the logical record is tokenized into fields.

### Physical-line classification

Each physical line SHALL be classified in this order:

1. A blank line contains only zero or more horizontal whitespace characters and
   SHALL be ignored.
2. A comment line is a line whose first non-horizontal-whitespace character is
   `#` and SHALL be ignored.
3. A non-comment content line beginning in column 1 SHALL begin a new logical
   record.
4. A non-comment content line beginning with one or more horizontal whitespace
   characters SHALL continue the current logical record.

For this ADR, horizontal whitespace means spaces or tabs.

Comments and blank lines are semantically invisible.  They neither begin a record
nor terminate the current record.

### Starting a logical record

A non-comment content line whose first character is not horizontal whitespace
SHALL start a new logical record.

If another logical record is already being accumulated, that previous record
SHALL be considered complete before the new record begins.

For example:

```text
id=one@1
  url=https://example.test/one
  dest=vendor/one
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
id=two@1
  url=https://example.test/two
  dest=vendor/two
  digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
```

contains two logical records.

### Continuing a logical record

A non-comment content line beginning with one or more spaces or tabs SHALL be a
continuation line.

The leading horizontal whitespace SHALL be removed from the continuation text.
The remaining continuation text SHALL be appended to the current logical record
with exactly one ASCII space between the existing logical text and the appended
text.

Therefore:

```text
foo
  bar
  bazzle
```

folds conceptually to:

```text
foo bar bazzle
```

For a valid bashdeps declaration:

```text
id=example@1
  url=https://example.test/example
  dest=vendor/example
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

folds to:

```text
id=example@1 url=https://example.test/example dest=vendor/example digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

The resulting logical text is then parsed exactly as ADR-002 specifies.

### Continuation without a current record

A continuation line encountered before any logical record has started SHALL make
the manifest invalid.

For example:

```text
  id=example@1
  url=https://example.test/example
```

is invalid because the first physical content line is indented and therefore
claims to continue a record that does not exist.

The parser SHALL fail rather than guessing that the indentation was accidental.

### Comments and blank lines within a folded record

Because comments and blank lines are ignored before folding semantics are applied,
they MAY appear between physical lines belonging to the same logical record.

For example:

```text
id=example@1
  url=https://example.test/example

  # Keep the artifact under the default dependency tree.
  dest=vendor/example
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

is semantically equivalent to:

```text
id=example@1 url=https://example.test/example dest=vendor/example digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

A comment or blank line does not terminate a record.  The next non-comment
physical content line determines whether the record continues or a new record
begins.

### Inline comments remain unsupported

This ADR does not add inline comments.

For example:

```text
id=example@1  # dependency identity
```

remains invalid under ADR-002 because, after folding, `#` and the following words
would be parsed as ordinary whitespace-delimited components rather than comment
syntax.

### Field grammar remains unchanged

After physical-line folding, the logical record SHALL continue to use the ADR-002
rules:

- fields are separated by one or more horizontal whitespace characters;
- each field token is split at the first `=` only;
- field order is irrelevant;
- `id`, `url`, `dest`, and `digest` are each required exactly once;
- duplicate, missing, and unknown fields fail closed;
- values cannot contain literal spaces or tabs;
- manifest content is never sourced, evaluated, or shell-expanded.

Indentation therefore affects record assembly only.  It does not create nested
objects, scopes, sections, or field ownership beyond continuation of the preceding
logical record.

### Diagnostics and source locations

When reporting an invalid logical record, implementations SHOULD identify the
physical line on which that logical record began.

When reporting a continuation line that has no preceding logical record,
implementations SHOULD identify the physical continuation line itself.

This preserves useful diagnostics even though one parsed record may span several
physical lines.

## Examples

### Single-line form

```text
id=example@1 url=https://example.test/example dest=vendor/example digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

### Folded form

```text
id=example@1
  url=https://example.test/example
  dest=vendor/example
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

The two forms are semantically equivalent.

### Field order remains irrelevant

```text
url=https://example.test/example
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  id=example@1
  dest=vendor/example
```

is valid because the unindented `url=` line begins the logical record and the
remaining indented lines continue it.  ADR-002 still makes field order irrelevant.

### Multiple records separated by comments

```text
# First dependency
id=one@1
  url=https://example.test/one
  dest=vendor/one
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# Second dependency
id=two@1
  url=https://example.test/two
  dest=vendor/two
  digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
```

contains two logical records.

## Considered Alternatives

### Keep every dependency on one physical line

This preserves the smallest parser, but long URLs and SHA-256 values make records
difficult to scan.  The project accepts the small folding step because it improves
human review without changing the logical grammar.

### INI-style sections

An INI-like representation could be readable, for example:

```ini
[example@1]
url=https://example.test/example
dest=vendor/example
digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

This was rejected for version 1 because INI is not one rigorously universal
format.  bashdeps would need to define section identity, duplicate-section
behavior, duplicate-key behavior, whitespace normalization, comment forms,
quoting, escaping, empty values, continuation behavior, and potentially section
ordering.  The resulting parser and specification would be larger than the data
model requires.

### Treat indentation as a prefix to `dest` or another hierarchy

This was rejected because indentation should have one narrow syntactic meaning:
continuation of the preceding logical record.  It does not create nested data or
change any field value.

### Require `id=` to be the first physical line

This could make records visually uniform, but ADR-002 deliberately makes field
order irrelevant.  Folding should not introduce a new positional requirement.
Any valid field may begin a logical record in column 1.

### Make blank lines terminate records

This would make visual spacing semantically significant and would prevent comments
or blank lines from being inserted inside a folded record.  Blank lines remain
inert instead; the next content line's indentation determines whether it continues
or starts a record.

### Support inline comments while adding folding

Inline comments remain ambiguous in an unquoted whitespace-delimited field grammar
and are unrelated to the readability problem folding solves.  They remain outside
version 1.

## Consequences

Manifest authors may choose compact one-line records or readable folded records
without changing dependency semantics.

The parser gains a small physical-line assembly phase before existing field
parsing.

Indentation becomes significant only at the beginning of non-comment physical
lines.  Accidental indentation at the start of a new record fails closed rather
than being silently repaired.

Comments and blank lines can be inserted freely without terminating a record,
which keeps annotation and visual spacing separate from dependency semantics.

Existing one-line manifests remain valid without modification.

External tools that already reason about logical `KEY=VALUE` records can continue
to use the same field model, although tools reading raw physical lines may need to
implement the documented folding step.

## Implementation and Testing Follow-Up

Implementation work should preserve the current ADR-002 parser after introducing
a record-folding layer ahead of tokenization.

Regression coverage should include at least:

- an existing one-line record;
- a four-line folded record;
- tabs as continuation indentation;
- comments between continuation lines;
- blank lines between continuation lines;
- multiple folded records;
- a continuation before any record;
- field-order independence across physical lines;
- inline comments remaining invalid;
- URLs containing additional `=` characters after folding.

## Related Decisions

- Extends: ADR-002
- Related to: ADR-003
- Related to: ADR-007
- Related to: ADR-010
