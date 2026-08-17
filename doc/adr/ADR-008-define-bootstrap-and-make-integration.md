# ADR-008: Define Bootstrap and Make Integration

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines how consuming projects obtain `bashdeps.bash` itself and how Make
targets should separate dependency convergence, verification, and ordinary build
work.

## Context

A dependency tool cannot use itself to obtain the first copy of itself.  Every
consumer therefore retains one intentionally small bootstrap path for the pinned
`bashdeps.bash` release artifact.

The project does not attempt to hide this bootstrap paradox.  Its value is that a
small, repeated bootstrap recipe can replace many project-specific dependency
recipes after `bashdeps.bash` is available.

The Make boundary also matters.  A target advertised as offline verification must
not silently download the tool required to perform that verification, and an
ordinary build should not unexpectedly repair or fetch dependencies.

## Decision Drivers

- Keep the bootstrap path small, explicit, pinned, and independently verifiable.
- Keep `bashdeps.bash` itself outside dependency destinations managed by the
  consumer manifest.
- Preserve a genuinely network-free and mutation-free dependency check.
- Avoid implicit dependency synchronization from ordinary builds.
- Make dependency acquisition an explicit developer/CI action.
- Keep the integration easy to copy among Bash projects.

## Decision

A consuming project SHOULD place its bootstrapped `bashdeps.bash` artifact outside
the paths managed by `dependencies.txt`.

The recommended location is:

```text
.build/bashdeps.bash
```

The exact bootstrap directory is a consumer convention rather than a requirement
of the `bashdeps.bash` CLI.

The consumer Makefile SHALL pin the bootstrap artifact by immutable release URL
and committed SHA-256 digest.  The release publishes `bashdeps.bash.256` as a
checksum companion for review and verification, but the consuming project SHALL
retain its expected digest as committed trust data rather than dynamically trust a
remote checksum file on every bootstrap.

The bootstrap recipe SHALL:

1. accept an existing bootstrap artifact only when its SHA-256 digest matches;
2. otherwise download a replacement candidate to a temporary path;
3. verify the candidate digest before publication;
4. publish the verified candidate at the bootstrap path;
5. never update the expected digest automatically.

The bootstrap recipe MAY use the same downloader and SHA-256 capability-selection
strategy documented by bashdeps, but it remains intentionally small and local to
the consumer because `bashdeps.bash` is not yet available to implement that first
step.

### Make target contract

The recommended consumer contract SHALL be:

```text
make deps        bootstrap bashdeps.bash if necessary, then bashdeps.bash sync
make deps-check  run bashdeps.bash verify using an already-present bootstrap artifact
make build       build only from current local inputs
make all         deps, then build
```

`make deps` MAY access the network and MAY mutate declared dependency destinations.

`make deps-check` SHALL NOT bootstrap a missing `bashdeps.bash` artifact.  If the
pinned bootstrap artifact is absent or invalid, the target SHALL fail rather than
silently access the network or repair it.  When the bootstrap artifact is valid,
`deps-check` SHALL invoke `bashdeps.bash verify` and therefore remain network-free
and non-mutating with respect to managed dependencies.

`make build` SHALL NOT implicitly invoke `bashdeps.bash sync`, `bashdeps.bash
verify`, or the bootstrap recipe.  A build may fail because required inputs are
absent; that failure is preferable to an ordinary build unexpectedly changing
repository state or requiring network access.

`make all` MAY compose `deps` followed by `build` for callers that explicitly want
convergence before building.

Consumers MAY use different target names, but documentation for bashdeps SHOULD
present this contract as the recommended integration because its boundaries map
directly to the CLI semantics.

### Bootstrap artifact identity

The bootstrap artifact SHALL be treated like any other externally acquired
artifact: filename presence is insufficient.  Consumers SHALL verify its pinned
SHA-256 digest before trusting it.

A bootstrap recipe SHOULD avoid downloading when the existing bytes already match
the pinned digest.

## Considered Alternatives

### Put bashdeps.bash in dependencies.txt

This creates a circular dependency: `bashdeps.bash` would be required to
materialize the manifest entry that provides `bashdeps.bash`.  The bootstrap
artifact therefore remains outside the managed manifest.

### Let deps-check bootstrap automatically

This is convenient on a fresh checkout but violates the promised no-network and
no-mutation character of a check operation.  Explicit `make deps` is the repair
path.

### Make build depend on deps

This makes first use convenient but couples compilation/generation to network and
mutation.  The project intentionally keeps ordinary build behavior separate from
dependency convergence.

### Vendor bashdeps.bash permanently in every consumer repository

Committing the tool avoids bootstrap network access but creates generated/vendor
copies whose update discipline can drift.  Consumers remain free to choose that
policy, but it is not the recommended integration.

## Consequences

A fresh checkout normally runs `make deps` before `make build` or uses `make all`.

Offline verification is meaningful only after the pinned bootstrap artifact is
already available locally.

Consumers retain a small amount of duplicated bootstrap logic, but the larger and
more security-sensitive dependency-set behavior is centralized in bashdeps.

The bootstrap recipe itself should be tested by consumers that rely on it because
it remains outside bashdeps' runtime control.

## Open Questions and Follow-Ups

A future release may provide a documented bootstrap snippet or generated Make
include to reduce consumer duplication, but such a feature must not obscure the
independent trust required for the first `bashdeps.bash` artifact.

## Related Decisions

- Related to: ADR-001
- Related to: ADR-003
- Related to: ADR-004
- Related to: ADR-006
- Related to: ADR-007
- Related to: ADR-009
