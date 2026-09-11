# Manifest Manager Behavior Specification

## Purpose

`manifest-manager.bash` is the maintainer-side companion to `bashdeps.bash`.  It
prepares deliberate source changes to bashdeps manifests and provides validated
read-only inspection without moving release discovery or trust changes into the
runtime synchronizer.

It does not synchronize dependency destinations and is not involved in runtime
byte acceptance.  The committed manifest remains trusted source; a manager
mutation is a proposal that becomes authorized only through the consuming
repository's normal review and commit process.

The currently implemented commands are `update`, `list`, `add`, and `remove`.
ADR-021 defines the relationships and preservation contracts among these
operations.  ADR-023 adds the optional `digest_url` manifest field and defines how
the manager preserves and verifies it without inferring checksum locations.

## Runtime Requirements

The manager requires Bash 4.3 or newer and ordinary Unix-like filesystem tools
used for private staging and publication.

Capabilities are command-specific:

- `list`, `add`, and `remove` require no network client or SHA-256 command;
- `update` requires curl and `sha256sum` or `shasum -a 256` when update work
  requires release discovery, artifact retrieval, checksum-resource retrieval, or
  hashing.

The executable does not require `gh`, `jq`, Git, Python, or `bashdeps.bash`.

These requirements apply to `manifest-manager.bash` only.  They do not change the
runtime capabilities required by `bashdeps.bash`.

## Public CLI

The currently implemented public forms are:

```text
manifest-manager.bash update [OPTIONS] ID [VERSION]
manifest-manager.bash update [OPTIONS] ID@VERSION
manifest-manager.bash update [OPTIONS] --all
manifest-manager.bash add [OPTIONS] id=VALUE url=VALUE dest=VALUE digest=sha256:HEX [digest_url=HTTPS_URL]
manifest-manager.bash remove [OPTIONS] ID
manifest-manager.bash list [OPTIONS]
manifest-manager.bash help
manifest-manager.bash version
```

Update options are:

```text
-a, --all
-f, --filename FILE
-h, --help
-V, --version
```

Add, remove, and list options are:

```text
-f, --filename FILE
-h, --help
-V, --version
```

The default manifest is:

```text
dependencies.txt
```

`-f FILE` selects another manifest.  `-f -` is meaningful for all implemented
manifest commands, but its STDOUT contract depends on the command: `update`,
`add`, and `remove` are transactional source transforms, while `list` is
read-only data output.

`update --all` cannot be combined with a positional ID or VERSION.  `list` accepts
no positional arguments.  `add` requires exactly one each of the four required
manifest fields, may accept one explicit `digest_url`, and accepts no other
positional form.  `remove` accepts exactly one complete identity value.

The executable is non-interactive.

## Help and Version

These top-level help forms are equivalent:

```text
manifest-manager.bash help
manifest-manager.bash -h
manifest-manager.bash --help
```

Top-level help summarizes implemented subcommands and shared informational forms.
It does not advertise commands whose contracts are not implemented.

These command-specific help forms write to STDOUT and return status 0:

```text
manifest-manager.bash update -h
manifest-manager.bash update --help
manifest-manager.bash add -h
manifest-manager.bash add --help
manifest-manager.bash remove -h
manifest-manager.bash remove --help
manifest-manager.bash list -h
manifest-manager.bash list --help
```

Subcommand help documents command syntax, options, file/stream behavior, output,
and relevant exit categories.  Informational help does not consume STDIN even
when `-f -` is also present.

These version forms are equivalent:

```text
manifest-manager.bash version
manifest-manager.bash -V
manifest-manager.bash --version
```

`update`, `add`, `remove`, and `list` also accept `-V` and `--version` as
informational forms.  Generated artifacts report the shared bashdeps project
release version, source revision date, and source commit while identifying the
executable as `manifest-manager.bash`.

## Manifest Grammar

The manager accepts the bashdeps version-1 manifest grammar defined by ADR-002,
ADR-015, and ADR-023.

Each logical dependency record requires exactly one each of:

```text
id=VALUE
url=VALUE
dest=VALUE
digest=sha256:<64-lowercase-hex>
```

A record may additionally contain exactly one:

```text
digest_url=HTTPS_URL
```

