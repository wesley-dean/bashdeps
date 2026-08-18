# bashdeps Behavior Specification

## Purpose

`bashdeps` materializes exact, SHA-256-pinned external artifacts at declared
project-relative destinations subject to an invocation-level destination-root
policy.  The distributed executable is named `bashdeps.bash`.

It is deliberately narrower than a package manager.  It does not resolve
versions, discover releases, execute install hooks, construct dependency graphs,
or infer whether a downloaded file is a script, library, template, image, data
file, or another ordinary artifact.

The committed declaration and approved SHA-256 digest define the intended bytes.

## Runtime Requirements

Version 1 requires:

- Bash 4.3 or newer;
- `curl` or a usable HTTPS-capable `wget` when network acquisition is needed;
- `sha256sum` or `shasum -a 256` for SHA-256 verification;
- ordinary Unix-like file utilities and filesystem behavior required for staging
  and publication.

Downloader selection prefers `curl`, then falls back to `wget`.
SHA-256 selection prefers `sha256sum`, then falls back to `shasum -a 256`.

For version 1, a Wget backend is usable only when `wget --help` advertises both
`-T` timeout control and `-t` tries control.  The adapter uses `-T 120 -t 1` so
one Wget invocation represents one bounded bashdeps acquisition attempt.  A
present Wget command that lacks those controls is treated as an unavailable
runtime capability.  See ADR-012.

A downloader is not required when an operation does not need network access.

## Manifest

The conventional manifest filename is:

```text
dependencies.txt
```

Each logical record declares one artifact using named fields:

```text
id=IDENTITY url=HTTPS_URL dest=RELATIVE_PATH digest=sha256:HEX_DIGEST
```

A logical record may occupy one physical line:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

or may use explicit trailing continuation markers:

```text
id=wesley-dean/mktext@0.0.7 \
  url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash \
  dest=vendor/mktext.bash \
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

Those forms are semantically equivalent.

### Physical-line folding

Manifest physical lines are assembled into logical records before field
tokenization.

A physical content line requests continuation only when it ends with a standalone
`\` marker.  The marker must be the final character before the newline and must
be separated from the preceding field text by horizontal whitespace.  Spaces or
tabs after the marker are invalid.

When a continuation marker is present, bashdeps removes the marker and its
separating whitespace, trims leading horizontal whitespace from the immediately
following physical content line, and joins the fragments with exactly one ASCII
space.  Repeated markers may continue the same logical record across additional
physical lines.

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

Indentation alone never continues a record.  Leading spaces or tabs are cosmetic.
A physical content line without a preceding continuation marker begins a new
logical record even when it is indented.

Outside an active continuation, blank lines are ignored and a line whose first
non-horizontal-whitespace character is `#` is ignored.

Inside an active continuation, the very next physical line must contain record
content.  A blank line or full-line comment immediately after a continuation
marker is an invalid manifest rather than something bashdeps silently skips.

A continuation marker on the final physical line of the manifest is invalid.

The `\` marker is a bashdeps manifest continuation convention only.  It does not
enable shell escaping, quoting, expansion, or evaluation.

See ADR-015 for the line-folding rationale and complete physical-line rules.

### Record tokenization

After physical-line folding, a logical manifest record is parsed in two stages.

First, the record is split on horizontal whitespace into field tokens.
Values therefore cannot contain literal spaces or tabs in version 1.

Second, each field token is split at its first, left-most `=` character.
Everything after that first `=` belongs to the field value unchanged.

For example:

```text
url=https://example.test/download?first=1&second=2
```

parses as:

```text
key   = url
value = https://example.test/download?first=1&second=2
```

Additional equals signs in values are data.

Manifest contents are never sourced, evaluated, shell-expanded, or interpreted as
shell commands.

### Required fields

Each record requires exactly one of each field:

- `id`
- `url`
- `dest`
- `digest`

Field order is irrelevant, including when fields occupy separate physical lines.
Any valid field may appear first; `id=` is not required to be physically first.

Duplicate fields, missing fields, and unknown fields are errors.

Unknown fields fail closed so an older bashdeps release never silently accepts a
manifest that depends on newer semantics.

### Comments

Blank lines are ignored outside an active continuation.

A line whose first non-horizontal-whitespace character is `#` is ignored outside
an active continuation.

