# AGENTS.md

This file provides guidance for AI coding agents working in this repository.

Use this file together with `README.md`.  The README is the human-facing project
overview.  This file is the agent-facing operational map.

## Project Overview

The repository produces two related but independently assembled Bash executables.

`bashdeps.bash` is a small deterministic tool for materializing exact external
artifacts declared by a committed manifest.  A dependency declaration identifies
an artifact, its HTTPS retrieval URL, its repository-relative destination, and its
approved SHA-256 digest.  Byte acceptance is determined by digest equality.

`manifest-manager.bash` is separate maintainer tooling for inspecting validated
manifest identities, appending complete explicit declarations, removing exact
selected records, and deliberately updating existing bashdeps manifest source.
Update may discover GitHub releases, retrieve candidate artifact bytes, and
calculate proposed SHA-256 digests.  Add requires all declaration data explicitly,
while list and remove require neither acquisition nor hashing.  The manager never
participates in `bashdeps.bash` runtime synchronization or verification.

The project deliberately does less than a package manager.  `bashdeps.bash` does
not resolve versions, discover releases, execute install hooks, build dependency
graphs, or infer whether an artifact is executable.  The manifest manager's
read-only `list`, explicit append-only `add`, exact-record `remove`, and surgical
`update` operations do not change that runtime boundary.

Canonical maintained implementation source is:

```text
src/bashdeps.bash
src/manifest-manager.bash
lib/manifest-manager/state.bash
lib/manifest-manager/manifest.bash
lib/manifest-manager/github.bash
lib/manifest-manager/transaction.bash
lib/manifest-manager/update.bash
lib/manifest-manager/list.bash
lib/manifest-manager/add.bash
lib/manifest-manager/remove.bash
```

After build dependencies have been prepared, `make build` generates twelve
release files:

```text
dist/bashdeps.dev.bash
dist/bashdeps.bash
dist/bashdeps.min.bash
dist/bashdeps.dev.bash.sha256
dist/bashdeps.bash.sha256
dist/bashdeps.min.bash.sha256

dist/manifest-manager.dev.bash
dist/manifest-manager.bash
dist/manifest-manager.min.bash
dist/manifest-manager.dev.bash.sha256
dist/manifest-manager.bash.sha256
dist/manifest-manager.min.bash.sha256
```

The supported public interfaces are the executable CLIs.  Neither product exposes
a supported sourceable Bash library API.

## Read the ADRs and Specifications First

The ADR collection is the canonical source of architectural intent.

Before making significant changes, review the relevant files under `doc/adr/`.
Also review `doc/bashdeps-spec.md` whenever a change can affect observable
`bashdeps.bash` behavior and `doc/manifest-manager-spec.md` whenever a change can
affect observable `manifest-manager.bash` behavior.  Source-code documentation
work SHALL follow ADR-014.  Repository self-hosting and development-dependency
work SHALL follow ADR-017.  Build flavor, minification, and release-artifact work
SHALL follow ADR-018.  Checksum companion naming and legacy sidecar compatibility
SHALL follow ADR-019.  Manifest-manager architecture, product isolation, and
surgical update behavior SHALL follow ADR-020.  Manifest-manager `list`, `add`,
and `remove` semantics SHALL follow ADR-021.

Preserve these foundational boundaries:

- manifest declarations are data and are never sourced or evaluated;
- SHA-256 equality is the authority for bytes accepted by `bashdeps.bash`;
- hashes are mandatory even when upstream does not publish checksums;
- `verify` performs no network access and no intentional mutation;
- `sync` preflights all required candidates before intentional publication;
- downloader details remain behind a private adapter;
- `curl` is preferred and usable `wget` is the fallback for `bashdeps.bash`;
- destinations are repository-relative to the invocation's current directory;
- destinations must be strictly beneath `vendor/` by default, with an explicit
  invocation-level `--dest-root` override for another permitted subtree;
- `--dest-root` constrains `dest=` and never prepends or rewrites it;
- symbolic-link path traversal is rejected;
- bashdeps does not own or prune an entire `vendor/` tree;
- ordinary artifact purpose and executability are not inferred;
- the runtime public API is the `bashdeps.bash` CLI, not private Bash helpers;
- `manifest-manager.bash` is a separate maintainer CLI and is never invoked by
  `bashdeps.bash` during materialization or verification;
