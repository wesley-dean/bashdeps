# ADR-017: Self-Host Build and Development Dependency Management

Date: 2026-08-18

## Status

Proposed

## Intent and Scope

This Architecture Decision Record defines how the bashdeps source repository uses
a previously released, independently verified `bashdeps.bash` artifact to manage
its own ordinary external build and development artifacts.

The selected design is deliberate self-hosting rather than circular bootstrap.
The unreleased source tree does not execute itself in order to obtain the tools
needed to build that same source tree.  Make first bootstraps a known released
`bashdeps.bash`; that released executable then synchronizes the committed
`dependencies.txt` manifest.

For the current repository, the only manifest-managed external artifact is the
`bash-doxygen` AWK filter used to generate reference documentation.  It is a
documentation dependency only.  The normal bashdeps build and release artifacts
do not require it.

This ADR supersedes the portions of ADR-010 that define `make all` as build-only
and the portions of ADR-016 that require Make to download the Doxygen filter
directly from a moving branch.  Those ADRs remain historical records of the prior
decisions.

## Context

bashdeps exists to centralize exact external-artifact acquisition and verification
that would otherwise be repeated in project-specific Make recipes.  The bashdeps
source repository had one remaining example of the pattern it is intended to
replace: `make docs` directly downloaded `doxygen-bash.awk` from the
`bash-doxygen` `main` branch.

The adrctl migration established a clearer architecture:

```text
Makefile
  -> bootstrap and verify one released bashdeps.bash
  -> bashdeps.bash sync dependencies.txt
       -> ordinary external build/development artifacts
```

Applying the same boundary to bashdeps itself creates a conventional bootstrap
relationship:

```text
bashdeps source tree
  |
  +-- Make bootstraps released bashdeps vN
  |
  +-- released bashdeps vN syncs dependencies.txt
  |
  +-- source tree builds/tests bashdeps vN+1
```

The released bootstrap artifact is already complete software.  It is not produced
from the source revision currently being built and therefore does not create a
cycle in the dependency graph.

The current repository has no external artifact required by `make build`.
`bash-doxygen` is required only for Doxygen reference generation.  This matters
for target semantics: a clean `make build` must continue to succeed without
preparing `vendor/`.

## Decision Drivers

- Use bashdeps for the ordinary external artifacts that fit its released contract.
- Keep one small, explicit bootstrap path that can establish the first trusted
  `bashdeps.bash` executable.
- Never require unreleased bashdeps source to bootstrap itself.
- Keep the bootstrap artifact outside the manifest it is used to process.
- Replace moving development-tool URLs with immutable release/tag URLs.
- Make committed URL and SHA-256 data the reviewable source of artifact identity.
- Preserve staged download and verification before publication.
- Keep `make deps-check` genuinely network-free and non-repairing.
- Keep `make build` independent of dependency synchronization and verification.
- Preserve bashdeps' runtime and release portability: released artifacts must not
  require the bootstrap tool, manifest, or vendor tree.
- Treat `vendor/` as generated dependency state.
- Preserve the distinction between documentation tooling and build/runtime inputs.

## Decision

### Bootstrap a released bashdeps artifact

Make SHALL directly own one bootstrap artifact:

```text
vendor/bashdeps.bash
```

The bootstrap SHALL be a pinned stable bashdeps release identified by:

- an explicit version;
- an immutable release asset URL; and
- an expected SHA-256 digest committed in the Makefile.

The initial selected bootstrap is the known-good release already used by adrctl:

```text
version: 0.0.6
asset:   https://github.com/wesley-dean/bashdeps/releases/download/v0.0.6/bashdeps.bash
sha256:  bb6c807fa12c010950bda06172ac0611d278c57aca1f8352f41502d0d76b4e6c
```

An existing bootstrap file MAY be reused only when its bytes match the committed
digest.  A missing or mismatched bootstrap SHALL be replaced only after a staged
download matches that digest.

A failed download or digest verification SHALL NOT publish unverified candidate
bytes over an existing bootstrap path.

### Exclude the bootstrap from dependencies.txt

`vendor/bashdeps.bash` SHALL NOT appear in `dependencies.txt`.

The bootstrap executable is required to process the manifest, so asking the
manifest to provide that executable would create the circular dependency the
bootstrap boundary exists to avoid.

This exclusion is narrow.  Make directly owns the bootstrap tool only; it SHALL
not become a second general-purpose dependency manager beside bashdeps.

### Use dependencies.txt for ordinary external artifacts