A blank line or full-line comment immediately after a trailing continuation marker
is invalid because the marker promises that the next physical line continues the
same logical record.

Inline comments are not supported in version 1.  For example:

```text
id=example@1  # dependency identity
```

is invalid because `#` and the following text are parsed as ordinary record
components rather than comment syntax.

### id

`id` is non-empty opaque metadata without whitespace.

The recommended convention is:

```text
PACKAGE@VERSION
```

Bashdeps does not parse or enforce semantic-version meaning from `id`.

IDs must be unique within a manifest.

### url

`url` must begin with:

```text
https://
```

Other schemes are invalid in version 1.

### dest

`dest` names the complete ordinary-file destination relative to the physical
current working directory from which bashdeps is invoked.

It is not relative to the manifest file and bashdeps does not discover a Git
repository root.

A destination must:

- be non-empty;
- be relative;
- not begin or end with `/`;
- not contain repeated `/` separators;
- not contain whitespace;
- not contain a component equal to `.` or `..`;
- be strictly beneath the selected destination root.

By default, the selected destination root is:

```text
vendor
```

Therefore these are valid by default:

```text
dest=vendor/tool.bash
dest=vendor/templates/report.tmpl
```

while these are invalid by default:

```text
dest=Makefile
dest=src/generated.bash
dest=vendor-old/tool.bash
dest=vendor
```

Containment is evaluated at a path-component boundary.  A destination under
`vendor-old/` therefore does not satisfy the default `vendor/` policy merely
because the strings share a prefix.

Existing symbolic links in any destination path component are rejected.
An existing final destination must be a regular file and must not be a symbolic
link.

Destinations must be unique within a manifest.

### digest

`digest` is mandatory and has this form:

```text
sha256:<64 lowercase hexadecimal characters>
```

An upstream project does not need to publish the digest.  The consuming project
may calculate and commit the SHA-256 digest of the exact artifact it reviewed and
approved.

When upstream publishes a SHA-256 checksum, the consuming project may use that
published value as the committed `digest=` value.  Synchronization still trusts
the committed declaration; bashdeps does not dynamically replace it with a live
upstream checksum.

Digest equality establishes byte identity with the committed declaration.  It
does not establish that the upstream software is safe, correctly versioned, or
free from vulnerabilities.

## Destination Root Policy

The default destination root is `vendor`.

`install`, `sync`, and `verify` accept an explicit invocation-level override:

```text
--dest-root PATH
```

The option must precede the manifest path or install declaration fields.

The selected root is a containment rule only.  It does not prepend to, rewrite,
or otherwise transform `dest`.

For example:

```text
bashdeps.bash sync --dest-root assets dependencies.txt
```

permits:

```text
dest=assets/logo.png
```

and rejects:

```text
dest=vendor/tool.bash
dest=Makefile
```

The same manifest declaration always names the same project-relative path.  A
caller cannot relocate it merely by changing `--dest-root`.

The selected root must itself be a normalized project-relative path after
trailing slash normalization.  It must be non-empty and must not:

- be absolute;
- contain whitespace;
- contain repeated internal `/` separators;
- contain a component equal to `.` or `..`.

One or more trailing `/` characters on `--dest-root` are ignored before
validation, so these are equivalent:

```text
--dest-root vendor
--dest-root vendor/
```

Nested roots such as `third_party/vendor` are permitted.

The destination root is invocation policy rather than manifest data.  Version 1
does not define a `dest-root=` manifest field.

See ADR-013 for the rationale and superseded destination-scope decisions.

## Commands

### install

```text
bashdeps.bash install [--dest-root PATH] id=... url=... dest=... digest=...
```

`install` materializes one explicitly declared artifact.

The CLI fields use the same logical field grammar as one manifest record.  Physical
line folding is a manifest-file feature and does not change ordinary shell argv
parsing for `install`.  Callers invoking the command through a shell must quote
arguments when ordinary shell syntax requires it; for example, a URL containing
`&` should be passed as one quoted argument.

