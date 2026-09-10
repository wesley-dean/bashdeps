# Architecture Decision Summary

This file provides concise navigation for the Architecture Decision Records under
`doc/adr/`.  The ADRs remain authoritative for rationale, constraints, tradeoffs,
and supersession relationships.

## ADR-000: Capability Scope, Epistemic Honesty, and Separation of Concerns

The project requires capability claims to remain evidence-based and explicit.
Accuracy and separation of concerns take priority over appearing agreeable or
helpful, and unsupported rationale must not be invented.  This foundation governs
all later technical and documentation decisions.  See
[ADR-000](adr/ADR-000-capability-scope-and-epistemic-honesty.md).

## ADR-001: Define bashdeps Scope and Trust Boundary

Bashdeps is an exact external-artifact synchronization and verification tool, not
a package manager.  The committed SHA-256 digest is the authority for accepted
bytes, while identity remains metadata and retrieved content is never executed as
part of synchronization.  Release discovery, version selection, transitive
resolution, lifecycle hooks, and automatic digest replacement are outside the
runtime product.  See
[ADR-001](adr/ADR-001-define-bashdeps-scope-and-trust-boundary.md).

## ADR-002: Define the Dependency Manifest Grammar

A version-1 manifest uses four required named fields: `id`, `url`, `dest`, and
`digest`.  Field order is irrelevant, values are non-whitespace tokens, unknown or
duplicate fields fail closed, and SHA-256 is mandatory.  Manifest text is data and
is never sourced or evaluated as shell code.  See
[ADR-002](adr/ADR-002-define-dependency-manifest-grammar.md).

## ADR-003: Define Install, Sync, and Verify Semantics

`install` materializes one declaration, `sync` converges a complete manifest, and
`verify` checks existing state without network access or mutation.  Digest equality
determines satisfaction, and multi-record sync preflights all required candidates
before intentional publication begins.  Bashdeps does not prune undeclared files
or claim filesystem-wide atomicity.  See
[ADR-003](adr/ADR-003-define-install-sync-and-verify-semantics.md).

## ADR-004: Define Network Acquisition Policy

Network retrieval is isolated behind a private downloader adapter and accepts only
HTTPS declarations.  Curl is preferred and a sufficiently capable Wget may serve
as fallback, with bounded attempts and finite timeout behavior where supported.
Transport success never replaces SHA-256 verification or authorizes a new digest.
See [ADR-004](adr/ADR-004-define-network-acquisition-policy.md).

## ADR-005: Define Filesystem and Publication Safety

Dependency destinations are interpreted relative to the physical invocation
working directory and are subject to conservative path, file-type, and symlink
checks.  Network candidates are staged away from final destinations and verified
before rename-style publication, with newly published files using mode `0644`.
The project explicitly does not claim race-proof concurrent filesystem safety or
multi-file atomicity.  See
[ADR-005](adr/ADR-005-define-filesystem-and-publication-safety.md).

## ADR-006: Define Runtime Platform and Tool Capabilities

Bashdeps requires Bash 4.3+, one supported HTTPS downloader, one supported SHA-256
implementation, and ordinary Unix-like filesystem behavior.  Capability detection
is preferred over operating-system assumptions, with curl then Wget for download
and `sha256sum` then `shasum -a 256` for hashing.  Additional language runtimes or
parsers are not ordinary runtime dependencies.  See
[ADR-006](adr/ADR-006-define-runtime-platform-and-tool-capabilities.md).

## ADR-007: Define CLI, Diagnostics, and Exit Statuses

The runtime executable is `bashdeps.bash` with `install`, `sync`, `verify`, help,
and version commands.  Successful state operations are normally quiet, diagnostics
go to STDERR, and broad failure classes receive stable exit statuses from 0
through 6.  This process CLI, rather than private helper names, is the supported
runtime interface.  See
[ADR-007](adr/ADR-007-define-cli-diagnostics-and-exit-statuses.md).

## ADR-008: Define Bootstrap and Make Integration

A consuming project must bootstrap `bashdeps.bash` outside the manifest that the
tool will later process.  The bootstrap artifact is pinned and independently
SHA-256 verified, while Make separates network-capable convergence from offline
verification and ordinary build work.  Later ADR-017 refines the repository's own
self-hosting implementation.  See
[ADR-008](adr/ADR-008-define-bootstrap-and-make-integration.md).

## ADR-009: Define Build and Release Artifact Contract

Maintained source lives under `src/`, while generated release files live under
`dist/` and are never hand-maintained.  The original decision introduced developer
and comment-stripped executable flavors with per-artifact checksums and common
release metadata.  ADR-018 later supersedes the two-flavor/no-minification portion,
and ADR-019 supersedes checksum suffix naming.  See
[ADR-009](adr/ADR-009-define-build-and-release-artifact-contract.md).

## ADR-010: Define Development and Testing Workflow

Make is the canonical development orchestration surface and Bats is the primary
public behavior framework.  Ordinary tests use controlled local fixtures instead
of live public network services, and shipped generated artifacts receive the same
behavioral scrutiny as maintained source.  Later dependency/build ADRs refine
specific target ordering and artifact surfaces.  See
[ADR-010](adr/ADR-010-define-development-and-testing-workflow.md).

## ADR-011: Define Public Interface Boundary

`bashdeps.bash` is supported as an executable CLI rather than a sourceable Bash
library.  Private `__bashdeps_*` helpers may be documented and tested internally
without becoming compatibility promises to consumers.  A future sourceable API
would require its own explicit architecture decision.  See
[ADR-011](adr/ADR-011-define-public-interface-boundary.md).

## ADR-012: Define Wget Capability Floor

