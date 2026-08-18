# ADR-017: Self-Host Project Dependency Synchronization

Date: 2026-08-17

## Status

Proposed

## Intent and Scope

This ADR defines how the bashdeps repository consumes one released `bashdeps.bash`
artifact as its bootstrap dependency and then uses that artifact to synchronize the
repository's remaining external build/documentation inputs from `dependencies.txt`.

The selected boundary is deliberately narrow:

```text
Makefile
  -> vendor/bashdeps.bash
  -> make deps
       -> vendor/bashdeps.bash sync dependencies.txt
            -> vendor/mktext.bash
            -> vendor/doxygen-bash.awk
```

The Makefile therefore owns acquisition and verification of exactly one external
artifact: the released bashdeps executable required to process the manifest.
After that bootstrap succeeds, `bashdeps.bash` owns acquisition and integrity
verification for dependencies declared by the repository manifest.

This ADR refines ADR-008 for the bashdeps repository itself and supersedes the
Doxygen-filter acquisition portion of ADR-016.

## Context

ADR-008 established the bootstrap paradox: a dependency tool cannot use itself to
obtain the first copy of itself.  It therefore requires one small independently
verified bootstrap path in every consumer.

The initial bashdeps Makefile independently downloaded the Bash Doxygen filter from
a mutable `main` URL.  That meant the repository already contained a second direct
external-acquisition implementation in addition to the eventual bashdeps bootstrap
path.

The project also needs a concrete real-world manifest that exercises the mechanism
that consumers such as adrctl will use.  adrctl consumes mktext as a build input and
uses the Bash Doxygen filter for reference documentation.  Keeping release-pinned
records for both artifacts in bashdeps' own `dependencies.txt` gives the tool a
self-hosting integration surface without claiming that mktext is part of the
bashdeps runtime implementation.

The desired separation is therefore:

- Make knows how to bootstrap one trusted `bashdeps.bash` release artifact;
- bashdeps knows how to interpret and synchronize `dependencies.txt`;
- the manifest records mktext and bash-doxygen identities, immutable retrieval
  locations, destinations, and SHA-256 digests;
- ordinary `make build` remains independent of dependency synchronization;
- documentation generation may require synchronized dependencies before invoking
  Doxygen.

## Decision Drivers

- Exercise the released bashdeps artifact as a real consumer would.
- Reduce direct download/checksum logic in the Makefile to one bootstrap artifact.
- Preserve a committed SHA-256 trust anchor for the bootstrap executable.
- Move mktext and bash-doxygen acquisition policy into `dependencies.txt`.
- Replace the mutable bash-doxygen `main` URL with an immutable release-tagged
  source location.
- Keep `vendor/` generated and ignored.
- Preserve ADR-008's separation between ordinary build work and dependency
  synchronization.
- Avoid pretending that mktext is a bashdeps runtime dependency merely because it
  is present in this repository's integration manifest.

## Decision

### Bootstrap artifact

The bashdeps repository SHALL bootstrap the released consumer artifact at:

```text
vendor/bashdeps.bash
```

The bootstrap executable SHALL NOT be declared in `dependencies.txt`.

The Makefile SHALL commit and pin:

- the exact bashdeps release version;
- an immutable release-asset URL for `bashdeps.bash`; and
- the expected SHA-256 digest of that exact release artifact.

The bootstrap target SHALL accept an existing `vendor/bashdeps.bash` only when its
SHA-256 digest matches the committed value.  A missing or mismatched artifact
SHALL be replaced only after a newly downloaded candidate has passed SHA-256
verification.

The bootstrap target SHALL publish the verified file as executable because the
Makefile invokes it directly.

Although ADR-008 recommends placing the bootstrap executable outside manifest
managed paths, this repository deliberately places it under `vendor/` because:

1. the project already treats `vendor/` as disposable generated dependency state;
2. bashdeps does not prune undeclared files during `sync`; and
3. the bootstrap executable remains outside the manifest and therefore outside the
   set of paths bashdeps is asked to materialize.

This is a repository-specific refinement, not a change to the general consumer
recommendation in ADR-008.

### Manifest-managed dependencies

The repository SHALL contain a committed root-level:

```text
dependencies.txt
```

The initial manifest SHALL declare:

```text
vendor/mktext.bash
vendor/doxygen-bash.awk
```

The mktext record SHALL reference the latest reviewed release asset selected at the
time of this decision.

The bash-doxygen record SHALL reference the latest reviewed release tag selected at
the time of this decision.  Because the bash-doxygen release workflow currently
creates a GitHub release without attaching `doxygen-bash.awk` as a release asset,
the manifest SHALL use the immutable raw file at that release tag rather than the
mutable `main` branch URL.