If the existing destination is a valid ordinary file within the selected root
whose SHA-256 digest already matches, `install` succeeds without network access or
mutation.

Otherwise, `install`:

1. validates the selected destination root and complete declaration;
2. verifies that the declared destination is strictly beneath the selected root;
3. acquires a candidate into private staging;
4. verifies the candidate SHA-256 digest;
5. creates required parent directories only after verification;
6. publishes the verified bytes conservatively;
7. sets a newly published file to mode `0644`;
8. re-hashes the final destination;
9. succeeds only if the final bytes match the declaration.

### verify

```text
bashdeps.bash verify [--dest-root PATH] [MANIFEST]
```

The default manifest is `dependencies.txt` and the default destination root is
`vendor`.

`verify`:

- validates the selected destination root;
- folds, parses, and validates the complete manifest;
- rejects any declaration outside the selected destination root;
- performs no network access;
- intentionally performs no filesystem mutation;
- verifies that every declared destination exists as an acceptable regular file;
- verifies that every declared destination has the approved SHA-256 digest;
- ignores undeclared files;
- ignores destination file mode.

A valid empty manifest verifies successfully.

### sync

```text
bashdeps.bash sync [--dest-root PATH] [MANIFEST]
```

The default manifest is `dependencies.txt` and the default destination root is
`vendor`.

`sync` converges the complete manifest-defined set.

It:

1. validates the selected destination root;
2. folds, parses, and validates the whole manifest;
3. rejects any declaration outside the selected root;
4. validates filesystem safety for every declared destination;
5. hashes existing destinations;
6. reuses destinations whose bytes already match;
7. identifies missing or mismatched destinations;
8. acquires all required candidates into private staging;
9. verifies every required candidate before intentional publication begins;
10. creates missing parent directories only after candidate preflight succeeds;
11. publishes verified candidates;
12. performs a final verification of every declared destination.

`sync` does not literally execute `bashdeps.bash install` once per manifest line.
`install` and `sync` share internal logic, while `sync` preserves whole-manifest
preflight before publication.

`sync` does not remove files that are absent from the current manifest.

Multi-file synchronization is not a filesystem-wide atomic transaction.  If an
unpredictable failure occurs during publication, some files may have been updated
and others may not.  A later `sync` determines state from actual destination
bytes rather than prior intent.

### help

These forms are equivalent:

```text
bashdeps.bash help
bashdeps.bash -h
bashdeps.bash --help
```

Help writes to standard output and returns status 0.

### version

These forms are equivalent:

```text
bashdeps.bash version
bashdeps.bash --version
```

Generated release artifacts report semantic version, build date/source revision
timestamp, and source commit metadata.  The first version line identifies the
program as `bashdeps.bash`.

## Downloader Behavior

When acquisition is necessary, bashdeps chooses one supported downloader:

```text
curl -> wget -> failure
```

Downloader-specific behavior is isolated behind a private transport adapter.

The selected downloader writes only to private staging.  It never writes directly
over a declared destination.

The acquisition layer may make one initial transfer attempt plus up to two
retries for transport failures.

The curl backend uses HTTPS-only redirect restrictions, a redirect limit, and
finite connection/transfer timeouts as defined by ADR-004.

The Wget backend is eligible only when its local help surface advertises `-T` and
`-t`.  When selected, version 1 invokes Wget with a 120-second timeout and one
backend-managed try per acquisition-layer attempt.  Portable Wget implementations
still have different timeout semantics, so bashdeps does not claim
transport-policy parity with curl.  Mandatory SHA-256 verification remains the
backend-independent authority for candidate acceptance.

`verify` never invokes a downloader.

## SHA-256 Behavior

Hash implementation selection is:

```text
sha256sum -> shasum -a 256 -> failure
```

The calculated lowercase hexadecimal digest is compared with the 64-character
hexadecimal portion of the declaration.

No successful downloader status, HTTP metadata, filename, timestamp, ETag, or
version label substitutes for SHA-256 equality.

## Filesystem Behavior

The physical current working directory is the project root for one invocation.
The selected destination root is a project-relative security boundary within that
project root.

Network candidates are staged away from final destinations.

For multi-record `sync`, all candidates required by the current operation are
acquired and verified before intentional publication begins.

