# AGENTS.md

This file provides guidance for AI coding agents working in this repository.

Use this file together with `README.md`.  The README is the human-facing project
overview.  This file is the agent-facing operational map.

## Project Overview

`bashdeps` is a small deterministic Bash tool for materializing exact external
artifacts declared by a committed manifest.  The distributed executable is named
`bashdeps.bash`.

A dependency declaration identifies an artifact, its HTTPS retrieval URL, its
repository-relative destination, and its approved SHA-256 digest.  Byte acceptance
is determined by digest equality.

The project deliberately does less than a package manager.  It does not resolve
versions, discover releases, execute install hooks, build dependency graphs, or
infer whether an artifact is executable.

The canonical maintained implementation is `src/bashdeps.bash`.

`make build` generates:

```text
dist/bashdeps.dev.bash
dist/bashdeps.dev.bash.256
dist/bashdeps.bash
dist/bashdeps.bash.256
```

The supported public interface is the `bashdeps.bash` executable CLI.  There is no
supported sourceable library API in version 1.

## Read the ADRs and Specification First

The ADR collection is the canonical source of architectural intent.

Before making significant changes, review the relevant files under `doc/adr/`.
Also review `doc/bashdeps-spec.md` whenever a change can affect observable public
behavior.  Source-code documentation work SHALL follow ADR-014.  Repository
self-hosting and development-dependency work SHALL follow ADR-017.

Preserve these foundational boundaries:

- manifest declarations are data and are never sourced or evaluated;
- SHA-256 equality is the authority for acceptable bytes;
- hashes are mandatory even when upstream does not publish checksums;
- `verify` performs no network access and no intentional mutation;
- `sync` preflights all required candidates before intentional publication;
- downloader details remain behind a private adapter;
- `curl` is preferred and usable `wget` is the fallback;
- destinations are repository-relative to the invocation's current directory;
- destinations must be strictly beneath `vendor/` by default, with an explicit
  invocation-level `--dest-root` override for another permitted subtree;
- `--dest-root` constrains `dest=` and never prepends or rewrites it;
- symbolic-link path traversal is rejected;
- bashdeps does not own or prune an entire `vendor/` tree;
- ordinary artifact purpose and executability are not inferred;
- the public API is the `bashdeps.bash` CLI, not private Bash helpers;
- the source repository directly bootstraps only a pinned released
  `vendor/bashdeps.bash` development tool;
- that bootstrap is excluded from `dependencies.txt` and independently verified
  before execution;
- ordinary external development artifacts are declared in `dependencies.txt`;
- the current manifest contains only the documentation-only Bash Doxygen filter;
- `make build` does not acquire, verify, or require development dependency state;
- `make deps-check` is network-free and non-repairing; and
- released bashdeps artifacts do not require `vendor/` or `dependencies.txt` at
  runtime.

## Clarify Before Acting

When a request is ambiguous, determine whether two reasonable interpretations
would materially change the public contract or architecture.

If existing ADRs, the specification, tests, or repository context answer the
question, follow them and continue.

If the ambiguity would materially change public behavior and the repository does
not establish an answer, ask the minimum question necessary.

For ordinary implementation choices that do not affect the public contract,
choose the conventional, conservative solution and continue.

Do not invent architectural rationale when the repository does not establish it.

## Architectural Principles

- Bash 4.3+ is the minimum runtime.
- `src/bashdeps.bash` is the maintained implementation.
- `dist/` contains generated release artifacts and is not maintained source.
- The public executable name is `bashdeps.bash`.
- The CLI operations are `install`, `sync`, `verify`, `help`, and `version`.
- `install` and manifest records use the same named field grammar.
- Required fields are `id`, `url`, `dest`, and `digest`.
- Field order is irrelevant.
- A field token is split at the first `=` only.
- Unknown manifest fields fail closed in version 1.
- The digest grammar is `sha256:` followed by exactly 64 lowercase hexadecimal
  characters.
- The recommended identity convention is `PACKAGE@VERSION`; identity remains
  opaque to bashdeps.
- Downloader selection is `curl`, then usable `wget`, then failure.
- SHA-256 command selection is `sha256sum`, then `shasum -a 256`, then failure.
- Correct existing bytes require no network request.
- Candidate bytes are staged and verified before publication.
- Multi-file synchronization is not claimed to be globally atomic.
- Newly published files use mode `0644`; verify ignores mode.
- Version 1 does not implement locking or concurrent mutation coordination.

## Technology Stack

Runtime:

- Bash 4.3+
- Bash builtins and language features
- `curl` or usable HTTPS-capable `wget` when acquisition is required
- `sha256sum` or `shasum -a 256`
- ordinary Unix-like filesystem utilities used by publication

