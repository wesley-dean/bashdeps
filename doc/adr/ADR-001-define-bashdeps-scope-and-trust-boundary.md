# ADR-001: Define bashdeps Scope and Trust Boundary

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines what `bashdeps` is responsible for, what it deliberately does
not attempt to do, and what security claims it may honestly make.

The project sits on a software supply-chain boundary: it retrieves external
artifacts and places them where consuming projects can use them.  That role
requires a narrow product definition and conservative trust model.  Features
that blur the distinction between exact artifact materialization and package
management are intentionally excluded unless a later ADR revisits the boundary
with a demonstrated need.

## Context

Several projects need exact external inputs such as released Bash scripts,
libraries, filters, generators, templates, data files, images, or other
repository-local artifacts.  Implementing download, verification, staging,
cache validation, and error behavior independently in each Makefile duplicates
security-sensitive logic and creates opportunities for those implementations to
drift.

Although `bashdeps` is implemented in Bash and initially motivated by Bash
projects, a managed dependency is an artifact rather than an executable unit.
The tool does not assume that downloaded bytes are shell code, executable, or
even textual.

A concrete failure in `adrctl` demonstrated that the presence of a dependency at
an expected filename does not establish that the expected version or bytes are
present.  A stale locally cached artifact survived a version change and was
incorporated into a generated artifact even though surrounding metadata claimed
a newer dependency version.  Digest verification of the bytes actually consumed
is therefore a central requirement, not an optional enhancement.

`bashdeps` is intended to centralize this repeated policy in one small Bash tool.
A consuming repository will still need a small bootstrap path that obtains the
pinned `bashdeps` release artifact before `bashdeps` can manage the project's
ordinary dependencies.  The project does not claim that this bootstrap dependency
disappears; it claims that one intentionally small bootstrap path can replace
multiple independent dependency-acquisition implementations.

The initial design uses a committed, line-oriented dependency manifest whose
records identify an external artifact, its retrieval URL, its destination, and
its approved SHA-256 digest.  The manifest is trusted source code and belongs
inside the same review and repository-protection boundary as the consuming
project's Makefile and source.

Some upstream projects do not publish checksums for their release artifacts.
That does not prevent a consuming project from computing the SHA-256 digest of
the exact artifact it reviewed and committing that digest to its manifest.
Accordingly, upstream checksum publication is not a prerequisite for `bashdeps`
verification.

## Decision Drivers

- Centralize repeated dependency-acquisition and verification policy.
- Verify the exact bytes a consuming project will use.
- Detect stale, modified, corrupted, or silently replaced local artifacts.
- Keep the manifest readable by humans and straightforward for automation.
- Keep the implementation small enough to audit as supply-chain-sensitive code.
- Avoid arbitrary code execution while acquiring dependencies.
- Avoid assuming that managed artifacts are executable Bash files.
- Avoid accidental evolution into a general package manager.
- Preserve deterministic behavior and explicit failure semantics.
- Make security claims no stronger than the mechanism supports.
- Permit projects to pin artifacts even when upstream does not publish hashes.

## Decision

`bashdeps` SHALL be a deterministic external-artifact synchronization and
verification tool implemented in Bash.

Its core responsibility SHALL be:

```text
committed dependency manifest
        |
        v
validate declarations
        |
        v
obtain exact declared artifacts when needed
        |
        v
verify approved byte identity
        |
        v
materialize verified bytes at declared destinations
```

The project SHALL operate on exact dependency declarations.  It SHALL NOT resolve
acceptable versions, discover newer versions, select among package candidates, or
construct dependency graphs.

A managed artifact MAY be executable code, source code, a library, a template, a
data file, an image, or another ordinary file.  `bashdeps` SHALL NOT infer file
purpose or executability from its identity, URL, destination name, or contents.
File mode is therefore separate from byte identity and is not part of the
version 1 manifest contract.  A later manifest version MAY add an explicit named
field such as `mode=0775` if a demonstrated consumer requirement justifies that
behavior.

Every managed dependency SHALL have a committed SHA-256 digest.  The digest MAY
be copied from an upstream-published checksum when an appropriate trusted checksum
is available, or MAY be computed independently by the consuming project from the
exact artifact it intends to approve.  The absence of an upstream-published
checksum SHALL NOT create an unverified or hash-optional manifest mode.

SHA-256 verification establishes that local or downloaded bytes match the digest
approved in the manifest.  It does not establish that the upstream software or
other artifact is safe, benevolent, free from vulnerabilities, correctly
labeled, or semantically consistent with a version string in the dependency
identity or URL.

The dependency identity field SHALL be metadata for humans and external
automation.  The generic `bashdeps` implementation SHALL treat it as opaque except
for validation and uniqueness rules defined by the manifest grammar.  Byte
acceptance SHALL be determined by digest equality rather than by filenames,
version labels, timestamps, HTTP metadata, or dependency identity text.

The manifest SHALL be treated as trusted source code.  A contributor able to
change both the artifact location and approved digest can intentionally declare
new trusted bytes.  Repository review, CODEOWNERS, branch protection, signed
commits, or similar governance controls may reduce that risk, but those controls
remain responsibilities of the consuming repository rather than `bashdeps`.

