# bashdeps Behavior Specification

## Purpose

`bashdeps` materializes exact, SHA-256-pinned external artifacts at declared
repository-relative destinations.

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

A downloader is not required when an operation does not need network access.

## Manifest

The conventional manifest filename is:

```text
dependencies.txt
```

Each non-blank, non-comment line declares one artifact using named fields:

```text
id=IDENTITY url=HTTPS_URL dest=RELATIVE_PATH digest=sha256:HEX_DIGEST
```

For example:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

### Record tokenization

A manifest record is parsed in two stages.

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

Field order is irrelevant.

Duplicate fields, missing fields, and unknown fields are errors.

Unknown fields fail closed so an older bashdeps release never silently accepts a
manifest that depends on newer semantics.

### Comments

Blank lines are ignored.

A line whose first non-horizontal-whitespace character is `#` is ignored.

Inline comments are not supported in version 1.

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

`dest` names an ordinary file relative to the physical current working directory
from which bashdeps is invoked.

It is not relative to the manifest file and bashdeps does not discover a Git
repository root.

A destination must:

- be non-empty;
- be relative;
- not begin or end with `/`;
- not contain repeated `/` separators;
- not contain a component equal to `.` or `..`.

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

Digest equality establishes byte identity with the committed declaration.  It
does not establish that the upstream software is safe, correctly versioned, or
free from vulnerabilities.

## Commands

### install

```text
bashdeps install id=... url=... dest=... digest=...
```

`install` materializes one explicitly declared artifact.

The CLI fields use the same grammar as one manifest record.  Callers invoking the
command through a shell must quote arguments when ordinary shell syntax requires
it; for example, a URL containing `&` should be passed as one quoted argument.

If the existing destination is a valid ordinary file whose SHA-256 digest already
matches, `install` succeeds without network access or mutation.

Otherwise, `install`:

1. validates the complete declaration and destination path;
2. acquires a candidate into private staging;
3. verifies the candidate SHA-256 digest;
4. creates required parent directories only after verification;
5. publishes the verified bytes conservatively;
6. sets a newly published file to mode `0644`;
7. re-hashes the final destination;
8. succeeds only if the final bytes match the declaration.

### verify

```text
bashdeps verify [MANIFEST]
```

The default manifest is `dependencies.txt`.

`verify`:

- parses and validates the complete manifest;
- performs no network access;
- intentionally performs no filesystem mutation;
- verifies that every declared destination exists as an acceptable regular file;
- verifies that every declared destination has the approved SHA-256 digest;
- ignores undeclared files;
- ignores destination file mode.

A valid empty manifest verifies successfully.

### sync

```text
bashdeps sync [MANIFEST]
```

The default manifest is `dependencies.txt`.

`sync` converges the complete manifest-defined set.

It:

1. parses and validates the whole manifest;
2. validates filesystem safety for every declared destination;
3. hashes existing destinations;
4. reuses destinations whose bytes already match;
5. identifies missing or mismatched destinations;
6. acquires all required candidates into private staging;
7. verifies every required candidate before intentional publication begins;
8. creates missing parent directories only after candidate preflight succeeds;
9. publishes verified candidates;
10. performs a final verification of every declared destination.

`sync` does not literally execute `bashdeps install` once per manifest line.
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
bashdeps help
bashdeps -h
bashdeps --help
```

Help writes to standard output and returns status 0.

### version

These forms are equivalent:

```text
bashdeps version
bashdeps --version
```

Generated release artifacts report semantic version, build date/source revision
timestamp, and source commit metadata.

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

Portable wget implementations have different capabilities.  Bashdeps does not
claim that wget provides transport-policy parity with curl.  Mandatory SHA-256
verification remains the backend-independent authority for candidate acceptance.

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

Network candidates are staged away from final destinations.

For multi-record `sync`, all candidates required by the current operation are
acquired and verified before intentional publication begins.

Before publication, existing path components are checked for symbolic links.
Missing parent directories may then be created.

A verified candidate is copied to a destination-adjacent temporary ordinary file,
set to mode `0644`, and replaced into the final path using rename-style behavior
where practical.

An already-correct destination is not chmodded merely to normalize its mode.

Version 1 does not implement concurrent mutation coordination or locking.

## Output and Exit Statuses

Successful `install`, `sync`, and `verify` operations normally write no standard
output.

Diagnostics are written to standard error.

The public exit status contract is:

```text
0  success, help, or version output
1  verify completed but one or more destinations are missing or mismatched
2  invalid CLI usage, invalid manifest, or invalid dependency declaration
3  required runtime capability is unavailable or unusable
4  network acquisition failed
5  acquired candidate bytes do not match the approved digest
6  filesystem safety, staging, or publication failed
```

A malformed digest is status 2.  A syntactically valid declaration whose acquired
candidate hashes differently is status 5.

## Public Interface Boundary

The supported public interface is the executable CLI.

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

`make build` generates:

```text
dist/bashdeps.dev.bash
dist/bashdeps.bash
dist/SHA256SUMS
```

`bashdeps.dev.bash` retains maintained source comments.

`bashdeps.bash` is the normal consumer artifact and removes full-line source
comments while preserving executable behavior.

No minified artifact is generated by this project.

The same public behavior suite is run against maintained source and both generated
Bash artifacts.

## Consumer Make Integration

The recommended consumer boundary is:

```text
make deps        bootstrap bashdeps if needed, then bashdeps sync
make deps-check  verify using an already-present valid bashdeps bootstrap artifact
make build       build only from current local inputs
make all         deps, then build
```

The bashdeps bootstrap artifact itself remains outside `dependencies.txt` and must
be independently pinned and SHA-256 verified by the consuming project.