Existing four-field records remain valid.  The optional field is stored in the
manager's logical view only when explicitly declared; the manager never derives a
checksum location merely because an artifact URL is present.

Field order is irrelevant.  Blank lines and full-line comments are allowed outside
an active continuation.  Explicit standalone trailing `\` continuation markers
fold physical lines exactly as bashdeps defines them.

Both `url` and an explicitly present `digest_url` must use HTTPS.  The committed
`digest` remains mandatory and canonical as `sha256:` followed by 64 lowercase
hexadecimal characters.

The manager validates a selected manifest before command-specific work that relies
on its records.  It never sources, evals, or shell-expands manifest content.

Parsing creates a logical validation view and retains the exact raw physical bytes
for every record.  It also retains an ordered source-chunk view in which comments,
blank lines, and complete logical records remain independent.  The logical view is
never serialized back into source merely to inspect or mutate a manifest.

## `list`

`list` is a read-only manifest inspection command:

```text
manifest-manager.bash list [OPTIONS]
```

On success, it writes each complete validated `id` value to STDOUT, one identity
per line, in manifest order.

For example, a manifest containing identities:

```text
id=acme/tool@v1
id=other.example/helper@release-7
```

produces:

```text
acme/tool@v1
other.example/helper@release-7
```

The values are complete logical `id` fields.  `list` does not strip versions,
reduce identities to GitHub package coordinates, or otherwise reinterpret the
identity.  This keeps the command consistent with the runtime rule that `id` is
opaque metadata.

The complete selected manifest, including optional `digest_url` syntax when
present, is parsed and validated before the first identity is emitted.  A malformed
later record therefore cannot produce a successful or partial prefix of list
output.

A valid empty manifest succeeds and writes nothing.

`list` never reserializes the manifest, never mutates the source path, and never
retrieves a declared `digest_url`.

### List file mode

With a normal filename, the file is captured into private staging and fully
validated before output begins.  The selected file remains unchanged.

### List stream mode

With:

```text
manifest-manager.bash list -f -
```

the complete manifest is read from STDIN and validated before identities are
written to STDOUT.

Unlike a mutating command, `list` does not use rollback-manifest output.  On
failure, STDOUT contains no list data intentionally; diagnostics go to STDERR and
the command returns nonzero.  STDOUT belongs to the identity list, not a
transformed source representation.

`list` requires no release discovery, network access, artifact retrieval, checksum
retrieval, or SHA-256 implementation.

## `add`

`add` appends one deliberately supplied dependency declaration:

```text
manifest-manager.bash add [OPTIONS] \
  id=VALUE url=VALUE dest=VALUE digest=sha256:HEX [digest_url=HTTPS_URL]