The committed `dependencies.txt` manifest SHALL be the source of truth for
ordinary external artifacts that fit the released bashdeps contract.

For the current repository, the manifest contains exactly one artifact:

```text
vendor/doxygen-bash.awk
```

The filter SHALL use the immutable `bash-doxygen` v0.0.6 tagged raw URL and the
reviewed SHA-256 digest established by the adrctl migration:

```text
url:    https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk
sha256: dc09bccac7cdb69940b2b34f0c2a92d862c5979d578364ec66782ac92338a3ea
```

The manifest SHALL keep each dependency on one physical line while the selected
released bootstrap does not implement the newer ADR-015 continuation syntax.

The manifest is trusted source code.  A change to its URL or digest changes which
bytes the repository authorizes and requires ordinary source review.

### Make target boundaries

The repository SHALL provide these dependency targets:

```text
make deps
make deps-check
```

Their semantics are:

```text
make deps
    May use the network.
    Bootstrap or repair the pinned released bashdeps executable when necessary.
    Verify the bootstrap before executing it.
    Run bashdeps sync against dependencies.txt.
    Converge manifest-managed dependency state.

make deps-check
    Must not use the network.
    Must not repair bootstrap or managed dependency state.
    Verify the existing bootstrap artifact.
    Run bashdeps verify against dependencies.txt.
```

`make build` SHALL NOT invoke `deps`, `deps-check`, the bootstrap recipe, `sync`,
or `verify`.

Unlike repositories whose consumer artifact embeds an external dependency,
bashdeps currently has no manifest-managed build input.  Therefore a clean:

```text
make build
```

SHALL succeed without creating `vendor/bashdeps.bash` or
`vendor/doxygen-bash.awk`.

`make all` SHALL explicitly synchronize dependencies before building:

```text
make all
  -> make deps
  -> make build
```

The ordering SHALL remain correct under parallel Make execution.  A recursive
Make invocation or an equivalent explicit sequencing mechanism is acceptable.

The `all` target is the convenient fresh-checkout development path.  The fact
that the current manifest contains only documentation tooling does not change the
shared target contract.

### Documentation generation

`make docs` SHALL use the manifest-managed:

```text
vendor/doxygen-bash.awk
```

rather than downloading that filter directly.

`make docs` MAY depend on `make deps`, because documentation generation is an
explicit development operation and may require network preparation on a fresh
checkout.

bashdeps publishes ordinary managed artifacts with mode `0644`.  Doxygen needs to
execute the AWK filter, so the documentation target SHALL apply the executable
mode required by its consumer context before invoking Doxygen.  Mode ownership
remains with the consumer target; bashdeps SHALL NOT infer executability from the
artifact name or contents.

### Network policy

Network access is an explicit property of synchronization-oriented targets:

- `make deps` may use the network;
- `make all` may use the network because it explicitly includes `deps`;
- `make docs` may use the network because it explicitly prepares documentation
  dependencies through `deps`;
- `make deps-check` must remain network-free;
- `make build` must remain network-free with respect to dependency management.

Tests that claim a no-network boundary SHALL use controlled local fakes or an
isolated PATH rather than assuming network absence.

### Convergence and preservation

Dependency state is determined by SHA-256 equality, not by filename presence.

For manifest-managed artifacts, `bashdeps sync` SHALL repair missing or stale
bytes to the committed declaration and reuse already-correct bytes without
unnecessary replacement.

For the Make-owned bootstrap, equivalent behavior SHALL be implemented narrowly:
correct cached bytes are reused; missing or mismatched bytes are downloaded to
staging, verified, and then published.

A transfer or digest failure SHALL NOT destroy a previously usable bootstrap or
publish an unverified managed artifact.

### Generated vendor state

The complete `vendor/` directory SHALL remain ignored generated state.

It may contain:

```text
vendor/bashdeps.bash
vendor/doxygen-bash.awk
```

Neither file is maintained repository source.

`make clean` SHALL retain its existing narrow meaning of removing ordinary build
output under `dist/`.

`make distclean` SHALL remove ordinary build output, generated reference output,
and the complete generated `vendor/` dependency state.

### CI boundaries

CI SHALL exercise the architecture rather than relying only on unit tests of the
bashdeps CLI.

Applicable coverage includes:

- a clean `make build` succeeds without creating dependency state;
- `make deps` works from a fresh checkout;
- `make deps-check` verifies synchronized state;
- tampered manifest-managed bytes are rejected by offline verification;
- synchronization restores stale managed bytes;
- failed acquisition or digest verification does not publish unverified bytes;
- `make all` prepares dependencies before building;
- `make docs` uses the manifest-managed filter and leaves generated reference
  output ignored;
- `make distclean` removes generated vendor state; and
- generated bashdeps release artifacts remain executable without `vendor/`,
  `dependencies.txt`, or a bootstrap executable at runtime.

Ordinary behavior tests SHOULD remain deterministic and should not depend on live
public network services.  CI MAY separately exercise the real released bootstrap
and immutable dependency URLs as an integration path.

### Release workflow boundary

The bashdeps release artifacts are generated entirely from maintained source and
do not consume `doxygen-bash.awk`.

Therefore the release build SHALL NOT be made dependent on the documentation-only
manifest artifact merely to imitate repositories whose build outputs genuinely
need external inputs.  The versioning/release workflow MAY continue to build and
test release artifacts without running `make deps` first.

This is an intentional application of the broader rule: release workflows must
prepare and verify dependencies that the release build actually consumes.  At
present, bashdeps consumes none.

A future build dependency would require revisiting this conclusion.

### Runtime isolation

Neither maintained nor generated bashdeps executables SHALL require:

```text
vendor/bashdeps.bash
dependencies.txt
vendor/doxygen-bash.awk
```

at runtime.

The bootstrap and manifest exist only in the source repository's development
workflow.  The released `dist/bashdeps.bash` remains the same self-contained CLI
artifact governed by the runtime and release ADRs.

## Considered Alternatives

### Continue downloading bash-doxygen directly from Make

This keeps the current implementation small, but it preserves project-specific
acquisition logic beside the dependency manager designed to replace that logic.
It also uses a moving `main` URL rather than an immutable tag.  The new design
centralizes ordinary artifact convergence in bashdeps and makes the exact filter
bytes reviewable in `dependencies.txt`.

### Put bashdeps.bash in dependencies.txt

Rejected because the executable is needed before the manifest can be processed.
The bootstrap artifact is the one intentional Make-owned exception.

### Use unreleased src/bashdeps.bash to synchronize dependencies

Rejected because a defect in the source revision under development could prevent
the dependency manager required to prepare that same development environment from
being established.  A previously released and independently verified artifact is
a cleaner bootstrap compiler/tool boundary.

### Commit vendor/bashdeps.bash or doxygen-bash.awk

Rejected as the default because both are reproducible generated dependency state.
Committing them would add duplicated externally produced bytes to repository
history without removing the need for an intentional update and trust process.

### Make build depend on deps

Rejected because the current build needs no external manifest artifact.  Hidden
network access from `make build` would weaken the target boundary for no benefit.

### Make deps-check repair missing state

Rejected because a check target must provide meaningful offline verification.
Repair belongs to `make deps`.

### Make release builds synchronize documentation dependencies

Rejected because the release artifacts do not consume the Doxygen filter.  This
would couple release availability to an unrelated documentation dependency and
would blur the distinction between development tooling and release inputs.

## Consequences

bashdeps now uses its own released contract to manage the kind of ordinary
external artifact it was created to manage.

The repository retains a small amount of direct bootstrap logic, but that logic
is limited to establishing one independently trusted released executable.

The Doxygen filter moves from a moving branch URL and direct Make acquisition to
an immutable tagged declaration with a committed SHA-256 digest.

A fresh `make build` remains independent of dependency preparation, while
`make all` becomes the explicit dependency-synchronizing convenience path shared
with other adopting repositories.

Reference documentation generation may bootstrap and synchronize dependencies on
a fresh checkout.  Runtime and release artifacts remain isolated from that
development tooling.

## Follow-Ups

When a newer bashdeps release is selected as the bootstrap compiler/tool, update
the Makefile version, immutable release URL, and committed digest together after
reviewing the release artifact.

When a newer bash-doxygen release is selected, update the manifest identity,
immutable tagged URL, and digest together.

If future source builds gain additional ordinary external artifacts, evaluate them
for inclusion in `dependencies.txt` rather than adding new direct Make download
recipes.

## Related Decisions

- Related to: ADR-001
- Related to: ADR-003
- Related to: ADR-004
- Related to: ADR-005
- Related to: ADR-006
- Related to: ADR-008
- Related to: ADR-009
- Supersedes `make all` build-only semantics in: ADR-010
- Supersedes direct Doxygen-filter acquisition portions of: ADR-016