Development:

- Make
- Bats
- ShellCheck
- shfmt
- Doxygen for reference generation
- GitHub Actions

## Development Dependency Management

ADR-017 defines the source repository's deliberate self-hosting boundary.

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

The committed `dependencies.txt` file owns ordinary external development
artifacts.  At present it declares only:

```text
vendor/doxygen-bash.awk
```

using the immutable bash-doxygen v0.0.6 tag and committed digest.  The selected
released bootstrap predates ADR-015 manifest folding, so keep repository manifest
records on one physical line until the bootstrap pin intentionally moves to a
compatible release.

Target boundaries are explicit:

```text
make deps        bootstrap/verify released bashdeps, then sync dependencies.txt
make deps-check  verify existing bootstrap and manifest state without repair
make build       build only from maintained source; do not touch vendor state
make all         deps, then build
make docs        prepare deps, then generate reference documentation
```

`make deps` and therefore `make all`/`make docs` may use the network.  `make
deps-check` must not use the network.  `make build` must not invoke dependency
preparation and currently succeeds from a clean checkout because the manifest
contains documentation tooling only.

The complete `vendor/` tree is generated state.  `make distclean` removes it.

The Doxygen filter is published by bashdeps as ordinary mode `0644` data.  The
`docs` consumer target applies executable mode before Doxygen uses it.  Do not add
mode inference to bashdeps merely to satisfy this repository's documentation
consumer.

## Coding Guidelines

Prefer small, readable Bash functions with one explicit responsibility.

Manifest data is never executable input.  Do not use `eval` or `source` to parse
manifest records or CLI field values.

Do not construct shell command strings from URLs, destinations, identities, or
digests.  Pass values as quoted argv elements.

Quote expansions deliberately.

Keep downloader-specific argv and capability behavior inside downloader adapter
functions.  Synchronization logic should reason about acquisition outcomes, not
curl or wget flags.

Keep SHA-256 command differences behind a private hashing helper.

Private helpers and metadata variables use the `__bashdeps_` namespace.  Do not
create public Bash functions without an architectural decision.

Do not infer executable mode from filenames, shebangs, URLs, identities, or file
contents.

Do not normalize or repair a manifest silently.  Invalid declarations fail.

Avoid additional external runtime dependencies when Bash builtins or already
accepted platform utilities implement the behavior clearly and safely.

## Build and Release Boundaries

Treat `src/bashdeps.bash` as the source of truth.  Do not edit generated files
under `dist/` directly.

`dist/bashdeps.dev.bash` retains source comments.

`dist/bashdeps.bash` removes full-line source comments only.  Do not introduce
minification, inline-comment stripping, whitespace normalization, transpilation,
or other executable-source rewriting without a new architectural decision.

The project does not generate `bashdeps.min.bash`.

Generated artifacts embed version, source revision timestamp/build date, and
commit metadata.

Each generated Bash artifact has one checksum companion:

```text
dist/bashdeps.dev.bash.256
dist/bashdeps.bash.256
```

Each `.256` file contains the SHA-256 digest and matching artifact filename in
conventional checksum-tool syntax.  The project does not generate an aggregate
`SHA256SUMS` file.

Tests must cover maintained source and both generated Bash artifacts.

`make build` has no external manifest-managed input in the current architecture.
It must not bootstrap bashdeps, synchronize `dependencies.txt`, verify development
state, or create `vendor/`.

The versioning/release workflow likewise builds consumer artifacts without the
documentation-only dependency tree and asserts that release generation does not
create `vendor/`.  Do not couple release availability to the Doxygen filter unless
a future release artifact genuinely consumes it.

## Scope Discipline

Unless explicitly requested otherwise, produce the smallest correct change that
satisfies the documented behavior.

Do not expand bashdeps into a package manager.

Features such as semantic-version resolution, registries, transitive dependency
resolution, recursive manifests, install hooks, authenticated artifact retrieval,
automatic digest updates, arbitrary plugins, or package-manager integration
belong outside version 1 unless a later ADR changes that boundary.

A future manifest field such as `mode=0775` is architecturally possible because
the named-field grammar is extensible, but unknown fields intentionally fail in
version 1.  Do not implement speculative fields before their behavior is defined.

Do not perform unrelated refactoring, formatting, renaming, or documentation
changes in a focused patch.

If additional improvement opportunities are discovered, record them separately
rather than silently broadening the change.

## Documentation Standards

Follow the documentation-driven, test-second philosophy established by the ADRs.
Source-code documentation SHALL follow ADR-014, which adopts the documentation-first
standard established by Bootstrap ADR-045.