Both records SHALL use committed SHA-256 digests as the authority for acceptable
bytes.

### `make deps`

The Makefile SHALL provide:

```text
make deps
```

The target SHALL:

1. ensure `vendor/bashdeps.bash` exists and matches the committed bootstrap digest;
2. invoke that executable as a process; and
3. run `sync` against the repository's `dependencies.txt`.

Conceptually:

```text
vendor/bashdeps.bash sync dependencies.txt
```

The target MAY use the network because synchronization may need to acquire missing
or mismatched manifest entries.

### Ordinary builds

`make build` SHALL remain independent of `make deps`.

The existence of the self-hosting integration does not make dependency acquisition
an implicit prerequisite for generating bashdeps release artifacts from maintained
source.

### Documentation generation

`make docs` requires `vendor/doxygen-bash.awk` and therefore SHALL ensure manifest
dependencies are synchronized before Doxygen runs.

Because bashdeps publishes newly materialized files as mode `0644` and does not
infer executability, the documentation target SHALL explicitly make
`vendor/doxygen-bash.awk` executable before Doxygen invokes it as a filter.

The Makefile SHALL no longer contain a standalone URL/download recipe for the
Doxygen filter.

### Cleanup

`vendor/` remains generated state and SHALL remain ignored by Git.

The broad development cleanup operation SHALL remove the generated vendor tree so
both the bootstrap executable and manifest-managed dependencies can be reconstructed
from committed trust data.

## Current Pins

At the time this ADR was drafted, the reviewed release inputs were:

```text
bashdeps      v0.0.5  bashdeps.bash
mktext        v0.0.9  mktext.bash
bash-doxygen  v0.0.6  doxygen-bash.awk
```

The committed Makefile and manifest remain authoritative for the exact URLs and
SHA-256 digests.  Future upgrades should change version, URL, and digest together
as one reviewed dependency update.

## Considered Alternatives

### Keep direct Makefile download rules for every dependency

This preserves the current Doxygen pattern and could add a similar rule for
mktext.  It was rejected because it duplicates the parsing, acquisition,
verification, staging, and failure policy that bashdeps exists to centralize.

### Put `vendor/bashdeps.bash` in `dependencies.txt`

This creates a bootstrap cycle: bashdeps would be required to read the declaration
that obtains bashdeps.  The bootstrap executable therefore remains independently
managed by Make.

### Place the bootstrap executable under `.build/`

ADR-008 recommends this for ordinary consumers to separate the tool from the tree
it manages.  The bashdeps repository instead uses `vendor/bashdeps.bash` because
`sync` does not prune undeclared files and the requested self-hosting layout treats
the complete vendor tree as disposable generated state.  This exception remains
local to this repository.

### Keep bash-doxygen on the moving `main` URL

A committed digest would still reject changed bytes, but a mutable source URL can
make historical reconstruction fail after upstream changes.  Pinning the raw file
to the reviewed release tag gives the manifest a stable source identity as well as
a stable digest.

### Treat mktext as part of the bashdeps build

The current bashdeps build does not use mktext.  Inventing a build dependency merely
to justify the manifest would misdescribe the architecture.  The record exists as
a deliberate self-hosting/integration dependency and mirrors a real dependency
needed by adrctl.

## Consequences

The Makefile retains one unavoidable bootstrap acquisition path and removes
project-specific acquisition logic for the dependencies that follow it.

`make deps` becomes a concrete end-to-end demonstration of the product's intended
consumer workflow.

Documentation generation now exercises the same dependency synchronization path
that downstream consumers are expected to use.

The manifest becomes the auditable source of truth for mktext and bash-doxygen
version, source, destination, and digest data.

A bootstrap failure prevents manifest synchronization.  This is inherent in the
self-hosting trust chain and is intentionally visible rather than hidden.

The repository's ordinary release build remains usable without running `make deps`
unless a separate build input later creates a genuine dependency on a manifest
artifact.

## Validation Requirements

CI SHOULD contain an explicit integration job that starts from a clean checkout,
runs `make deps`, and verifies that:

- `vendor/bashdeps.bash` exists and is executable;
- `vendor/mktext.bash` exists;
- `vendor/doxygen-bash.awk` exists;
- `vendor/bashdeps.bash verify dependencies.txt` succeeds.

This live acquisition check is an integration test and SHOULD remain separate from
the deterministic ordinary behavior suite described by ADR-010.

## Related Decisions

- Refines repository bootstrap placement from: ADR-008
- Related to: ADR-009
- Related to: ADR-010
- Supersedes Doxygen-filter acquisition portions of: ADR-016
