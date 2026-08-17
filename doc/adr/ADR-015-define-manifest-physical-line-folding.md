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
sourced or evaluated.  It adds one explicit physical-line continuation marker
that is processed before ADR-002 field parsing begins.

The goal is to improve human readability without making indentation semantic and
without replacing the deliberately small manifest grammar with a hierarchical
configuration language.

## Context

ADR-002 defines each dependency as one logical line containing four named fields:

```text
id=VALUE url=VALUE dest=VALUE digest=VALUE
```

That representation is deterministic and easy to parse, but realistic URLs and
SHA-256 digests make individual physical lines long.  Long records are harder to
scan in reviews and make adjacent fields visually blend together.

The project first considered indentation-based folding, where an indented
physical line would continue the preceding logical record.  That approach was
readable, but it assigned semantic meaning to whitespace and allowed accidental
indentation to change record boundaries.

The project therefore chose an explicit trailing backslash continuation marker,
which is already familiar to Bash and Unix users:

```text
id=wesley-dean/mktext@0.0.7 \
  url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash \
  dest=vendor/mktext.bash \
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

This representation is semantically identical to:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

The project also considered moving to an INI-like structure, but doing so would
create a materially larger grammar and force decisions about sections, duplicate
keys, section identity, quoting, escaping, comments, continuation behavior, and
parser compatibility.  Explicit continuation provides the desired readability
while preserving the already-defined logical record grammar.

## Decision Drivers

- Improve manifest readability during ordinary review.
- Preserve the named-field grammar from ADR-002.
- Make continuation explicit rather than indentation-sensitive.
- Use a convention familiar to Bash and Unix developers.
- Keep manifest parsing deterministic and inspectable in Bash.
- Avoid introducing a general-purpose configuration parser.
- Keep indentation cosmetic.
- Fail closed when a requested continuation is incomplete or malformed.
- Preserve field-order independence.
- Preserve the rule that field values cannot contain literal horizontal whitespace.
- Keep future external tooling able to reason about stable `KEY=VALUE` fields.

## Decision

Version 1 manifests SHALL distinguish physical lines from logical records.

A logical record MAY occupy one physical line or multiple physical lines.

Physical-line folding SHALL occur before the logical record is tokenized into
fields.

### Continuation marker

A physical content line requests continuation only when it ends with a standalone
backslash continuation marker.

The continuation marker SHALL:

- be the final non-newline character on the physical line;
- be preceded by at least one horizontal whitespace character; and
- consist of one literal `\` character.

No spaces or tabs may follow the marker before the newline.

For example:

```text
id=example@1 \
  url=https://example.test/example \
  dest=vendor/example \
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

is a four-physical-line representation of one logical record.

A backslash that is part of field data and is not a standalone trailing marker
has no continuation meaning.

The continuation marker is a bashdeps manifest lexical convention only.  It does
not enable Bash escaping, quoting, command parsing, parameter expansion, or any
other shell evaluation behavior.

### Folding behavior

When a physical line ends with the continuation marker, bashdeps SHALL:

1. remove the horizontal whitespace immediately separating the marker from the
   preceding content as needed to remove the marker cleanly;
2. remove the marker itself;
3. require another physical content line immediately after it;
4. remove leading horizontal whitespace from that next content line for folding
   purposes; and
5. append the next line's content to the accumulated logical record using exactly
   one ASCII space between the two physical-line fragments.

If the next physical line also ends with a continuation marker, folding SHALL
continue recursively until a physical content line without a continuation marker
completes the logical record.

Conceptually:

```text
foo \
  bar \
  bazzle
```

folds to:

```text
foo bar bazzle
```

After folding, the resulting logical record SHALL be parsed exactly as ADR-002
specifies.

### Indentation is not semantic

Leading spaces or tabs on a physical content line SHALL NOT by themselves imply
continuation.

Continuation exists only because the immediately preceding physical content line
ended with the explicit continuation marker.

For example:

```text
id=one@1
  id=two@1
```

contains two physical records, not one folded record.  Each record is then
validated independently and will ordinarily fail because each declaration is
incomplete.

This fail-closed behavior is intentional.  Accidental indentation cannot silently
change the logical dependency being declared.

Indentation on the physical line following a continuation marker is cosmetic and
is removed before joining the fragments.  Authors may therefore align continued
fields for readability without changing manifest meaning.

### Blank lines and comments

Outside an active continuation, ADR-002's existing rules remain unchanged:

- blank lines are ignored;
- lines whose first non-horizontal-whitespace character is `#` are ignored; and
- inline comments are unsupported.

Inside an active continuation, the next physical line SHALL contain record
content.  A blank line or full-line comment immediately after a trailing
continuation marker SHALL make the manifest invalid.

For example, this is invalid:

```text
id=example@1 \
  # explanation inserted inside a continuation
  url=https://example.test/example
```

and this is also invalid:

```text
id=example@1 \

  url=https://example.test/example
```

