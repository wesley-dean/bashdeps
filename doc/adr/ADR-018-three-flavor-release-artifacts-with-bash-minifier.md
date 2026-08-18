# ADR-018: Three-Flavor Release Artifacts with Bash-Minifier

Date: 2026-08-18

## Status

Proposed

## Intent and Scope

This Architecture Decision Record defines the bashdeps release-artifact pipeline
for developer, ordinary, and minified Bash distributions and defines
Bash-Minifier as a manifest-managed build dependency.

This decision changes the earlier release contract deliberately.  ADR-009 remains
the historical record of the decision to publish only developer and
comment-stripped artifacts and to exclude minification.  This ADR supersedes those
specific portions of ADR-009.

ADR-017 remains the historical record of the repository's self-hosting dependency
architecture.  This ADR supersedes only the portions of ADR-017 that state that
`make build` has no manifest-managed build input, that a clean `make build` must
succeed without `vendor/`, and that release generation requires no prepared
manifest dependencies.

The runtime CLI contract is unchanged.  The three generated Bash files are
alternate representations of the same `bashdeps.bash` program.

## Context

The repository previously generated two executable release forms:

```text
dist/bashdeps.dev.bash
dist/bashdeps.bash
```

The developer artifact retained source comments.  The ordinary artifact removed
full-line source comments while preserving executable lines.  Each file had one
matching `.256` checksum companion.

A third release flavor is now desired for consumers who prefer a substantially
smaller standalone Bash artifact.  Love Borgstrom's Bash-Minifier provides a
state-aware Bash source transformation that can read Bash from standard input or
a file and emit minified Bash.  The repository will use one reviewed,
commit-pinned copy of that tool rather than a moving branch.

The minifier is a build-time transformation tool.  It is not a runtime dependency
of bashdeps and must not be embedded as a required external component of the
released CLI.

The repository already has a dependency-management boundary established by
ADR-017:

```text
Make
  -> bootstrap released vendor/bashdeps.bash
  -> released bashdeps sync dependencies.txt
       -> ordinary external development/build artifacts
```

Bash-Minifier fits that manifest-managed dependency model and therefore does not
justify additional direct download logic in Make.

## Decision Drivers

- Publish a readable developer artifact, an ordinary comment-stripped artifact,
  and a smaller minified artifact from one maintained source tree.
- Preserve `dist/bashdeps.bash` as the ordinary/default consumer filename.
- Apply stripping and minification to the complete assembled program rather than
  independently transforming source fragments.
- Keep imported or concatenated libraries inside the same transformation boundary
  if the build later gains such inputs.
- Keep every shipped Bash artifact independently executable and behavior-tested.
- Give every Bash artifact one directly associated SHA-256 companion.
- Keep `make build` network-free and non-repairing.
- Keep dependency acquisition and convergence owned by `make deps`.
- Use an immutable, reviewed Bash-Minifier commit and committed digest.
- Keep release artifacts independent of `vendor/` and `dependencies.txt` at
  runtime.
- Preserve generated-state and staged-publication discipline.

## Decision

### Publish three executable Bash flavors

`make build` SHALL generate exactly these Bash artifacts:

```text
dist/bashdeps.dev.bash
dist/bashdeps.bash
dist/bashdeps.min.bash
```

Their roles are:

```text
bashdeps.dev.bash  complete assembled Bash with explanatory/source comments
bashdeps.bash      complete assembled Bash with full-line comments removed
bashdeps.min.bash  comment-stripped Bash after Bash-Minifier transformation
```

`dist/bashdeps.bash` remains the ordinary/default release filename for existing
consumers and bootstrap examples.

All three artifacts SHALL retain a valid Bash shebang and executable mode.  The
build currently publishes each as mode `0755`.

### Generate one checksum companion per artifact

`make build` SHALL generate:

```text
dist/bashdeps.dev.bash.256
dist/bashdeps.bash.256
dist/bashdeps.min.bash.256
```

Each checksum file SHALL contain the SHA-256 digest and matching artifact basename
in conventional checksum-tool syntax.

The repository SHALL continue not to generate an aggregate `SHA256SUMS` file.