- manifest-manager changes are proposed source changes, not dynamic runtime trust;
- manifest-manager `update` preserves unrelated manifest bytes exactly and
  publishes only after a complete requested transaction succeeds;
- manifest-manager `add` requires explicit `id`, `url`, `dest`, and `digest`
  fields, infers none of them, and preserves the complete original source as an
  exact prefix before its canonical append;
- manifest-manager `remove` selects one complete opaque identity and omits only
  that logical record's physical source chunk, leaving comments and blank lines
  independent and unchanged;
- mutating `update`, `add`, and `remove` stream modes emit the complete candidate
  on success and the complete captured original on failure after input capture;
- manifest-manager `list` validates the complete manifest before emitting complete
  logical `id` values and never emits rollback source on failure;
- `list`, `add`, and `remove` require no network or SHA-256 capability;
- the two executable families are assembled from explicit source inventories;
- manager-only code and runtime requirements must not leak into `bashdeps.bash`;
- bashdeps-only runtime code must not leak into `manifest-manager.bash`;
- the source repository directly bootstraps only a pinned released
  `vendor/bashdeps.bash` development tool;
- that bootstrap is excluded from `dependencies.txt` and independently verified
  before execution;
- ordinary external development/build artifacts are declared in
  `dependencies.txt`;
- the current manifest contains the documentation-only Bash Doxygen filter and
  the build-time Bash-Minifier input;
- `make build` does not acquire, repair, or verify dependency state;
- `make build` requires an already-prepared `vendor/bash-minifier.bash` and fails
  clearly when it is absent;
- `make deps-check` is network-free and non-repairing; and
- released executables do not require `vendor/` or `dependencies.txt` at runtime.

## Clarify Before Acting

When a request is ambiguous, determine whether two reasonable interpretations
would materially change the public contract or architecture.

If existing ADRs, the specifications, tests, or repository context answer the
question, follow them and continue.

If the ambiguity would materially change public behavior and the repository does
not establish an answer, ask the minimum question necessary.

For ordinary implementation choices that do not affect the public contract,
choose the conventional, conservative solution and continue.

Do not invent architectural rationale when the repository does not establish it.

## Architectural Principles

- Bash 4.3+ is the minimum runtime for both products.
- `src/bashdeps.bash` is the maintained runtime implementation.
- `src/manifest-manager.bash` plus its explicit `lib/manifest-manager/` inventory
  is the maintained manifest-manager implementation.
- `dist/` contains generated release artifacts and is not maintained source.
- The runtime executable name is `bashdeps.bash`.
- The maintainer executable name is `manifest-manager.bash`.
- `bashdeps.bash` operations are `install`, `sync`, `verify`, `help`, and
  `version`.
- The implemented manifest-manager operations are `update`, `add`, `remove`,
  `list`, `help`, and `version`.
- `list` emits complete logical `id` values in manifest order only after complete
  manifest validation.
- `add` accepts exactly one each of `id=`, `url=`, `dest=`, and `digest=`, appends
  one canonical logical record at absolute EOF, and never infers missing data.
- `remove` selects exactly one complete `id` value and deletes only that record's
  physical chunk, including continuation lines and its own terminator.
- `install` and manifest records use the same named field grammar.
- Required fields are `id`, `url`, `dest`, and `digest`.
- Field order is irrelevant.
- A field token is split at the first `=` only.
- Unknown manifest fields fail closed in version 1.
- The digest grammar is `sha256:` followed by exactly 64 lowercase hexadecimal
  characters.
- The recommended identity convention is `PACKAGE@VERSION`; identity remains
  opaque to `bashdeps.bash`, `list`, explicit `add`, and exact `remove`, while
  `update` interprets a narrow GitHub maintenance form.
- `bashdeps.bash` downloader selection is `curl`, then usable `wget`, then failure.
- Manager capabilities are command-specific: `list`, `add`, and `remove` need no
  network or hash tool, while `update` uses curl and SHA-256 capability when
  acquisition or hashing is required; the manager does not require `gh` or JSON
  tooling.