Before publication, existing path components are checked for symbolic links.
Missing parent directories beneath the selected destination root may then be
created automatically.

A verified candidate is copied to a destination-adjacent temporary ordinary file,
set to mode `0644`, and replaced into the final path using rename-style behavior
where practical.

An already-correct destination is not chmodded merely to normalize its mode.

Version 1 does not implement concurrent mutation coordination or locking.

## Output and Exit Statuses

Successful `install`, `sync`, and `verify` operations normally write no standard
output.

Diagnostics are written to standard error and use `bashdeps.bash` as the program
name prefix.

The public exit status contract is:

```text
0  success, help, or version output
1  verify completed but one or more destinations are missing or mismatched
2  invalid CLI usage, invalid manifest, invalid dependency declaration, or invalid destination-root policy
3  required runtime capability is unavailable or unusable
4  network acquisition failed
5  acquired candidate bytes do not match the approved digest
6  filesystem safety, staging, or publication failed
```

A malformed digest is status 2.  A syntactically valid declaration whose acquired
candidate hashes differently is status 5.

An invalid folded record, including an unterminated continuation, a blank/comment
line where continued record content is required, or a malformed continuation
marker, is status 2.

An invalid `--dest-root` value or a declaration outside the selected destination
root is status 2 because the operation has not reached filesystem publication.

## Public Interface Boundary

The supported public interface is the `bashdeps.bash` executable CLI.

Bashdeps does not provide a sourceable public library API in version 1.
Private functions and variables use the `__bashdeps_` namespace and are not
compatibility commitments.

The Bash artifact may remain inert when sourced, but sourcing is not a documented
integration method.

## Build Artifacts

Maintained source:

```text
src/bashdeps.bash
```

After manifest-managed build dependencies have been prepared, `make build`
generates exactly:

```text
dist/bashdeps.dev.bash
dist/bashdeps.bash
dist/bashdeps.min.bash
dist/bashdeps.dev.bash.256
dist/bashdeps.bash.256
dist/bashdeps.min.bash.256
```

`bashdeps.dev.bash` is the complete assembled developer artifact and retains
source/documentation comments.

`bashdeps.bash` is the normal consumer artifact.  It is derived from the complete
developer artifact by removing full-line comments after the shebang while
preserving executable behavior.

`bashdeps.min.bash` is derived from the completed comment-stripped artifact using
the commit-pinned Bash-Minifier build dependency.  Comment stripping and
minification therefore apply after complete program assembly, including any Bash
libraries incorporated into the generated program.

All three Bash artifacts retain a valid shebang and executable mode and expose the
same public CLI contract.

Each Bash artifact SHALL have one matching `.256` checksum companion containing
the SHA-256 digest and artifact filename in conventional checksum-tool syntax.
The normal artifact can therefore be checked from the distribution directory with:

```text
sha256sum -c bashdeps.bash.256
```

or the supported `shasum` equivalent.

No aggregate `SHA256SUMS` file is generated.

The same public behavior suite is run against maintained source and all three
generated Bash artifacts.  The minified artifact is accepted only when its
syntax, Bash 4.3 compatibility, checksum, and public behavior validation pass.

`make build` does not acquire, repair, or verify dependency state.  It is
network-free and requires an already-prepared `vendor/bash-minifier.bash`.  A
fresh checkout should use `make all` or run `make deps` before `make build`.

The generated executables do not require Bash-Minifier, `dependencies.txt`, or the
vendor tree at runtime.

## Consumer Make Integration

The recommended consumer boundary is:

```text
make deps        bootstrap bashdeps.bash if needed, then bashdeps.bash sync
make deps-check  verify using an already-present valid bashdeps.bash bootstrap artifact
make build       build only from current local inputs
make all         deps, then build
```

Projects that intentionally use a dependency tree other than `vendor/` should
make the destination-root policy explicit in their Make targets, for example:

```text
bashdeps.bash sync --dest-root third_party dependencies.txt
bashdeps.bash verify --dest-root third_party dependencies.txt
```

The bashdeps bootstrap artifact itself remains outside `dependencies.txt` and must
be independently pinned and SHA-256 verified by the consuming project.