Maintained Bash source uses narrative-heavy Doxygen-style comments.  Every Doxygen
line begins with `##` at column 1.  Maintained Bash files require a file-level
`@file` block, every function requires an `@fn` block, and global/configuration
variables require `@var` documentation when applicable.  File and function blocks
include realistic `@par Examples` sections using `@code` and `@endcode`.

Documentation should explain intent, assumptions, constraints, invariants, safety
posture, failure modes, observable behavior, and non-goals where appropriate.  It
should help a maintainer understand why a construct exists without reverse-engineering
its control flow under pressure.  Comments that merely restate syntax are not a
substitute for that narrative.

Private `__bashdeps_*` helpers and variables are documented for maintainers.  Their
Doxygen documentation does not make them supported public interfaces; ADR-011
remains authoritative for the CLI-only compatibility boundary.

Documentation-only source work is strictly comment-only.  Do not change function
bodies, variable assignments, control flow, command invocations, shell options,
traps, or executable ordering while adding or correcting documentation.  Compare
non-comment lines before and after such a change whenever practical.

Do not invent rationale to make an implementation appear intentional.  When
purpose, usage, constraints, or rationale cannot be established confidently from
the source and governing documentation, add a specific neutral `## @TODO` in the
relevant documentation block and preserve the executable code.

`doc/bashdeps-spec.md` is the normative public-behavior reference.  ADRs preserve
why decisions were made.

When implementation and documentation disagree, do not silently choose whichever
is convenient.  Determine whether the implementation is wrong or the documented
decision has genuinely changed.

## Testing

Bats is the primary public behavior framework.

Ordinary tests must not depend on live public network services.

Use temporary project roots and controlled fixture bytes.  Exercise downloader
selection and failure through PATH-controlled fake commands where practical.

Run the same public behavior suite against:

- `src/bashdeps.bash`;
- `dist/bashdeps.dev.bash`;
- `dist/bashdeps.bash`.

Generated artifacts are products and must not be assumed correct because source
tests passed.

Repository orchestration tests run separately from the three public-artifact
behavior passes.  They should exercise Make/bootstrap/dependency boundaries with
controlled fake bootstrap/download inputs so ordinary tests remain deterministic.
CI may additionally exercise the real pinned released bootstrap and immutable
manifest URL.

Every functional change should prompt these questions:

- What public behavior changed?
- Which ADR or specification section governs it?
- How can the behavior be verified deterministically?
- Does it affect manifest parsing, byte identity, network boundaries, filesystem
  safety, output channels, or exit statuses?
- Does the same test pass against every shipped Bash artifact?

Bug fixes should add or update a regression test that would have failed before
the fix.

## Validation

When practical:

- review the resulting diff;
- run Bash syntax validation on maintained source and executable test helpers;
- run Bats tests against source and both generated artifacts;
- run the Make/bootstrap dependency-boundary regression tests;
- run ShellCheck on `src/bashdeps.bash` only; do not run ShellCheck on tests;
- run shfmt checks on maintained source and executable test helpers;
- verify a clean `make build` does not create `vendor/`;
- synchronize real development dependencies with `make deps` when integration
  validation is appropriate;
- verify synchronized state offline with `make deps-check`;
- verify `make all` sequences dependency preparation before build;
- verify `make docs` uses the manifest-managed Doxygen filter;
- verify generated artifact metadata;
- verify `dist/bashdeps.dev.bash.256` and `dist/bashdeps.bash.256` against the final
  generated bytes;
- confirm `verify` tests do not accidentally reach the network;
- confirm generated release artifacts run without the vendor tree or manifest;
- confirm generated comment removal does not alter observable behavior;
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
- assuming curl is always installed;
- treating every wget implementation as feature-identical;
- treating downloader success as proof of artifact identity;
- changing file mode on an already-correct destination during verify or sync;
- exposing private `__bashdeps_` functions as though they were a supported API;
- editing generated distribution artifacts;
- changing executable code during a documentation-only source update;
- inventing source-code rationale instead of marking genuine ambiguity with `@TODO`;
- introducing minification into this project;
- claiming multi-file transactionality or concurrency guarantees version 1 does
  not provide;
- putting `vendor/bashdeps.bash` in the manifest it is required to process;
- using unreleased `src/bashdeps.bash` as the repository bootstrap tool;
- reintroducing direct Make acquisition for manifest-managed development artifacts;
- using moving `main`/`master` URLs when an immutable release or tag is available;
- making `make build` implicitly synchronize or verify development dependencies;
- making `make deps-check` bootstrap, download, or repair state; or
- coupling release artifact generation to documentation-only dependency state.

## Final Principle

`bashdeps` knows how to materialize exact approved bytes at declared local paths
and almost nothing about what those bytes mean.

Every change should preserve that clarity.