- SHA-256 command selection is `sha256sum`, then `shasum -a 256`, then failure.
- Correct existing bytes require no network request for bashdeps synchronization.
- Candidate bytes are staged and verified before publication.
- Multi-file bashdeps synchronization is not claimed to be globally atomic.
- Manifest-manager `update --all` is transactional at the manifest-source level.
- Newly published dependency files use mode `0644`; verify ignores mode.
- Version 1 does not claim hostile-process locking or race-proof coordination.

## Technology Stack

`bashdeps.bash` runtime:

- Bash 4.3+
- Bash builtins and language features
- `curl` or usable HTTPS-capable `wget` when acquisition is required
- `sha256sum` or `shasum -a 256`
- ordinary Unix-like filesystem utilities used by publication

`manifest-manager.bash` runtime:

- Bash 4.3+
- Bash builtins and language features
- ordinary Unix-like filesystem utilities used for staging and publication
- `curl` for update operations that perform release discovery or acquisition
- `sha256sum` or `shasum -a 256` for update operations that calculate digests

Development:

- Make
- Bats
- ShellCheck
- shfmt
- Doxygen for reference generation
- commit-pinned Bash-Minifier for the minified distribution flavor
- GitHub Actions

## Development Dependency Management

ADR-017 defines the source repository's deliberate self-hosting boundary.  ADR-018
adds Bash-Minifier as a real build input while preserving that dependency model.

Make directly owns only:

```text
vendor/bashdeps.bash
```

That file is a previously released bashdeps artifact pinned by exact version,
immutable release URL, and committed SHA-256 digest.  Existing bytes may be reused
only when they match the committed digest.  Missing or mismatched bytes are
replaced only after a staged candidate verifies successfully.

Do not put `vendor/bashdeps.bash` in `dependencies.txt`; the bootstrap executable
must exist before the manifest can be processed.

The committed `dependencies.txt` file owns ordinary external development/build
artifacts.  At present it declares:

```text
vendor/doxygen-bash.awk
vendor/bash-minifier.bash
```

The Doxygen filter uses the immutable bash-doxygen v0.0.6 tag and committed
digest.  Bash-Minifier uses exact upstream commit
`9c824e20815a5bca2153ec25ecc02a4edea1430e` and is materialized from upstream
`Minify.sh` at the local path `vendor/bash-minifier.bash`.

The selected released bootstrap predates ADR-015 manifest folding, so keep
repository manifest records on one physical line until the bootstrap pin
intentionally moves to a compatible release.

Target boundaries are explicit:

```text
make deps        bootstrap/verify released bashdeps, then sync dependencies.txt
make deps-check  verify existing bootstrap and manifest state without repair
make build       consume prepared build inputs; do not acquire or verify them
make all         deps, then build both executable families
make docs        prepare deps, then generate reference documentation
```

`make deps` and therefore `make all`/`make docs` may use the network.
`make deps-check` must not use the network.  `make build` must not invoke
dependency preparation or verification and must not repair missing dependency
state.  It requires readable `vendor/bash-minifier.bash`; a fresh checkout should
use `make all` or run `make deps` before `make build`.

The complete `vendor/` tree is generated state.  `make distclean` removes it.

Manifest-managed tools normally arrive as ordinary mode `0644` data.  The Doxygen
consumer applies executable mode to its AWK filter.  The build invokes
`vendor/bash-minifier.bash` through `bash`, so the minifier does not need a mode
exception.  Do not add purpose or executable-mode inference to bashdeps for either
consumer.

## Coding Guidelines

Prefer small, readable Bash functions with one explicit responsibility.

Manifest data is never executable input.  Do not use `eval` or `source` to parse
manifest records or CLI field values.

Do not construct shell command strings from URLs, destinations, identities, or
digests.  Pass values as quoted argv elements.

Quote expansions deliberately.

Keep downloader-specific argv and capability behavior inside downloader adapter
functions.  Synchronization or update logic should reason about acquisition
outcomes, not duplicate curl/wget mechanics throughout the program.

Keep SHA-256 command differences behind private hashing helpers.

Private bashdeps helpers and metadata variables use the `__bashdeps_` namespace.
Private manager helpers and metadata variables use the `__manifest_manager_`
namespace.  Do not create public Bash functions without an architectural decision.