`bashdeps` SHALL NOT execute downloaded dependencies as part of synchronization
or verification.  Manifest contents SHALL NOT be evaluated or sourced as shell
code.  Arbitrary install hooks, post-install hooks, build hooks, and plugin
execution are outside the initial product boundary.

The following capabilities are explicitly out of scope for the initial project:

- semantic-version ranges or constraint solving;
- package registries;
- transitive dependency resolution;
- dependency graphs;
- recursive manifests;
- arbitrary install, post-install, or lifecycle scripts;
- runtime dependency discovery;
- operating-system package management;
- automatic trust of moving branches or mutable labels;
- automatic digest replacement when downloaded bytes differ;
- implicit transformation of downloaded dependency bytes;
- a global package database;
- dependency-update discovery or version-selection behavior.

External tooling such as Renovate may eventually understand the manifest and
propose coordinated identity, URL, and digest updates.  That integration SHALL
remain separate from the core synchronization and verification semantics.

A successful `bashdeps` operation SHALL make only claims justified by the
operation performed.  In particular:

- digest verification means byte equality with the approved digest;
- reproducibility of declared inputs does not imply offline availability;
- staged multi-file publication may reduce predictable partial updates but does
  not imply filesystem-wide transactionality;
- HTTPS transport does not establish that the retrieved artifact itself is
  trustworthy;
- a valid manifest does not establish semantic agreement between dependency
  identity, URL naming, and artifact contents.

## Considered Alternatives

### Permit dependencies without digests

A placeholder such as `-` or `nohash` could allow synchronization of artifacts
whose upstream projects do not publish checksums.

This was rejected because the consuming project can compute and commit the digest
of the exact artifact it approves.  Making hashes optional would remove the
mechanism that distinguishes an already-correct local artifact from stale,
modified, corrupted, or silently replaced bytes.  It would also create two
substantially different trust modes inside one manifest format.

### Trust only upstream-published checksums

This would align the manifest with upstream release metadata when checksums are
available.

This was rejected because many otherwise usable projects do not publish artifact
checksums.  The approved digest is a consuming-project trust decision and need not
originate upstream.

### Build a Bash package manager

A broader tool could resolve versions, follow transitive dependencies, understand
GitHub releases or package registries, and execute installation behavior.

This was rejected because those capabilities introduce substantially more parser,
resolver, trust, compatibility, and lifecycle complexity.  Existing package
managers already occupy that space.  `bashdeps` is intended to materialize exact
approved artifacts, not select packages.

### Limit managed artifacts to executable Bash files

The initial consumers are Bash projects, so the tool could assume every managed
artifact is executable shell code and apply executable permissions automatically.

This was rejected because acquisition integrity is independent of artifact type.
Templates, data files, images, source files, filters, and other build inputs
benefit from the same exact-byte materialization model.  Avoiding an executability
assumption also keeps the core behavior smaller and more generally useful.

### Keep dependency acquisition entirely in each consuming Makefile

This avoids the bootstrap dependency on `bashdeps` itself.

This remains reasonable for projects with trivial or unique needs.  It was not
selected as the general direction because several Bash projects already repeat
substantially similar download, verification, staging, and cache-validation
logic.  Centralizing that policy provides a single implementation and test suite
for security-sensitive behavior.

### Treat dependency identity or version labels as authoritative

The tool could infer whether an existing artifact is current from its filename,
versioned path, embedded metadata, or manifest identity.

This was rejected because labels describe intent rather than prove byte identity.
The stale-cache failure that motivated this project demonstrated that metadata can
claim one version while the consumed bytes belong to another.

## Consequences

The manifest format will require a SHA-256 digest for every managed dependency.
Projects using an upstream artifact without published checksums must compute and
review that digest themselves before committing the dependency declaration.

A valid local artifact can be reused without network access after its digest is
verified.  A mismatched artifact cannot be accepted merely because its filename
or dependency identity looks correct.

The core tool remains intentionally ignorant of package ecosystems, release
semantics, and artifact purpose.  This reduces implementation complexity and
keeps the trust boundary inspectable, while allowing the same mechanism to
materialize code and non-code files.

Consumers still have a bootstrap responsibility for obtaining and verifying the
`bashdeps` artifact itself.  The project must document that tradeoff explicitly
rather than presenting `bashdeps` as eliminating dependency bootstrapping.

Security review of manifest changes remains important because changing both a URL
and digest intentionally changes the bytes the project trusts.

Future features that add version resolution, lifecycle hooks, recursive manifests,
or executable plugins will require an explicit architectural reconsideration of
this ADR rather than being treated as incremental conveniences.

## Open Questions and Follow-Ups

Subsequent ADRs need to define:

- the exact `dependencies.txt` grammar and validation rules;
- installation, synchronization, and verification command semantics;
- staging and publication behavior;
- URL, redirect, timeout, retry, and transport policy;
- destination and symlink safety rules;
- bootstrap acquisition and verification of `bashdeps` itself;
- release artifact generation and validation;
- external command and minimum Bash requirements;
- integration expectations for consuming Makefiles;
- optional external dependency-update tooling such as Renovate.

## Related Decisions

- Related to: ADR-000
- Derived from: `bash-dependency-manifest-handoff.md`
- Derived from: `bash-dependency-convergence-handoff.md`