Release automation SHALL publish all six files together.

### Transform only after complete program assembly

The build SHALL construct `dist/bashdeps.dev.bash` first as the complete generated
program, including generated metadata and every source/library component that the
build incorporates.

The ordinary artifact SHALL then be derived from that complete developer artifact
by removing full-line comments while retaining the shebang.  This makes comment
stripping apply uniformly to project source, generated explanatory comments, and
any incorporated libraries rather than only to one maintained source file.

The minified artifact SHALL be derived from the completed comment-stripped
`dist/bashdeps.bash` artifact.  Bash-Minifier SHALL therefore see the same complete
program consumers receive in the ordinary flavor.

The build SHALL NOT minify individual source/library fragments before assembly.
Doing so would make the transformation boundary dependent on project layout and
could produce different semantics from minifying the completed program.

### Manage Bash-Minifier through dependencies.txt

The repository SHALL declare Bash-Minifier in committed `dependencies.txt` and
materialize it at:

```text
vendor/bash-minifier.bash
```

The initial reviewed upstream identity is:

```text
repository: Zuzzuc/Bash-minifier
commit:     9c824e20815a5bca2153ec25ecc02a4edea1430e
upstream:   Minify.sh
local:      vendor/bash-minifier.bash
sha256:     93cb422360db4cc410d19b068eb074da020a4a743f0eebc9c442d1e5acd90e9b
```

The manifest URL SHALL be commit-pinned rather than branch-pinned.

The dependency remains ordinary bashdeps-managed data.  bashdeps SHALL not infer
or assign executable mode merely because the file is a Bash script.  The build
SHALL invoke the tool explicitly through `bash`, so the vendor file can retain the
normal mode established by bashdeps.

The Make-owned bootstrap `vendor/bashdeps.bash` remains outside the manifest as
defined by ADR-017.

### Keep build network-free

`make build` SHALL NOT invoke:

```text
make deps
make deps-check
bashdeps sync
bashdeps verify
```

and SHALL NOT download or repair Bash-Minifier.

The build SHALL require an already-prepared readable
`vendor/bash-minifier.bash`.  If it is absent, `make build` SHALL fail clearly
without attempting network access or creating dependency state.

A fresh checkout that needs release artifacts SHALL therefore use:

```text
make all
```

or equivalently prepare dependencies before building:

```text
make deps
make build
```

`make all` continues to sequence dependency preparation before build and remains
the fresh-checkout convenience target.

### Preserve dependency verification ownership

`make deps` remains the operation that may use the network and converge manifest
state.

`make deps-check` remains network-free and non-repairing and verifies both the
released bashdeps bootstrap and manifest-managed dependency bytes.

`make build` consumes prepared build inputs without independently reimplementing
manifest digest policy.  This preserves the separation between dependency-state
management and build execution.

### Invoke Bash-Minifier deterministically

The build SHALL run the pinned minifier in force/non-interactive mode and supply
the completed comment-stripped artifact as input.  Output SHALL be written to a
temporary minified path, validated by the existing artifact test surfaces, given
the expected executable mode, and then published at the final artifact path.

A failed minifier invocation SHALL cause the build to fail rather than publishing
a newly generated minified final artifact.

The minifier is an external transformation tool and is therefore not assumed to
be semantics-preserving merely because it exits successfully.  Behavioral tests
are the acceptance mechanism for the generated result.

### Test all shipped representations

The public behavior suite SHALL run against:

1. `src/bashdeps.bash`;
2. `dist/bashdeps.dev.bash`;
3. `dist/bashdeps.bash`;
4. `dist/bashdeps.min.bash`.

Generated-artifact validation SHALL verify, as applicable:

- Bash syntax;
- executable mode;
- valid shebang;
- public CLI behavior;
- Bash 4.3 compatibility;
- matching `.256` checksum content; and
- release/runtime independence from the vendor tree and manifest after build.

The ordinary comment-stripped artifact SHALL also be checked for unintended
remaining full-line comments after the shebang.

Repository orchestration tests SHALL establish that:

- a clean `make build` fails when Bash-Minifier has not been prepared;
- that failure does not acquire or create dependency state;
- `make deps` prepares Bash-Minifier and other manifest dependencies;
- stale Bash-Minifier bytes converge to the manifest declaration;
- `make deps-check` detects tampered Bash-Minifier bytes without repair;
- `make all` prepares dependencies before generating all three Bash flavors; and
- completed release artifacts continue to run after `vendor/` and
  `dependencies.txt` are removed.

### Update CI and release preparation

CI SHALL prepare dependencies before any validation path that executes generated
artifact builds.

CI SHALL retain an explicit negative check that a fresh `make build` without
prepared Bash-Minifier fails and does not create dependency state.

Release automation SHALL run dependency preparation and offline dependency
verification before building release artifacts.  The release build itself remains
network-free.

GitHub releases SHALL include all six generated files defined by this ADR.

### Preserve runtime isolation

None of the three released Bash artifacts SHALL require:

```text
vendor/bash-minifier.bash
vendor/bashdeps.bash
vendor/doxygen-bash.awk
dependencies.txt
```

at runtime.

Bash-Minifier is solely a source-repository build dependency.

## Considered Alternatives

### Continue publishing only developer and ordinary artifacts

This preserves the previous release surface but does not provide the requested
compact distribution flavor.

### Minify maintained source directly

Rejected because it would create a different transformation boundary from the
ordinary artifact and could omit generated metadata or incorporated libraries.
The minified form is derived from the complete comment-stripped artifact instead.

### Minify each source or library separately before concatenation

Rejected because minification semantics can depend on statement boundaries across
the final assembled program.  The complete program is the correct transformation
unit.

### Download Bash-Minifier directly from Make

Rejected because ADR-017 already centralizes ordinary external build/development
artifacts in `dependencies.txt`.  Direct Make acquisition would duplicate policy
and weaken the reviewable manifest boundary.

### Use the Bash-Minifier master branch

Rejected because a moving branch does not identify immutable reviewed bytes.  The
manifest pins an exact commit and digest.

### Make build invoke make deps automatically

Rejected because network access and dependency repair must remain explicit.
`make all` is the fresh-checkout convenience path; `make build` consumes local
prepared inputs only.

### Verify Bash-Minifier digest again inside make build

Rejected because digest verification and state convergence belong to
`make deps`/`make deps-check`.  Reimplementing that policy in the build recipe
would duplicate dependency-management logic back into Make.

### Make bash-minifier executable in the manifest

Rejected because bashdeps intentionally does not infer or manage artifact purpose
or executability.  Invoking the managed file with `bash` keeps mode policy out of
the dependency manager.

### Replace bashdeps.bash with the minified artifact as the default filename

Rejected because `bashdeps.bash` is the established ordinary consumer and
bootstrap filename.  The minified artifact is additive and explicitly named
`bashdeps.min.bash`.

## Consequences

The build now has one required manifest-managed input, so a clean `make build`
without prepared dependencies no longer succeeds.

`make all` becomes the expected one-command build from a fresh checkout, while
`make build` remains useful and deterministic after dependency preparation.

Release validation grows from three execution surfaces to four: maintained source
plus three generated distributions.

Bash-Minifier becomes part of the reviewed build supply chain.  Its commit and
SHA-256 digest are committed alongside other ordinary external artifacts.

The minified output is trusted only after the same syntax, compatibility, and
public-behavior checks used for other generated artifacts pass.

The ordinary `bashdeps.bash` filename and runtime contract remain stable.

## Follow-Ups

A future Bash-Minifier update SHALL change its manifest identity, commit-pinned
URL, and digest together after review of the new bytes and successful generated
artifact validation.

If the source build later incorporates external Bash libraries, keep the complete
assembly-first transformation order defined here unless a future ADR establishes a
stronger reason to change it.

## Related Decisions

- Related to: ADR-001
- Related to: ADR-005
- Related to: ADR-008
- Supersedes minification and two-artifact portions of: ADR-009
- Supersedes three-surface generated-artifact testing portions of: ADR-010
- Related to: ADR-014
- Supersedes build-input and release-dependency portions of: ADR-017