```

Exactly one each of `id=`, `url=`, `dest=`, and `digest=` is mandatory.  One
`digest_url=` may additionally be supplied.  The field arguments may appear in any
order.  Each field token is split only at its first `=`, so additional equals signs
remain part of the field value.

Unknown, duplicate, missing, empty, whitespace-bearing, or otherwise invalid
fields fail with status 2.  The declaration must satisfy the same version-1
manifest validation rules as a committed record, including HTTPS artifact URL,
HTTPS `digest_url` when present, canonical project-relative destination text, and
a lowercase 64-hex `sha256:` committed digest.

`add` does not infer or invent:

- artifact URLs;
- checksum URLs or sidecar names;
- artifact filenames;
- destination paths;
- repositories or hosting providers;
- package conventions; or
- digest values.

Supplying an identity such as `OWNER/REPO@VERSION` does not cause any other field
to be derived.  Supplying `url=` does not cause `.sha256`, `.256`, release metadata,
or another checksum location to be guessed.  `add` performs no release discovery,
network access, artifact retrieval, checksum retrieval, or digest calculation.

The existing complete manifest is validated before append construction.  The new
logical declaration is then validated against the parsed existing state, so an
identity or destination that duplicates an existing record fails before
publication.

### Add canonical record form

Only the newly appended bytes are canonicalized.  Without `digest_url`, the new
record retains the historical one-line form and field order:

```text
id=... url=... dest=... digest=...
```

When `digest_url` is explicitly supplied, it is appended after the four required
fields:

```text
id=... url=... dest=... digest=... digest_url=...
```

No existing record is reformatted, folded, unfolded, reordered, or otherwise
serialized from parsed state.

### Add append and newline semantics

The new record is appended at absolute EOF.  Existing trailing comments, blank
lines, whitespace, records, and other valid source bytes therefore remain exactly
where they were and become an exact prefix of the candidate.

The append line ending is chosen deterministically from the captured original:

1. each observed physical LF or CRLF terminator updates the current convention;
2. the last observed terminator style is reused for the append; and
3. LF is used when the manifest contains no observable line terminator, including
   an empty file or a one-line file without a final terminator.

If a non-empty original does not end with a line terminator, exactly one selected
line terminator is inserted as a separator before the new record.  If the original
already ends with a line terminator, no additional separator is inserted.  The new
record itself always ends with the selected line terminator.

The implementation proves the successful candidate equals:

```text
captured original bytes + deliberately constructed append bytes
```

before publication.  It then reparses the complete candidate.  A candidate that
cannot satisfy this append-only proof or unexpectedly becomes invalid is a status
5 safety failure.

### Add file mode

With a normal filename, successful `add` is quiet on STDOUT.  The selected
manifest must already exist as a readable regular non-symlink file; `add` does not
implicitly create a missing manifest path.  An intentionally empty existing file
is valid and receives one LF-terminated canonical record.

The complete original is captured before mutation.  Publication uses the same
staged same-directory replacement discipline as `update`: a detected concurrent
content change or newly introduced symlink causes failure rather than overwrite,
and existing file metadata is preserved when ordinary filesystem tools permit it.

### Add stream mode

`add -f -` uses the same mutating stream transaction contract as `update`.
Recognizable stream syntax causes the complete input to be captured before full
CLI validation so an invalid declaration can still reproduce the original input.

After complete input capture:

```text
success -> STDOUT is the complete appended manifest, status 0
failure -> STDOUT is the complete original manifest, nonzero status
```

Diagnostics go to STDERR.  Callers must inspect the exit status rather than
assuming the presence of manifest output means the append succeeded.

Help and version remain informational output and do not consume STDIN.

## `remove`

`remove` deletes one dependency selected by its complete logical identity:

```text
manifest-manager.bash remove [OPTIONS] ID
```

`ID` is the complete value of the dependency's `id=` field.  Matching is exact
and provider-neutral.  `remove` does not strip a version component, interpret a
GitHub `OWNER/REPO` package prefix, parse semantic versions, or otherwise transform
the supplied identity before comparison.

The complete existing manifest is parsed and validated before selection.  Zero
exact matches fail with status 2.  Duplicate identities are already invalid under
the version-1 manifest grammar, so a manifest containing multiple records with the
same ID also fails before mutation.

A record containing `digest_url` is removed in exactly the same way as a four-field
record.  The field disappears only because the complete selected physical record
is removed; no checksum resource is retrieved.

### Remove physical-record semantics

A successful removal deletes exactly the selected logical record's complete
physical source chunk.  For a one-line record, that means the one physical record
line and its line terminator when one exists.  For an ADR-015 continued record,
the removal includes every physical continuation line that belongs to that same
logical record and the final physical line's terminator when present.

Comments and blank lines remain independent source chunks.  A comment immediately
before or after the selected record is preserved exactly, as are adjacent blank
lines.  `remove` does not infer whether prose or spacing belongs to a dependency.
A human may later choose to tidy such source in a separate edit.

Every surviving source byte remains unchanged and in its original order.  No
separator, line ending, indentation, or final newline is inserted or normalized to
make the result look tidier.

### Remove preservation proof

Candidate generation uses the parser's ordered exact source chunks and omits only
the one record chunk associated with the selected logical record.

Before publication, the implementation independently reconstructs the captured
original from the complete chunk sequence and requires byte-for-byte equality.  It
also reconstructs the expected candidate from the same sequence while omitting
exactly one selected record chunk, verifies that the omitted chunk equals the
retained raw bytes for the selected record, and requires the staged candidate to
match that expected candidate byte-for-byte.

The complete candidate is then reparsed.  A failure of the exact-one-record
omission proof or an unexpectedly invalid candidate is a status 5 safety failure.

### Remove file mode

With a normal filename, successful `remove` is quiet on STDOUT.  The manifest must
already exist as a readable regular non-symlink file.  Removing the only dependency
may intentionally leave an empty valid manifest or leave only comments and blank
lines that were already present.

Publication uses the shared staged same-directory replacement discipline.  A
concurrent content change or newly introduced symlink causes failure rather than
overwrite.

### Remove stream mode

`remove -f -` uses the mutating stream transaction contract shared by `update` and
`add`.  Recognizable stream syntax captures the complete input before full CLI
validation so selection and CLI failures can reproduce the original input.

After complete input capture:

```text
success -> STDOUT is the complete manifest with one record removed, status 0
failure -> STDOUT is the complete original manifest, nonzero status
```

Diagnostics go to STDERR.  Callers must inspect the exit status.  Help and version
remain informational output and do not consume STDIN.

`remove` requires no provider interpretation, release discovery, network access,
artifact retrieval, checksum retrieval, or SHA-256 implementation.

## Update Dependency Selection

A single-dependency update accepts a GitHub package name in this form:

```text
OWNER/REPO
```

It matches the package portion of an existing manifest identity that follows the
maintenance convention:

```text
OWNER/REPO@VERSION
```

For example:

```text
wesley-dean/bash-doxygen
```

matches:

```text
wesley-dean/bash-doxygen@0.0.6
```

The selected package must appear exactly once.  Zero matches or multiple records
with the same package prefix fail.

`update` does not add a missing dependency and does not add `digest_url` to a
record that does not already declare it.

## Update Version Selection

### Explicit VERSION

With:

```text
manifest-manager.bash update OWNER/REPO TAG
```

or:

```text
manifest-manager.bash update OWNER/REPO@TAG
```

`TAG` is used exactly as supplied.  The manager does not:

- add or remove a leading `v`;
- parse semantic-version ranges;
- select a compatible version;
- enumerate or sort tags; or
- require the tag to have a GitHub Release object.

The derived artifact URL, and derived checksum URL when an existing `digest_url`
is present, must still retrieve successfully.

A target tag cannot contain whitespace or `@`, because the resulting
`OWNER/REPO@TAG` identity would not be unambiguous for this maintenance interface.

The literal tag `latest` has no special meaning when supplied explicitly.

### Omitted VERSION

With:

```text
manifest-manager.bash update OWNER/REPO
```

or for each dependency under `update --all`, the manager uses GitHub's canonical
latest release.

It requests:

```text
https://github.com/OWNER/REPO/releases/latest
```

with curl and follows HTTPS redirects.  The final effective URL must be exactly in
the corresponding release-tag namespace:

```text
https://github.com/OWNER/REPO/releases/tag/ENCODED_TAG
```

The final path component is percent-decoded to obtain the exact release tag.
Percent decoding is path decoding: `+` remains `+` rather than becoming a space.
Malformed percent escapes and encoded NUL fail.

The manager does not call the GitHub REST API or parse JSON to perform this lookup.

## Existing Identity and URL Relationship

The update implementation recognizes these immutable GitHub URL families:

```text
https://raw.githubusercontent.com/OWNER/REPO/REF/ARTIFACT_PATH
https://github.com/OWNER/REPO/releases/download/TAG/ASSET_PATH
```

The package in the URL must match the package selected from the `id` field.

The existing URL REF/TAG must correspond to the current identity VERSION.  These
forms correspond:

```text
VERSION == REF
VERSION == TAG
```

For compatibility with existing manifests, exactly one leading `v` difference is
also accepted:

```text
id=OWNER/REPO@0.0.6
url=https://raw.githubusercontent.com/OWNER/REPO/v0.0.6/path
```

This compatibility check does not modify the target tag.  If the requested target
is `v0.0.14`, the new identity is exactly `OWNER/REPO@v0.0.14` and the new URL ref
is exactly `v0.0.14`.

A 40- or 64-character hexadecimal identity version is treated as a commit pin and
is not release-updateable.

A raw-content URL cannot be updated to a tag containing `/` because the ref/path
boundary would be ambiguous.  Unsupported URL forms fail rather than trigger URL
or artifact inference.

When a record already contains `digest_url`, that URL must independently satisfy
the same supported URL-family, package, and current-version relationship.  The
manager changes only its recognized REF/TAG component to the exact target tag.  It
does not infer a checksum filename, append `.sha256`, fall back to `.256`, or
construct a new checksum URL from the artifact URL.

A record whose artifact URL is updateable but whose declared `digest_url` cannot be
transformed safely fails before update network work rather than silently dropping
or ignoring the checksum contract.

## Candidate Artifact and Digest

For one selected update record without `digest_url`, the manager retains its
historical behavior:

1. replaces only the recognized current artifact URL ref/tag with the exact target
   tag to construct a candidate artifact URL;
2. downloads that artifact into private staging;
3. calculates SHA-256 over the exact downloaded bytes; and
4. prepares a `sha256:` digest value from that result.

For one selected record that already declares `digest_url`, the manager additionally:

1. replaces only that checksum URL's recognized current ref/tag with the exact
   target tag;
2. downloads the checksum resource into private staging;
3. parses exactly one accepted SHA-256 value from the resource; and
4. requires the downloaded artifact SHA-256 to equal that upstream value before
   proposing the new committed digest.

The checksum grammar is the same narrow ADR-023 grammar used by bashdeps runtime:
a bare 64-hex token defaults to SHA-256, `sha256:` may be explicit, conventional
filename text may follow, hexadecimal comparison is case-insensitive, and
multiple non-blank entries, malformed input, or another explicit algorithm fail
closed.  Filename text is opaque and is not used as trust input.

Downloaded artifacts and checksum resources are never executed.  The upstream
checksum is corroborating live data only; review and commit of the proposed
`digest=` remain the authorization boundary.

If the target artifact URL is identical to the existing immutable URL but the
downloaded bytes do not match the currently committed digest, the update fails.
This avoids silently authorizing changed bytes at a location the manifest already
described as immutable.  When `digest_url` is present, a same-target operation also
retrieves and verifies that checksum resource before reporting a successful no-op.

## Surgical Update Mutation Contract

For a selected dependency without `digest_url`, `update` may change only these
field values:

```text
id
url
digest
```

For a selected dependency that already declares `digest_url`, `update` may also
change that field's value:

```text
digest_url
```

`dest` is never changed, and `update` never inserts a previously absent
`digest_url`.

The old complete value for each field that needs to change must occur exactly once
inside the selected raw record.  An absent value or a value appearing multiple
times is a preservation failure.

Checksum URL replacement is planned before artifact URL replacement because a
conventional checksum URL may contain the complete artifact URL as a literal
prefix, such as `tool` and `tool.sha256`.  This ordering preserves the exact-once
proof for the shorter artifact URL without weakening the substitution rule.

The updated raw record then replaces the original raw record exactly once in the
complete captured manifest.

The implementation retains every changed old/new raw-record pair.  Before output
or publication, it reverses the candidate substitutions in reverse order and
requires the result to equal the original manifest byte-for-byte.  It then parses
the complete candidate again.

A successful update therefore preserves all unrelated bytes, including:

- spaces and tabs;
- indentation;
- field ordering;
- physical line breaks;
- continuation placement;
- blank lines;
- comments;
- trailing whitespace;
- CRLF versus LF endings;
- final-newline presence or absence; and
- unrelated records.

Input containing bytes that cannot make a lossless round trip through the Bash
string representation, including NUL, is rejected rather than changed.

ADR-021 retains operation-specific proofs for mutation commands.  It does not
authorize parse-and-reserialize rewriting.

## Update File Mode

With a normal manifest filename, successful update operation is quiet on STDOUT.

The manager captures the complete original file before any network update work.
No failed update intentionally modifies the manifest path.

Immediately before publication, the current file bytes are compared with the
captured original.  A detected concurrent content change causes failure rather
than overwrite.

When a changed candidate is ready, it is written through a same-directory
temporary file and renamed into place.  The implementation attempts to preserve
existing file metadata with ordinary filesystem tools.

A successful no-op leaves the original path untouched.

The manager does not provide locking or claim race-proof behavior against a
hostile concurrent local process.

## Update Stream Mode

`update -f -` reads the complete manifest from STDIN before release discovery,
artifact retrieval, checksum retrieval, hashing, or mutation.

After complete input capture:

### Success

```text
STDOUT = complete updated manifest
status = 0
```

A successful no-op emits the original input byte-for-byte.

### Failure

```text
STDOUT = complete original input manifest, byte-for-byte
STDERR = diagnostic
status != 0
```

This rollback output rule applies to both operational failures and update CLI
errors when stream mode can be recognized and the complete input can be captured.
Callers must inspect the exit status; output presence alone does not mean the
update succeeded.

If STDIN fails before complete capture, bytes never received cannot be reproduced.
If writing STDOUT fails, the manager cannot guarantee that the downstream consumer
received a complete representation.

Help and version output remain informational success output and do not consume
STDIN.

## `update --all`

`manifest-manager.bash update --all` selects every dependency in the manifest.

Before network access, it verifies that every record:

- uses an unambiguous GitHub `OWNER/REPO@VERSION` maintenance identity;
- maps to a unique package;
- is not commit-pinned;
- has an updateable artifact URL; and
- when `digest_url` is present, has an independently updateable checksum URL under
  the same package/current-version relationship.

For every selected dependency, the target is its GitHub latest release as defined
above.

All release discovery, artifact retrieval, hashing, declared checksum retrieval and
verification, surgical mutation, and final preservation checks complete before one
output/publication step.  A failure in any record fails the entire transaction.

Unsupported records are not silently skipped.

A valid empty manifest is a successful no-op for `update --all` and does not
require network/hash capabilities.

## Output Channels

Top-level and command-specific help and version information write to STDOUT.

Successful `update`, `add`, and `remove` file mode writes nothing to STDOUT.  Their
stream modes reserve STDOUT for exactly one complete manifest representation after
input capture.

`list` reserves STDOUT for complete identities, one per line.  Because complete
validation precedes emission, invalid manifests do not intentionally produce a
partial list.

Diagnostics write to STDERR.

No JSON output is defined.

## Exit Statuses

The public exit categories are:

```text
0  success, help, version, or successful no-op
2  invalid CLI, manifest, dependency selection, declaration, or unsupported update relationship
3  required runtime capability unavailable or unusable
4  latest-release discovery or network acquisition failed
5  integrity, exact-mutation, or preservation safety check failed
6  input, staging, filesystem, output, or publication failed
```

For `update`, status 4 includes failure to retrieve a declared checksum resource.
Status 5 includes a malformed, empty, multi-entry, or unsupported-algorithm
checksum resource and a checksum value that disagrees with the downloaded artifact.

Commands use only categories relevant to their behavior.  `list` normally uses 0,
2, and 6.  `add` and `remove` normally use 0, 2, 5, and 6.  These commands validate
`digest_url` syntax when encountered but do not retrieve it and therefore do not
report network or hashing failures for that field.

The implementation may use private helper statuses internally, but the public CLI
must remain within these categories.

## Product and Release Boundary

`manifest-manager.bash` and `bashdeps.bash` are independent executable products
built from explicit source inventories.

Manager-only code must not be incorporated into `bashdeps.bash`, and bashdeps-only
code must not be incorporated into the manager unless a later change deliberately
moves genuinely shared behavior into both source closures.

Both products share one project release version and each ships developer,
comment-stripped, and minified executables with matching `.sha256` companions.
The `digest_url` feature does not change the twelve-file release asset contract.

The manager behavior suite is run independently against maintained source and all
three manager distribution artifacts.

## ADR-021 Command Set

ADR-021 defines the conservative contracts for `list`, `add`, and `remove`, with
ADR-023 refining only their understanding of the optional manifest field.  The
commands share validated parsing and lifecycle infrastructure while retaining
operation-specific output and preservation proofs:

- `list` validates completely before emitting opaque identity values;
- `add` preserves the original source as an exact prefix followed only by its
  deliberately constructed canonical append; and
- `remove` preserves the ordered source chunk sequence with exactly one selected
  record omitted.

None of these contracts authorizes parse-and-reserialize source rewriting.

## Non-Goals

The current manager does not provide:

- `show` behavior;
- semantic-version ranges or constraint solving;
- transitive dependency resolution;
- package registries;
- arbitrary hosting-provider discovery;
- artifact-name inference;
- checksum-URL or checksum-filename inference;
- aggregate checksum-file entry selection;
- destination inference;
- automatic digest calculation for `add`;
- automatic comment cleanup for `remove`;
- JSON output;
- a public sourceable Bash API;
- authenticated/private GitHub retrieval; or
- silent skipping of unsupported dependencies under `update --all`.

`show` remains outside the accepted command set unless a concrete need produces a
separate decision.
