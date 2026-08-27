# ADR-019: Standardize SHA-256 Checksum Companion Filenames

Date: 2026-08-27

## Status

Proposed

## Intent and Scope

This Architecture Decision Record standardizes the filename suffix used for
SHA-256 checksum companions published with bashdeps release artifacts.

The change is deliberately narrow.  It changes release-sidecar names from `.256`
to `.sha256`; it does not change checksum contents, the SHA-256 algorithm, the
manifest digest grammar, the downloader trust model, or the public bashdeps CLI.

This ADR supersedes only the checksum-filename portions of ADR-008, ADR-009, and
ADR-018.  Those ADRs remain the historical record of the bootstrap, release, and
three-flavor decisions that introduced per-artifact checksum companions.

## Context

Bashdeps releases currently publish one SHA-256 checksum companion for each Bash
artifact using a `.256` suffix.  The suffix is technically sufficient because
checksum tools do not require a particular filename extension, but `.256` is not
self-describing and may be associated with unrelated formats or tools.

The `.sha256` suffix states the checksum algorithm directly and is readily
understood without repository-specific documentation.  The related
`bash-doxygen` project has adopted the same convention for new releases, making
this a useful opportunity to standardize the release surface across related Bash
projects.

The migration must not weaken bashdeps' existing trust boundary.  A consuming
repository authorizes dependency bytes through a SHA-256 digest committed in
source.  A remotely published checksum sidecar may help a maintainer review or
obtain that value, but synchronization and bootstrap behavior must not silently
replace committed trust data with a live remote checksum.

Historical releases also remain part of the ecosystem.  Existing `.256` assets
should remain usable by tools that explicitly retrieve checksum sidecars even
after new releases publish only `.sha256` companions.

## Decision Drivers

- Make the checksum algorithm obvious from the sidecar filename.
- Use one consistent checksum naming convention across related Bash projects.
- Preserve the existing one-artifact/one-checksum relationship.
- Preserve conventional `sha256sum`/`shasum` checksum-file contents.
- Avoid publishing duplicate checksum assets indefinitely.
- Preserve access to historical releases that used `.256`.
- Fail closed rather than masking transport or verification failures as legacy
  compatibility.
- Preserve the committed SHA-256 digest as the authority for bashdeps dependency
  acceptance.

## Decision

### Publish `.sha256` companions for new releases

`make build` SHALL produce these checksum files:

```text
dist/bashdeps.dev.bash.sha256
dist/bashdeps.bash.sha256
dist/bashdeps.min.bash.sha256
```

Each checksum file SHALL continue to contain the SHA-256 digest and matching
artifact basename in conventional checksum-tool syntax.  For example:

```text
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  bashdeps.bash
```

The ordinary artifact SHALL therefore be directly verifiable from the
distribution directory with:

```text
sha256sum -c bashdeps.bash.sha256
```

or the supported `shasum` equivalent.

New releases SHALL publish only the `.sha256` checksum companion for each Bash
artifact.  They SHALL NOT also publish duplicate `.256` companions merely for a
transition period.

The project SHALL continue not to generate an aggregate `SHA256SUMS` file.

### Preserve historical release assets

Existing releases and their `.256` checksum companions are historical published
artifacts and SHALL NOT be rewritten solely to adopt the new suffix.

A consumer that explicitly retrieves a checksum companion from releases spanning
both naming eras SHOULD request `<artifact>.sha256` first.  It MAY retry
`<artifact>.256` only when the preferred `.sha256` asset is confirmed to be
absent.

Legacy fallback SHALL NOT be used to recover from or conceal other failures,
including:

- TLS or certificate failures;
- authentication or authorization failures;
- timeouts or connection failures;
- HTTP server errors;
- malformed checksum contents; or
- a checksum mismatch.

Those conditions are failures and SHALL remain failures.

### Preserve committed-digest trust

This compatibility rule does not add checksum-sidecar discovery to the bashdeps
runtime.

Bashdeps manifest records continue to require:

```text
digest=sha256:<64 lowercase hexadecimal characters>
```

and the committed digest remains authoritative for accepted dependency bytes.
Likewise, a consuming Makefile that bootstraps `bashdeps.bash` continues to pin
and verify an expected SHA-256 digest as committed trust data.

Neither synchronization nor bootstrap behavior SHALL dynamically replace the
committed expected digest with a value retrieved from `.sha256` or `.256`.

A maintainer or external helper may use an upstream checksum sidecar while
reviewing a dependency update, but committing the selected digest remains the
explicit authorization step.

## Considered Alternatives

### Keep `.256`

This preserves historical naming and requires no migration, but the suffix does
not identify the checksum algorithm clearly and is less interoperable as a human
convention than `.sha256`.

### Publish both `.sha256` and `.256`

Publishing both would make every new release immediately compatible with consumers
that hard-code the legacy suffix.  It was rejected because the files would contain
the same information, permanently enlarge and clutter the release surface, and
make the deprecated convention appear equally current.

Read-side fallback provides historical compatibility without requiring duplicate
write-side artifacts.

### Replace per-artifact companions with `SHA256SUMS`

An aggregate checksum file is conventional and compact, but bashdeps deliberately
uses one checksum companion per executable so the relationship is explicit in the
filename and each artifact can be downloaded with only its matching verification
file.  The naming migration does not revisit that decision.

### Dynamically trust the published checksum sidecar

Bashdeps could fetch an upstream checksum file during synchronization and use its
value instead of the committed manifest digest.  This was rejected because it
would move the trust decision from reviewed repository source to live upstream
state and would contradict the existing exact-byte trust boundary.

## Consequences

New bashdeps releases expose self-describing `.sha256` checksum filenames while
retaining the same checksum bytes and verification commands apart from the
filename.

Release automation, build tests, current documentation, and agent guidance must
use the new suffix consistently.

Consumers that only use committed digests require no runtime behavior change.
Tools that explicitly retrieve release checksum sidecars can support both naming
eras with a narrow absence-only fallback.

Historical `.256` assets remain valid for the releases that published them.

## Follow-Ups

Related Bash projects may adopt the same producer convention and legacy-read
policy in dependency-safe release order.

Any future feature that teaches bashdeps itself to discover or consume remote
checksum sidecars would require a separate architectural decision because that
would change network behavior and the current trust boundary.

## Related Decisions

- Related to: ADR-001, which defines the exact-byte trust boundary.
- Supersedes checksum-filename portions of: ADR-008.
- Supersedes checksum-filename portions of: ADR-009.
- Supersedes checksum-filename portions of: ADR-018.