The strict rule keeps continuation local and obvious: a trailing `\` means the
very next physical line continues the same logical record.

Comments that explain a dependency SHOULD therefore appear before the record:

```text
# Rendering dependency used by the documentation build.
id=example@1 \
  url=https://example.test/example \
  dest=vendor/example \
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

### End-of-file handling

A manifest SHALL be invalid when the final physical line ends with a continuation
marker and no following physical content line exists.

Bashdeps SHALL fail rather than silently treating an unterminated continuation as
a complete logical record.

### Field semantics after folding

Folding SHALL NOT introduce spaces into field values.

The inserted ASCII space separates field tokens in the same way that horizontal
whitespace separates them in an ordinary one-line record.

For example:

```text
url=https://example.test/download?first=1&second=2 \
  id=example@1 \
  digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  dest=vendor/example
```

folds to a valid logical record.  The additional `=` characters inside the URL
remain literal field data because ADR-002 still splits each field token only at
its first `=`.

Field order remains irrelevant.

### Relationship to `bashdeps.bash install`

Physical-line continuation is a manifest-file feature.

It does not change the argv contract of `bashdeps.bash install`.  When a user
writes a shell command across lines using Bash's own `\`-newline behavior, the
interactive or calling shell processes that syntax before bashdeps receives its
arguments.  bashdeps does not apply manifest folding to CLI arguments.

This distinction prevents the manifest format from becoming an alternate shell
parser.

## Parsing Model

Conceptually, manifest processing now has three stages:

1. classify blank/comment lines and fold explicit physical-line continuations;
2. split each completed logical record on horizontal whitespace into field tokens;
3. split each token at its first `=` and apply ADR-002 validation.

An implementation may perform these operations in one streaming pass.  The stages
above define semantics, not a requirement to allocate a transformed intermediate
manifest.

At no stage may manifest content be sourced, evaluated, or shell-expanded.

## Considered Alternatives

### Indentation-based continuation

The project initially documented a rule where any indented content line continued
the preceding record.  That representation was compact and readable, but it made
indentation semantically significant and allowed accidental whitespace changes to
alter record boundaries.

Explicit trailing `\` continuation was chosen because it requires the author to
state continuation intent directly while leaving indentation cosmetic.

### INI-style sections

An INI-like format could represent a dependency as a section with one key per
line.  INI, however, is a family of related conventions rather than one precise
portable grammar.  bashdeps would need to define section identity, duplicate
sections, duplicate keys, whitespace trimming, comments, quoting, escaping,
continuation, and empty-value behavior.

That complexity does not improve the trust model.  Explicit folding provides the
needed readability while retaining the smaller existing grammar.

### Backslash as general escape syntax

Treating `\` as a general escape character would introduce another grammar layer
and invite Bash-like expectations around quoting and escaping.  Version 1 assigns
backslash exactly one special role: a standalone trailing continuation marker.
Every other backslash is ordinary data subject to the field-specific grammar.

### Silently skip comments or blank lines during continuation

Skipping semantically empty lines while a continuation is open could make long
records more permissive, but it weakens the direct relationship between a trailing
marker and the physical line it promises to continue onto.  Version 1 therefore
requires actual record content immediately after every continuation marker.

### Keep one physical line per dependency

This remains valid and is the smallest representation, but it makes realistic
records unnecessarily difficult to scan.  The chosen rule preserves one-line
compatibility while adding an explicit readable form.

## Consequences

Existing one-line manifests remain valid and unchanged.

Authors may format long declarations across several physical lines without
changing the logical field grammar.

Indentation becomes presentation only and cannot accidentally join records.

The parser gains one small state machine: it must track whether the preceding
physical line explicitly requested continuation.

Malformed or unterminated continuations fail closed as manifest errors.

External tooling may either implement the same small folding rule or continue to
operate on one-line records where that is more convenient.

The format remains intentionally narrower than shell syntax, INI, YAML, JSON, or a
general configuration language.

## Testing Requirements

Implementation of this ADR SHALL add deterministic behavior tests covering at
least:

- a conventional one-line record;
- a valid record folded across all four fields;
- two and three successive continuation markers;
- spaces used for visual indentation;
- tabs used for visual indentation;
- no indentation on a continued physical line;
- field-order independence across continued lines;
- a URL containing additional `=` characters across a folded record;
- multiple folded records in one manifest;
- blank lines and comments outside active continuations;
- a blank line immediately after a continuation marker;
- a full-line comment immediately after a continuation marker;
- an unterminated continuation at end of file;
- a backslash not used as a standalone trailing marker;
- trailing whitespace after a backslash marker being rejected;
- continued rejection of inline comments; and
- equivalent observable behavior across maintained source and both generated Bash
  artifacts.

## Related Decisions

- Refines physical representation defined by: ADR-002
- Related to: ADR-010
- Related to: ADR-013
- Related to: ADR-014
