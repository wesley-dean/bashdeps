# Manifest Manager Behavior Specification

## Purpose

`manifest-manager.bash` is the maintainer-side companion to `bashdeps.bash`.  It
prepares deliberate source changes to existing bashdeps manifests by coordinating
an updated dependency identity, immutable GitHub artifact URL, and SHA-256 digest.

It does not synchronize dependency destinations and is not involved in runtime
byte acceptance.  The committed manifest remains trusted source; a manager update
is a proposal that becomes authorized only through the consuming repository's
normal review and commit process.

The initial public mutation command is `update`.

## Runtime Requirements

The manager requires:

- Bash 4.3 or newer;
- curl;
- `sha256sum` or `shasum -a 256`; and
- ordinary Unix-like filesystem tools used for private staging and publication.

It does not require `gh`, `jq`, Git, Python, or `bashdeps.bash`.

These requirements apply to `manifest-manager.bash` only.  They do not change the
runtime capabilities required by `bashdeps.bash`.

## Public CLI

The public forms are:

```text
manifest-manager.bash update [OPTIONS] ID [VERSION]
manifest-manager.bash update [OPTIONS] ID@VERSION
manifest-manager.bash update [OPTIONS] --all
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

The default manifest is:

```text
dependencies.txt
```

`-f FILE` selects another manifest.  `-f -` selects transactional stdin/stdout
stream mode.

`--all` cannot be combined with a positional ID or VERSION.

The executable is non-interactive.

## Help and Version

These top-level help forms are equivalent:

```text
manifest-manager.bash help
manifest-manager.bash -h
manifest-manager.bash --help
```

`manifest-manager.bash update -h` and `update --help` also produce help.

Help writes to STDOUT and returns status 0.  It describes command syntax, version
selection, stream-mode rollback behavior, and exit categories.

These version forms are equivalent:

```text
manifest-manager.bash version
manifest-manager.bash -V
manifest-manager.bash --version
```

Generated artifacts report the shared bashdeps project release version, source
revision date, and source commit while identifying the executable as
`manifest-manager.bash`.

## Manifest Grammar

The manager accepts the bashdeps version-1 manifest grammar defined by ADR-002 and
ADR-015.

Each logical dependency record requires exactly one each of:

```text
id=VALUE
url=VALUE
dest=VALUE
digest=sha256:<64-lowercase-hex>
```

Field order is irrelevant.  Blank lines and full-line comments are allowed outside
an active continuation.  Explicit standalone trailing `\` continuation markers
fold physical lines exactly as bashdeps defines them.

The manager validates the manifest before update work.  It never sources, evals,
or shell-expands manifest content.

Parsing creates a logical validation view and retains the exact raw physical bytes
for every record.  The logical view is never serialized back into the output.

## Dependency Selection

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

`update` does not add a missing dependency.

## Version Selection

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

The derived artifact URL must still retrieve successfully.

A target tag cannot contain whitespace or `@`, because the resulting
`OWNER/REPO@TAG` identity would not be unambiguous for this maintenance interface.

The literal tag `latest` has no special meaning when supplied explicitly.

### Omitted VERSION

With:

```text
manifest-manager.bash update OWNER/REPO
```

or for each dependency under `--all`, the manager uses GitHub's canonical latest
release.

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

The initial manager recognizes these immutable GitHub URL families:

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

## Candidate Artifact and Digest

For one selected record, the manager:

1. replaces only the recognized current URL ref/tag with the exact target tag to
   construct a candidate artifact URL;
2. downloads that artifact into private staging;
3. calculates SHA-256 over the exact downloaded bytes; and
4. prepares a `sha256:` digest value from that result.

Downloaded artifacts are never executed.

If the target URL is identical to the existing immutable URL but the downloaded
bytes do not match the currently committed digest, the update fails.  This avoids
silently authorizing changed bytes at a location the manifest already described
as immutable.

## Surgical Mutation Contract

For each selected dependency, `update` may change only these field values:

```text
id
url
digest
```

`dest` is never changed.

The old complete value for each field that needs to change must occur exactly once
inside the selected raw record.  An absent value or a value appearing multiple
times is a preservation failure.

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

## File Mode

With a normal manifest filename, successful operation is quiet on STDOUT.

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

## Stream Mode

`-f -` reads the complete manifest from STDIN before release discovery, artifact
retrieval, hashing, or mutation.

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

Help and version output remain informational success output and do not need to
consume STDIN.

## `--all`

`manifest-manager.bash update --all` selects every dependency in the manifest.

Before network access, it verifies that every record:

- uses an unambiguous GitHub `OWNER/REPO@VERSION` maintenance identity;
- maps to a unique package; and
- is not commit-pinned.

For every selected dependency, the target is its GitHub latest release as defined
above.

All release discovery, artifact retrieval, hashing, surgical mutation, and final
preservation checks complete before one output/publication step.  A failure in any
record fails the entire transaction.

Unsupported records are not silently skipped.

A valid empty manifest is a successful no-op for `--all` and does not require
network/hash capabilities.

## Output Channels

Normal successful file-mode updates write nothing to STDOUT.

Help and version write to STDOUT.

Stream mode reserves STDOUT for exactly one complete manifest representation after
input capture.

Diagnostics write to STDERR.

No JSON output is defined.

## Exit Statuses

The public exit categories are:

```text
0  success, help, version, or successful no-op
2  invalid CLI, manifest, dependency selection, or update declaration
3  required runtime capability unavailable or unusable
4  latest-release discovery or network acquisition failed
5  exact-substitution or preservation safety check failed
6  input, staging, filesystem, or publication failed
```

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

The manager behavior suite is run independently against maintained source and all
three manager distribution artifacts.

## Non-Goals

The initial manager does not provide:

- `add`, `remove`, `list`, or `show` behavior;
- semantic-version ranges or constraint solving;
- transitive dependency resolution;
- package registries;
- arbitrary hosting-provider discovery;
- artifact-name inference;
- destination inference;
- JSON output;
- a public sourceable Bash API;
- authenticated/private GitHub retrieval; or
- silent skipping of unsupported dependencies under `--all`.

Possible `add`, `remove`, and `list` commands are tracked separately by issue #17.