Do not infer executable mode from filenames, shebangs, URLs, identities, or file
contents.

Do not normalize or repair a manifest silently.  Invalid declarations fail.  The
manager may parse a logical view for validation and selection, but it must not
serialize that parsed representation back over existing source.  `update` uses
surgical literal substitutions against retained raw bytes.  `add` preserves the
complete original as an exact prefix and serializes only its new canonical record.
`remove` rebuilds the candidate from exact source chunks while omitting only the
selected record chunk.  Each mutation keeps the operation-specific preservation
proof required by ADR-020 and ADR-021.

Avoid additional external runtime dependencies when Bash builtins or already
accepted platform utilities implement the behavior clearly and safely.

## Build and Release Boundaries

Treat maintained files under `src/` and the explicit manager files under
`lib/manifest-manager/` as source of truth.  Do not edit generated files under
`dist/` directly.

ADR-018 defines the three-flavor release representation, ADR-019 defines checksum
companion naming, and ADR-020 extends that model to the second executable family.
ADR-021 adds manager commands without changing the twelve-file product/release
surface.

The build defines explicit source inventories for the two products.  Never replace
those inventories with a wildcard that incorporates every library in the
repository.  A component belongs in both products only after a deliberate decision
that it is genuinely shared runtime code.

For each product, the developer artifact is assembled first and retains
source/documentation comments together with generated release metadata.  The
ordinary artifact is derived from the completed developer artifact by removing
full-line comments after the shebang.  The minified artifact is derived from the
completed comment-stripped artifact through the commit-pinned
`vendor/bash-minifier.bash` build dependency.  Do not minify individual source or
library fragments separately.

Each executable family contains:

```text
<product>.dev.bash
<product>.bash
<product>.min.bash
<product>.dev.bash.sha256
<product>.bash.sha256
<product>.min.bash.sha256
```

All six generated Bash artifacts retain a valid shebang, executable mode, the
correct product CLI contract, and shared project version/build/commit metadata.
Each `.sha256` file contains the SHA-256 digest and matching artifact filename in
conventional checksum-tool syntax.  The project does not generate an aggregate
`SHA256SUMS` file.

New releases publish only `.sha256` companions.  Historical `.256` companions
remain valid for the releases that contain them.  Code that explicitly retrieves
release checksum sidecars may fall back from `.sha256` to `.256` only when the
preferred asset is confirmed absent; transport, authorization, server,
malformed-content, and checksum-verification failures remain failures.  This
compatibility convention does not alter bashdeps' committed-digest trust model:
runtime synchronization and bootstrap integrations continue to treat the
committed expected digest as authoritative rather than dynamically trusting a
remote sidecar.

Tests must cover maintained source and all three generated representations for
each product.  Minifier success is not proof of semantic equivalence; every
minified artifact must pass syntax, Bash 4.3, checksum, and public behavior
validation.

`make build` is network-free and non-repairing.  It must not bootstrap bashdeps,
synchronize `dependencies.txt`, run `deps-check`, or otherwise acquire/verify
vendor state.  It must fail clearly before publishing build output when the
required Bash-Minifier input is absent.

The build must reject product-closure contamination: unmistakable
`__manifest_manager_` runtime symbols may not appear in the bashdeps developer
artifact, and unmistakable `__bashdeps_` runtime symbols may not appear in the
manifest-manager developer artifact.

The versioning/release workflow must prepare and verify dependencies before
running the release build, then publish all twelve release files.  Released
executables must continue to run without the vendor tree or manifest.

## Scope Discipline

Unless explicitly requested otherwise, produce the smallest correct change that
satisfies the documented behavior.

Do not expand `bashdeps.bash` into a package manager.  Do not use the existence of
`manifest-manager.bash` as permission to introduce general package-manager
semantics there either.

Features such as semantic-version resolution, registries, transitive dependency
resolution, recursive manifests, install hooks, authenticated artifact retrieval,
arbitrary plugins, or package-manager integration remain outside the established
scope unless a later ADR changes that boundary.  ADR-021 defines the implemented
`list`, `add`, and `remove` source-maintenance contracts.  `show` remains outside
the accepted command set unless a concrete need produces a separate decision.