A command named `wget` is accepted as the bashdeps fallback only when its help
surface advertises both `-T` timeout and `-t` tries controls.  The adapter uses a
finite timeout and one backend-managed try so bashdeps retains control over its
bounded acquisition attempts.  Unsupported Wget variants fail as unavailable
capability rather than silently weakening policy.  See
[ADR-012](adr/ADR-012-define-wget-capability-floor.md).

## ADR-013: Default Destination Root with Explicit Override

Bashdeps confines destinations beneath `vendor/` by default and allows a caller to
select another normalized project-relative root explicitly with `--dest-root`.
The option is a containment policy, not a relocation prefix, so `dest=` always
names the complete project-relative destination visible in source review.  This
decision supersedes the broader destination scope originally described by
ADR-002 and ADR-005.  See
[ADR-013](adr/ADR-013-default-destination-root-with-explicit-override.md).

## ADR-014: Documentation-First Source Code Commenting Standard

Maintained Bash source uses narrative-heavy Doxygen-style documentation for file,
function, variable, safety, and failure contracts.  Documentation of private
helpers improves maintainability without changing ADR-011's public API boundary,
and documentation-only changes must preserve executable behavior.  The repository
now also contains `doc/documentation-standard.md` as the current detailed standard
for new maintained Bash work.  See
[ADR-014](adr/ADR-014-documentation-first-source-code-commenting-standard.md).

## ADR-015: Define Manifest Physical-Line Folding

One logical dependency record may span multiple physical lines only through an
explicit standalone trailing backslash continuation marker.  Folding occurs before
field parsing, indentation is cosmetic, and blank/comment lines cannot interrupt
an active continuation.  The rule improves readability without turning the
manifest into shell syntax or an indentation-sensitive format.  See
[ADR-015](adr/ADR-015-define-manifest-physical-line-folding.md).

## ADR-016: Define the Doxygen Reference Documentation Workflow

`make docs` is the canonical path for generating browsable reference documentation
from maintained Bash source using the bash-doxygen filter.  Generated HTML lives
under ignored `doc/reference/` and GitHub Pages builds it from source rather than
requiring generated documentation commits.  ADR-017 later supersedes direct
filter download with manifest-managed dependency preparation.  See
[ADR-016](adr/ADR-016-define-doxygen-reference-documentation-workflow.md).

## ADR-017: Self-Host Build and Development Dependency Management

The repository bootstraps one previously released, pinned `vendor/bashdeps.bash`
and uses it to synchronize ordinary external development/build artifacts declared
in `dependencies.txt`.  This avoids asking unreleased source to bootstrap itself
and keeps `make deps-check` offline and non-repairing.  ADR-018 later adds a real
manifest-managed build input and changes the clean-build consequence.  See
[ADR-017](adr/ADR-017-self-host-build-development-dependencies.md).

## ADR-018: Three-Flavor Release Artifacts with Bash-Minifier

The release pipeline produces developer, ordinary comment-stripped, and minified
`bashdeps.bash` artifacts from one complete assembled program.  Bash-Minifier is a
commit-pinned manifest-managed build dependency, while `make build` remains
network-free and requires already-prepared dependency state.  Every shipped flavor
is tested independently rather than assuming the transformation is semantics
preserving.  See
[ADR-018](adr/ADR-018-three-flavor-release-artifacts-with-bash-minifier.md).

## ADR-019: Standardize SHA-256 Checksum Companion Filenames

New release checksum companions use the self-describing `.sha256` suffix and
retain conventional checksum-tool contents.  Historical `.256` files remain valid,
and read-side fallback may use them only when the preferred modern sidecar is
confirmed absent.  Remote sidecars never replace the committed digest as the
runtime trust authority.  See
[ADR-019](adr/ADR-019-standardize-sha256-checksum-companion-filenames.md).

## ADR-020: Ship Manifest Manager and Define Surgical Updates

The repository ships `manifest-manager.bash` as a second first-class executable
beside `bashdeps.bash`, sharing one project release version while retaining an
explicit independent source/runtime closure.  The manager uses curl-based GitHub
latest-release discovery and surgical identity/URL/digest substitutions that prove
unrelated manifest bytes are unchanged; stream failures reproduce completely
captured input.  Each product receives developer, ordinary, and minified artifacts
plus `.sha256` companions, bringing releases to twelve files without importing
manager-only code into bashdeps.  See
[ADR-020](adr/ADR-020-ship-manifest-manager-and-define-surgical-updates.md).

## ADR-021: Extend Manifest Manager with List, Add, and Remove

The manager grows as a conservative source-maintenance CLI with provider-neutral
`list`, explicit-field `add`, and exact-identity `remove` contracts while leaving
`bashdeps.bash` unchanged.  `list` emits complete validated `id` values in manifest
order; `add` and `remove` preserve unrelated source bytes and use operation-specific
proofs rather than parse-and-reserialize behavior.  Comments are not implicitly
owned by adjacent records, and `add` does not infer URLs, destinations, artifact
names, or digests.  See
[ADR-021](adr/ADR-021-extend-manifest-manager-with-list-add-and-remove.md).

## ADR-022: Publish an Ephemeral Generated ADR Landing Page

Documentation builds compose maintained ADR framing with an adrctl-generated
linked table of contents into ignored `doc/adr/README.md`, then use that ephemeral
Markdown file as the Doxygen main page.  The adrctl release is checksum-pinned as
documentation-only tooling, the generated README is not committed, and normal
publication deliberately omits ADR relationship graphs.  See
[ADR-022](adr/ADR-022-publish-an-ephemeral-generated-adr-landing-page.md).
