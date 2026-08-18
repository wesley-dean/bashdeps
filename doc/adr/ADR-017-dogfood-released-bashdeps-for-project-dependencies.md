# ADR-017: Dogfood Released Bashdeps for Project Dependencies

Date: 2026-08-17

## Status

Proposed

## Intent and Scope

This ADR defines how the bashdeps repository uses a released `bashdeps.bash`
artifact as its one directly bootstrapped external dependency and delegates the
repository's remaining external artifact acquisition to that released tool through
`dependencies.txt`.

The selected boundary is:

```text
Makefile
  -> bootstrap and verify vendor/bashdeps.bash
  -> make deps
       -> vendor/bashdeps.bash sync dependencies.txt
            -> vendor/mktext.bash
            -> vendor/doxygen-bash.awk
```

The Makefile therefore owns acquisition and verification of exactly one external
artifact: the released bashdeps executable required to process the manifest.
After that bootstrap succeeds, the released executable owns acquisition and byte
verification for artifacts declared by the manifest.

This ADR applies to repository development and documentation tooling.  It does not
change the public `bashdeps.bash` CLI or the runtime dependency model.

It refines ADR-008 for the bashdeps repository itself and supersedes the direct
Doxygen-filter acquisition portion of ADR-016.

## Context

ADR-008 documents the unavoidable bootstrap boundary: bashdeps cannot use a
manifest to obtain the first copy of itself.  A consumer therefore keeps one small,
explicit, independently verified bootstrap path.

The README now documents the corresponding consumer Make contract:

```text
make deps        bootstrap/verify bashdeps if needed, then sync dependencies.txt
make deps-check  verify existing bashdeps, then verify dependencies.txt offline
make build       build only from current local inputs
make all         deps, then build
```

The bashdeps repository should exercise that contract as a real consumer rather
than describe an integration that its own development workflow does not use.

The current Makefile also contains a second direct acquisition path for the Bash
Doxygen filter.  It downloads `doxygen-bash.awk` from the upstream `main` branch
without a committed digest.  That duplicates acquisition policy and uses a mutable
source identity even though bashdeps exists to centralize exact artifact
materialization.

`mktext` is not used by the bashdeps implementation.  It is used by adrctl, whose
stale cached mktext incident motivated bashdeps.  Including mktext in this
repository's `dependencies.txt` gives bashdeps a concrete multi-artifact dogfooding
surface that mirrors the consumer pattern intended for adrctl without pretending
that mktext is a bashdeps runtime dependency.

## Decision Drivers

- Make bashdeps itself exercise the consumer integration documented in its README.
- Keep direct Makefile acquisition limited to the unavoidable bashdeps bootstrap.
- Verify the bootstrap executable against committed SHA-256 trust data before use.
- Move ordinary external artifact declarations into `dependencies.txt`.
- Replace the mutable bash-doxygen `main` URL with a release-pinned source.
- Preserve a genuinely network-free and non-repairing `deps-check` operation.
- Preserve `make build` as a dependency-management-free operation.
- Make `make all` the explicit convenience path for synchronization followed by
  build.
- Keep `vendor/` generated, ignored, and reconstructable.
- Preserve bashdeps' rule that ordinary artifact executability is consumer policy,
  not something inferred during materialization.

## Decision

### Bootstrap artifact

The bashdeps repository SHALL directly bootstrap the released consumer artifact at:

```text
vendor/bashdeps.bash
```

The bootstrap executable SHALL NOT appear in `dependencies.txt`.

The Makefile SHALL pin:

- the exact bashdeps release version;
- the immutable release-asset URL for `bashdeps.bash`; and
- the expected SHA-256 digest of that release artifact.

The bootstrap target SHALL verify an existing `vendor/bashdeps.bash` before reuse.
If the file is absent or its digest differs from the committed trust value, the
target SHALL download a candidate to a temporary path, verify that candidate, and
replace the destination only after successful verification.

The published bootstrap artifact SHALL be executable because Make invokes it as a
program.

The repository-specific use of `vendor/bashdeps.bash` is compatible with ADR-008's
requirement that the bootstrap remain outside manifest-managed paths.  Bashdeps
manages declared destination paths and does not prune undeclared files.  Therefore
`vendor/bashdeps.bash` remains outside the set of paths managed by this repository's
manifest even though it shares the broader `vendor/` directory.

Consumers that give bashdeps exclusive ownership of an entire dependency tree may
still prefer ADR-008's `.build/bashdeps.bash` convention.  This ADR does not change
that general guidance.

### Manifest-managed artifacts

The repository SHALL contain a committed root-level:

```text
dependencies.txt
```

The initial manifest SHALL declare:

```text
vendor/mktext.bash
vendor/doxygen-bash.awk
```

Each record SHALL pin a reviewed release identity, an immutable retrieval location,
the complete repository-relative destination, and a committed SHA-256 digest.

At the time of this decision, the reviewed release inputs are:

```text
bashdeps      v0.0.6  bashdeps.bash
mktext        v0.0.9  mktext.bash
bash-doxygen  v0.0.6  doxygen-bash.awk
```

The Makefile and `dependencies.txt` remain authoritative for the exact URLs and
digests.  Future dependency upgrades should change version, URL, and digest
together as one reviewed change.

The bash-doxygen release currently does not attach `doxygen-bash.awk` as a release
asset.  Its manifest record SHALL therefore use the immutable raw file at the
reviewed release tag instead of the mutable `main` branch URL.

### `make deps`

The repository SHALL provide:

```text
make deps
```

The target SHALL:

1. ensure `vendor/bashdeps.bash` exists and matches the committed bootstrap digest;
2. verify the bootstrap artifact immediately before use; and
3. invoke:

```text
vendor/bashdeps.bash sync dependencies.txt
```

`make deps` MAY access the network and MAY mutate manifest-declared destinations.
Correct existing dependency bytes should be reused by bashdeps without a network
request.

### `make deps-check`

The repository SHALL provide:

```text
make deps-check
```

This target SHALL be network-free and SHALL NOT repair or bootstrap anything.
It SHALL:

1. require an already-present executable `vendor/bashdeps.bash`;
2. verify its committed SHA-256 digest; and
3. invoke:

```text
vendor/bashdeps.bash verify dependencies.txt
```

A missing, tampered, or otherwise invalid bootstrap artifact SHALL make
`deps-check` fail rather than trigger acquisition.

### `make build`

`make build` SHALL remain independent of `deps`, `deps-check`, and the bootstrap
recipe.

Ordinary repeated builds SHALL NOT hash the dependency set merely because a build
was requested, and SHALL NOT acquire external artifacts implicitly.

### `make all`

`make all` SHALL be the explicit convenience path for callers that want dependency
convergence before building.

It SHALL sequence:

```text
make deps
make build
```

The ordering SHALL be explicit rather than represented as two unordered parallel
prerequisites.

### Documentation generation

`make docs` requires `vendor/doxygen-bash.awk` and SHALL synchronize project
dependencies before invoking Doxygen.

Bashdeps materializes newly acquired ordinary artifacts as mode `0644` and does not
infer executability.  Therefore the `docs` target SHALL explicitly apply executable
mode to `vendor/doxygen-bash.awk` immediately before Doxygen uses the filter.

The Makefile SHALL no longer contain the bash-doxygen version, URL, digest, or a
standalone Doxygen-filter download recipe.  Those dependency declarations belong
in `dependencies.txt`.

The existing Pages workflow may continue to invoke `make docs`; that target will
exercise the same dependency path used for local documentation generation.

### Generated state and cleanup

`vendor/` SHALL remain ignored by Git.

`make clean` SHALL remain focused on ordinary `dist/` build products.

`make distclean` SHALL remove the generated documentation tree and the complete
`vendor/` tree so the bootstrap and manifest-managed artifacts can be reconstructed
from committed trust data.

## Considered Alternatives

### Continue downloading bash-doxygen directly from Make

This preserves ADR-016's initial implementation, but duplicates artifact
acquisition policy and bypasses the mechanism this repository exists to provide.
It also leaves the filter tied to a mutable upstream branch URL.  This option is
rejected.

### Put bashdeps itself in `dependencies.txt`

This creates the bootstrap cycle ADR-008 explicitly avoids: the tool would be
needed to read the manifest entry that obtains the tool.  The bootstrap artifact
therefore remains directly managed by Make.

### Put the bootstrap under `.build/`

ADR-008 recommends `.build/bashdeps.bash` as a clean general convention when the
bootstrap should be structurally separate from a managed dependency tree.

This repository uses `vendor/bashdeps.bash` deliberately because bashdeps does not
prune undeclared files, only manifest-declared destinations are managed, and the
entire vendor tree is disposable generated state for this project.  The bootstrap
remains absent from the manifest, preserving the actual trust boundary.

### Make `build` depend on `deps`

This would make first use convenient but would couple ordinary artifact generation
to dependency hashing, potential network access, and filesystem mutation.
The documented consumer contract intentionally keeps those operations separate.

### Make `deps-check` repair a missing or invalid bootstrap

That would make the command convenient but would destroy its offline and
non-mutating meaning.  `make deps` is the explicit repair path.

### Omit mktext because bashdeps does not use it

This would leave the repository with only one manifest-managed artifact and would
avoid carrying an integration-only dependency.  It was rejected for this project
because the requested dogfooding manifest is intended to exercise the same
multi-artifact pattern adrctl will consume, including the dependency whose stale
cache incident motivated bashdeps.

The documentation SHALL remain clear that mktext is an integration dependency of
the bashdeps repository, not a runtime or build dependency of the bashdeps CLI.

## Consequences

The bashdeps repository becomes a working reference consumer of its own released
artifact and documented Make integration.

A fresh checkout can use `make all` to acquire approved dependencies and then build,
or use `make deps` and `make build` as explicit separate operations.

Repeated `make build` invocations remain free of dependency synchronization and
verification overhead.

`make deps-check` provides a meaningful offline integrity check after the bootstrap
artifact has already been obtained.

Reference documentation now exercises the same manifest-mediated acquisition path
intended for downstream consumers.

The Makefile retains one unavoidable external bootstrap implementation, while
ordinary project dependency declarations move to the manifest.

The repository intentionally carries mktext as an integration dependency even
though the bashdeps implementation does not consume it.

## Validation Requirements

CI SHOULD exercise the repository as a consumer by verifying that a clean runner
can:

1. run `make build` without creating dependency state;
2. run `make all` and obtain the pinned bootstrap plus both manifest-managed
   artifacts;
3. run `make deps-check` successfully after synchronization;
4. run `make docs` through the synchronized Doxygen filter; and
5. run `make deps-check` successfully after the consumer changes the Doxygen
   filter's executable mode, confirming that bashdeps verification remains based
   on bytes rather than mode.

The existing deterministic Bats suite remains the primary CLI behavior test.  Live
public network access belongs only in this explicit repository-integration check.

## Related Decisions

- Refines: ADR-008
- Related to: ADR-003
- Related to: ADR-006
- Related to: ADR-009
- Related to: ADR-015
- Supersedes the direct Doxygen-filter acquisition portion of: ADR-016