A future manifest field such as `mode=0775` is architecturally possible because
the named-field grammar is extensible, but unknown fields intentionally fail in
version 1.  Do not implement speculative fields before their behavior is defined.

Do not perform unrelated refactoring, formatting, renaming, or documentation
changes in a focused patch.

If additional improvement opportunities are discovered, record them separately
rather than silently broadening the change.

## Documentation Standards

Follow the documentation-driven, test-second philosophy established by the ADRs.
Source-code documentation SHALL follow ADR-014 and the repository standard in
`doc/documentation-standard.md` when that standard applies to the maintained
source being changed.

The revised `doc/documentation-standard.md` applies to new manifest-manager source.
Existing maintained scripts are not reformatted or backported to the revised
standard as part of issue #17; that backport is a separate future change.

Maintained Bash source uses narrative-heavy Doxygen-style comments.  Every Doxygen
line begins with `##` at column 1.  Maintained Bash files require a file-level
`@file` block, every function requires an `@fn` block, and global/configuration
variables require `@var` documentation when applicable.  Follow the repository
standard for required STDIN, STDOUT, STDERR, `@returns`, `@retval`, and example
sections.

Documentation should explain intent, assumptions, constraints, invariants, safety
posture, failure modes, observable behavior, and non-goals where appropriate.  It
should help a maintainer understand why a construct exists without
reverse-engineering its control flow under pressure.  Comments that merely restate
syntax are not a substitute for that narrative.

Private helpers remain implementation details despite being documented for
maintainers.  Doxygen visibility does not create a supported sourceable API.

Documentation-only source work is strictly comment-only.  Do not change function
bodies, variable assignments, control flow, command invocations, shell options,
traps, or executable ordering while adding or correcting documentation.  Compare
non-comment lines before and after such a change whenever practical.

Do not invent rationale to make an implementation appear intentional.  When
purpose, usage, constraints, or rationale cannot be established confidently from
the source and governing documentation, add a specific neutral `## @TODO` in the
relevant documentation block and preserve the executable code.

`doc/bashdeps-spec.md` and `doc/manifest-manager-spec.md` are the normative
public-behavior references for their respective products.  ADRs preserve why
decisions were made.

When implementation and documentation disagree, do not silently choose whichever
is convenient.  Determine whether the implementation is wrong or the documented
decision has genuinely changed.

## Testing

Bats is the primary public behavior framework.

Ordinary tests must not depend on live public network services.

Use temporary project roots and controlled fixture bytes.  Exercise downloader
selection, GitHub latest-release discovery, acquisition, and failure through
PATH-controlled fake commands where practical.

Run the bashdeps public behavior suite against:

- `src/bashdeps.bash`;
- `dist/bashdeps.dev.bash`;
- `dist/bashdeps.bash`;
- `dist/bashdeps.min.bash`.

Run the manifest-manager public behavior suite against:

- `src/manifest-manager.bash`;
- `dist/manifest-manager.dev.bash`;
- `dist/manifest-manager.bash`;
- `dist/manifest-manager.min.bash`.

Generated artifacts are products and must not be assumed correct because source
or another generated flavor passed.

Repository orchestration tests run separately from the public-artifact behavior
passes.  They should exercise Make/bootstrap/dependency/build boundaries with
controlled fake bootstrap/download/minifier inputs so ordinary tests remain
deterministic.  CI may additionally exercise the real pinned released bootstrap
and immutable manifest URLs.

Every functional change should prompt these questions:

- What public behavior changed?
- Which ADR or specification section governs it?
- How can the behavior be verified deterministically?
- Does it affect manifest parsing, byte identity, network boundaries, filesystem
  safety, output channels, or exit statuses?
- Does the same test pass against every shipped representation of the affected
  product?
- Does the change alter either executable's explicit source or runtime dependency
  closure?

Bug fixes should add or update a regression test that would have failed before
the fix.

## Validation

When practical:

- review the resulting diff;
- run Bash syntax validation on maintained source and executable test helpers;
- run both Bats behavior suites against source and all generated artifacts;
- run the Make/bootstrap/dependency-boundary regression tests;
- run ShellCheck on maintained product source, not on Bats test files;
- run shfmt checks on maintained source and executable test helpers;
- verify a clean `make build` fails without acquiring or creating dependency
  state when Bash-Minifier is absent;
- synchronize real development/build dependencies with `make deps` when
  integration validation is appropriate;
- verify synchronized state offline with `make deps-check`;
- verify `make all` sequences dependency preparation before build;
- verify `make docs` documents both maintained executable source closures through
  the manifest-managed Doxygen filter;
- verify generated artifact metadata and executable modes;
- verify all six `.sha256` companions against final generated bytes;
- verify ordinary comment-stripped artifacts contain no full-line comments after
  their shebangs;
- verify product-specific private namespaces do not leak into the other developer
  artifact;
- confirm `verify` tests do not accidentally reach the network;
- confirm `list` behavior is identical across all manager representations and
  remains network/hash independent;
- confirm `add` preserves exact original bytes before its append, uses only
  explicit declaration data, and remains network/hash independent across all
  manager representations;
- confirm `remove` deletes exactly one selected record chunk, preserves comments,
  blank lines, and remaining bytes, and remains network/hash independent across
  all manager representations;
- confirm all generated release artifacts run without the vendor tree or manifest;
- confirm comment removal and minification do not alter observable behavior; and
- for documentation-only Bash changes, confirm non-comment lines are unchanged.

Report only validation that actually ran.

## Common Failure Modes

Avoid:

- treating filename presence as proof of dependency identity;
- making hashes optional because upstream does not publish one;
- parsing a field token at every `=` instead of the first `=` only;
- using `eval`, `source`, or shell command strings for manifest data;
- accepting unknown fields silently;
- making `verify` repair or download anything;
- publishing one sync candidate before all required candidates pass preflight;
- downloading directly over an existing destination;
- following destination symlinks;
- pruning undeclared files from `vendor/` or another directory;
- assuming curl is always installed for `bashdeps.bash`;
- treating every wget implementation as feature-identical;
- treating downloader success as proof of artifact identity;
- changing file mode on an already-correct destination during verify or sync;
- exposing private helper functions as though they were a supported API;
- editing generated distribution artifacts;
- changing executable code during a documentation-only source update;
- inventing source-code rationale instead of marking genuine ambiguity with
  `@TODO`;
- claiming multi-file bashdeps transactionality or hostile-process concurrency
  guarantees that version 1 does not provide;
- putting `vendor/bashdeps.bash` in the manifest it is required to process;
- using unreleased `src/bashdeps.bash` as the repository bootstrap tool;
- reintroducing direct Make acquisition for manifest-managed development/build
  artifacts;
- using moving `main`/`master` URLs when an immutable release, tag, or commit can
  be used;
- making `make build` implicitly synchronize, verify, or repair dependencies;
- making `make deps-check` bootstrap, download, or repair state;
- minifying source/library fragments before complete program assembly;
- treating Bash-Minifier exit success as proof of semantic equivalence;
- changing `bashdeps.bash` to mean the minified flavor;
- reserializing existing manifest source as part of a manager mutation;
- inferring an add URL, artifact name, destination, package convention, or digest
  from a partial declaration;
- interpreting a remove identity as a package prefix or stripping version text
  before exact selection;
- deleting comments or blank lines merely because they are adjacent to a removed
  dependency record;
- interpreting `list` identities as package coordinates or emitting a partial list
  before complete manifest validation;
- applying mutating stream rollback output semantics to read-only `list`;
- emitting partial manager output after a mutating transaction has failed;
- silently skipping unsupported dependencies under `manifest-manager update --all`;
- importing manager-only libraries into `bashdeps.bash` or bashdeps-only runtime
  code into `manifest-manager.bash`; or
- coupling released executables to Bash-Minifier, the bootstrap, the manifest, or
  the vendor tree at runtime.

## Final Principle

`bashdeps.bash` knows how to materialize exact approved bytes at declared local
paths and almost nothing about what those bytes mean.

`manifest-manager.bash` helps a maintainer inspect and prepare deliberate changes
to those approved declarations without becoming part of runtime trust or
materialization.

The repository may build and release both tools together, but each executable
retains its own responsibility, source closure, and runtime requirements.

Every change should preserve that clarity.
