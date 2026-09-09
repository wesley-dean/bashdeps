# ADR-020: Ship Manifest Manager and Define Surgical Updates

Date: 2026-09-09

## Status

Accepted

## Intent and Scope

This Architecture Decision Record introduces `manifest-manager.bash` as a second
first-class executable produced by the bashdeps repository and defines the
initial `update` operation that maintains existing bashdeps dependency manifests.

The decision deliberately preserves the boundary established by ADR-001.
`bashdeps.bash` remains an exact-artifact synchronization and verification tool.
It does not discover releases, select versions, or change committed trust data.
`manifest-manager.bash` is separate maintainer tooling that prepares reviewable
manifest source changes before those changes are committed and later consumed by
`bashdeps.bash`.

This ADR also extends the release model from one executable family to two.  The
products share repository governance, release version, build metadata, and release
cadence, while retaining independent source closures and runtime requirements.
Code required only by one product must not be incorporated into the other merely
because both are built from the same repository.

Issue #16 defines the initial implementation request.  Issue #17 tracks possible
future `add`, `remove`, and `list` subcommands and remains outside this decision's
initial behavior except for reserving a subcommand-oriented CLI shape.

## Context

A bashdeps manifest is trusted source code.  Updating one dependency currently
requires a maintainer to coordinate at least three related source changes:

1. select a target version or release tag;
2. change the dependency identity and immutable artifact URL; and
3. calculate and commit the SHA-256 digest of the proposed artifact bytes.

Those steps are mechanical enough to automate, yet they are intentionally absent
from `bashdeps.bash`.  ADR-001 excludes dependency-update discovery and version
selection from the runtime product.  ADR-004 further states that retrieved bytes
must never cause the approved digest to change automatically during synchronization.
ADR-019 permits a maintainer or external helper to assist with an update while
preserving the committed manifest as the explicit authorization step.

The distinction is important.  A synchronizer answers whether local bytes match
already-approved source.  A manifest-maintenance tool helps a maintainer prepare a
proposal to approve different bytes.  Combining those responsibilities would
allow runtime retrieval to rewrite its own trust authority.

The repository also already has a mature distribution pipeline.  ADR-018 produces
three representations of `bashdeps.bash`: developer, ordinary comment-stripped,
and minified.  ADR-019 gives each one a `.sha256` companion.  A separately useful
manifest manager should receive the same distribution treatment without turning
one executable into a superset of the other.

The initial manager is GitHub-aware because the demonstrated manifests use GitHub
release/tag URLs.  Requiring the GitHub CLI or a JSON parser solely to discover the
latest release would enlarge deployment requirements unnecessarily.  GitHub
provides a canonical `OWNER/REPO/releases/latest` redirect whose effective URL
contains the release tag, allowing the manager to use curl without parsing API
JSON.

Finally, the manifest is intentionally human-readable source.  Reformatting or
regenerating an entire record merely to update three values would create noisy
review diffs and could alter comments, physical continuation layout, line endings,
or other source bytes unrelated to the requested trust change.  Exact preservation
therefore needs to be an architectural property rather than an implementation
preference.

## Decision Drivers

- Preserve ADR-001's separation between runtime materialization and update
  selection.
- Keep committed manifest changes visible and reviewable as trust decisions.
- Reduce mechanical errors when identity, URL, and SHA-256 digest change together.
- Preserve unrelated manifest bytes exactly, including physical formatting.
- Make file and stdin/stdout operation transactional at the manifest level.
- Provide a process-oriented interface suitable for humans, Make, CI, and shell
  pipelines without introducing JSON output.
- Avoid a dependency on `gh`, `jq`, Python, or another JSON parser.
- Keep each released executable's runtime dependency closure independent.
- Prevent product-specific helper code from leaking into the other executable.
- Reuse the existing developer, ordinary, minified, and checksum release model.
- Keep future manifest operations possible without pre-designing them now.

## Decision

### Ship a second first-class executable

The repository SHALL maintain two executable products:

```text
src/bashdeps.bash
src/manifest-manager.bash
```

`bashdeps.bash` retains its existing runtime responsibility and public contract.

`manifest-manager.bash` is a maintainer-side manifest source-management CLI.  Its
initial public subcommand is:

```text
manifest-manager.bash update ...
```

The executable SHALL not be required to run `bashdeps.bash`, `bashdeps sync`, or
`bashdeps verify`.  Likewise, `bashdeps.bash` SHALL never invoke
`manifest-manager.bash` as part of dependency materialization or verification.

The manager SHALL expose only a process-oriented CLI.  Its private Bash functions
are not a supported sourceable API.

### Share one project version and release cadence

Both executable families SHALL use the same bashdeps project version, source
revision date, and source commit metadata for a given release.

The repository SHALL not maintain an independent manifest-manager version stream.
A release therefore identifies the complete tested repository product set rather
than requiring separately coordinated version numbers.

### Publish twelve release assets

`make build` SHALL produce these executable artifacts:

```text
dist/bashdeps.dev.bash
dist/bashdeps.bash
dist/bashdeps.min.bash

dist/manifest-manager.dev.bash
dist/manifest-manager.bash
dist/manifest-manager.min.bash
```

Each executable SHALL have one `.sha256` companion under ADR-019:

```text
dist/bashdeps.dev.bash.sha256
dist/bashdeps.bash.sha256
dist/bashdeps.min.bash.sha256

dist/manifest-manager.dev.bash.sha256
dist/manifest-manager.bash.sha256
dist/manifest-manager.min.bash.sha256
```

New GitHub releases SHALL publish all twelve files.

For each product, the `.dev.bash` artifact retains source documentation, the
ordinary `.bash` artifact removes full-line comments after the shebang, and the
`.min.bash` artifact is produced from the completed ordinary artifact with the
manifest-managed Bash-Minifier.  Each generated executable must independently
pass syntax, behavior, compatibility, and checksum validation.

### Assemble products from explicit source closures

The build SHALL define an explicit source inventory for each executable family.

Conceptually:

```text
BASHDEPS_SOURCES
MANIFEST_MANAGER_SOURCES
```

A source component SHALL be incorporated into an executable only when that product
directly requires the component.  The presence of a Bash file in `src/`, `lib/`,
or another repository directory SHALL NOT automatically include it in either
product.

A component may appear in both inventories only when it implements behavior
intentionally shared by both products.  Repository co-location alone is not a
reason to make a component shared runtime code.

Wildcard assembly of all available libraries is therefore prohibited for these
release products.  This rule protects `bashdeps.bash` from accidentally acquiring
GitHub release-selection code or manager-only runtime dependencies, and protects
the manager from unrelated synchronization/publication code.

The initial manifest-manager implementation requires no shared runtime library
with `bashdeps.bash`; each maintained executable is its own explicit source
closure.

### Keep runtime capabilities product-specific

`manifest-manager.bash` SHALL require:

- Bash 4.3 or newer;
- curl for GitHub release discovery and HTTPS artifact retrieval;
- `sha256sum` or `shasum -a 256` for digest calculation; and
- ordinary Unix-like filesystem utilities used for staging and publication.

It SHALL NOT require:

- the GitHub CLI (`gh`);
- `jq` or another JSON parser;
- Python, Perl, Ruby, or Node.js;
- Git for runtime operation; or
- `bashdeps.bash` itself.

These requirements are independent from ADR-006's runtime capability contract for
`bashdeps.bash`.  A requirement introduced for one executable SHALL NOT become a
requirement of the other unless both products genuinely use that capability.

### Resolve omitted versions through GitHub's latest-release redirect

When `VERSION` is omitted for an update, the manager SHALL request:

```text
https://github.com/OWNER/REPO/releases/latest
```

through curl, follow HTTPS redirects, and inspect curl's final effective URL.
The final URL must have the matching form:

```text
https://github.com/OWNER/REPO/releases/tag/ENCODED_TAG
```

The manager SHALL percent-decode the single tag path component and use the decoded
value as the exact target tag.  `+` is ordinary path data and SHALL NOT be decoded
as a space.  Malformed percent escapes and NUL encodings SHALL fail.

The manager SHALL NOT enumerate tags, sort versions, query a package registry, or
implement its own definition of "latest."  GitHub's canonical latest release is
the authority for the omitted-version operation.

The literal word `latest` is not reserved.  If supplied explicitly as `VERSION`,
it is the exact requested tag.

An explicitly supplied version/tag does not need a GitHub Release object.  The
manager uses the supplied tag exactly; successful retrieval of the derived
artifact URL establishes that the requested Git ref is usable for the declared
artifact.  No semantic-version normalization, range interpretation, or automatic
leading-`v` transformation is performed on the requested target.

### Support only unambiguous GitHub URL transformations initially

The manager SHALL initially update only existing dependency records whose GitHub
package and immutable artifact URL can be related mechanically without guessing.

Supported URL families are:

```text
https://raw.githubusercontent.com/OWNER/REPO/REF/ARTIFACT_PATH
https://github.com/OWNER/REPO/releases/download/TAG/ASSET_PATH
```

The existing `OWNER/REPO` must agree with the selected package.  The URL ref/tag
must correspond to the current identity version.  Exact equality is preferred;
one leading `v` difference is accepted for compatibility with existing manifests
such as:

```text
id=wesley-dean/bash-doxygen@0.0.6
url=https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk
```

This compatibility relation is used only to validate the existing declaration.
The new identity and URL use the exact requested or discovered target tag.

Commit-pinned dependencies are not release-updateable.  An identity version that
is a 40- or 64-character hexadecimal commit identifier SHALL fail rather than be
silently reinterpreted as a release tag.

For a raw-content URL, a target tag containing `/` is ambiguous with the path that
follows the ref and SHALL fail.  Unsupported URL shapes likewise fail rather than
trigger artifact-name, destination, or repository inference.

### Preserve the manifest through surgical literal substitution

The manager SHALL parse manifests only to validate grammar, establish logical
record boundaries, and identify the exact raw record to update.  It SHALL NOT
serialize parsed records back into source.

For each selected dependency, `update` may change only:

- the `id` value;
- the `url` value; and
- the `digest` value.

`dest` SHALL remain unchanged.

Each intended old value must occur exactly once in the selected raw record before
it can be replaced.  Zero occurrences or multiple occurrences are a safety
failure.

The implementation SHALL retain raw physical record bytes separately from the
folded parsing view.  Successful updates therefore preserve unrelated:

- spaces and tabs;
- indentation;
- field ordering;
- continuation markers and physical line layout;
- blank lines;
- comments;
- trailing whitespace;
- LF versus CRLF line endings;
- final-newline state; and
- unrelated dependency records.

Before output or publication, the manager SHALL prove that the candidate differs
only through intended raw-record replacements.  One acceptable implementation is
to replace each updated raw record back with its original in reverse order and
require byte-for-byte equality with the complete captured input.  The candidate
manifest SHALL also pass manifest validation after mutation.

Manifest input containing bytes that cannot be represented losslessly by the Bash
implementation, including NUL, SHALL fail rather than be silently normalized or
truncated.

### Treat candidate digest changes as proposed source changes

For each selected record, the manager SHALL:

1. construct the target URL from the supported existing URL shape;
2. download candidate bytes into private staging;
3. calculate SHA-256 over those exact bytes;
4. prepare the new `digest=sha256:...` value; and
5. retain the change only if all surgical and preservation checks succeed.

Downloaded artifacts SHALL never be executed by the manager.

If the target URL is byte-for-byte identical to the existing immutable URL but the
retrieved bytes no longer match the committed digest, the operation SHALL fail
rather than silently bless changed bytes at an allegedly immutable location.

The calculated digest is not runtime trust established by the manager.  It becomes
a proposal in repository source.  Review and commit of the manifest change remain
the authorization boundary consumed later by `bashdeps.bash`.

### Make `--all` a whole-manifest transaction

`manifest-manager.bash update --all` SHALL attempt to update every declared
dependency to its GitHub latest release.

Before release discovery, the operation SHALL validate that every dependency has
an unambiguous GitHub `PACKAGE@VERSION` identity and that no dependency is
commit-pinned.  It SHALL NOT silently skip unsupported records.

All release discoveries, candidate downloads, hashes, exact substitutions, and
preservation checks SHALL complete before the manifest is published or emitted.
If any dependency fails, the complete `--all` operation fails.

This is manifest-source transactionality, not a claim about remotely retrieved
artifacts or later `bashdeps sync` filesystem publication.

### Define file mode as staged single publication

With the default `dependencies.txt` or `-f FILE`, the manager SHALL capture the
complete original manifest before network work.  A failed update SHALL leave the
manifest path unchanged.

After the complete candidate passes validation, the manager SHALL compare the
current manifest bytes with the captured original to detect an ordinary concurrent
edit.  If they differ, publication fails rather than overwriting the newer source.

A changed candidate SHALL be written to a destination-adjacent temporary file and
renamed into place only after the complete transaction succeeds.  Existing file
metadata SHOULD be preserved where the available filesystem tools permit it.

The manager does not claim race-proof locking or `openat`-style protection against
a hostile concurrent local process.

### Define `-f -` as a rollback-preserving stream transform

With:

```text
-f -
```

the manager SHALL capture the complete STDIN manifest before performing update
work.

After successful input capture, exactly one complete manifest representation is
written to STDOUT:

```text
success -> complete updated manifest
failure -> complete original input manifest, byte-for-byte
```

A failure during dependency N of M therefore cannot expose a partially updated
stream and cannot turn successfully captured input into an empty output file.
Diagnostics remain on STDERR and the nonzero exit status still communicates that
the requested update did not succeed.

If reading STDIN itself fails before complete capture, the manager cannot reproduce
bytes it never successfully received.  If writing STDOUT fails, it likewise cannot
guarantee what the downstream consumer received.  These ordinary I/O limits are
explicit non-promises.

Help and version requests are informational success operations and need not consume
STDIN merely because `-f -` also appears in their argument list.

### Keep successful file-mode operation quiet

Normal successful file-mode updates SHALL write nothing to STDOUT.  Diagnostics
SHALL go to STDERR.  No JSON output or other structured serialization format is
part of the interface.

Help and version output use STDOUT.

The manager SHALL use these public exit categories:

```text
0  success, help, version, or successful no-op
2  invalid CLI, manifest, dependency selection, or update declaration
3  required runtime capability unavailable or unusable
4  latest-release discovery or network acquisition failed
5  exact-substitution or preservation safety check failed
6  input, staging, filesystem, or publication failed
```

A successful no-op returns status 0.  For an explicit target already present in
the manifest, the manager may still retrieve and hash the immutable target bytes
so changed bytes at the same URL are detected rather than automatically approved.

### Preserve subcommand space for later manifest operations

The initial public mutation operation is only `update`.

Future commands such as:

```text
manifest-manager.bash add ...
manifest-manager.bash remove ...
manifest-manager.bash list ...
```

are tracked by issue #17 and require their own defined behavior before
implementation.  The existence of the `manifest-manager.bash` executable does not
implicitly authorize those semantics.

### Document and test the products independently

`src/manifest-manager.bash` SHALL follow `doc/documentation-standard.md` from its
initial implementation.  Existing maintained scripts are not reformatted or
backported to the revised standard as part of this feature.

Doxygen input SHALL include both maintained executable sources.

The manager SHALL have its own public behavior suite executed against:

1. `src/manifest-manager.bash`;
2. `dist/manifest-manager.dev.bash`;
3. `dist/manifest-manager.bash`; and
4. `dist/manifest-manager.min.bash`.

The existing bashdeps behavior suite continues to execute independently against
its four source/distribution surfaces.  Tests SHOULD also verify that unmistakably
product-specific private symbols do not appear in the other product's developer
artifact, protecting the explicit source-closure rule.

Ordinary manager tests SHALL use controlled curl fixtures rather than live GitHub
state.

## Considered Alternatives

### Add `update` to `bashdeps.bash`

This would provide one executable, but it would directly contradict the separation
established by ADR-001.  A runtime tool that consumes committed trust declarations
must not silently become the tool that selects and rewrites those declarations.

### Keep the manager as an unreleased repository-only script

That would reduce release assets, but the CLI is useful to any repository that
maintains bashdeps manifests.  Shipping it as a first-class optional executable
makes the behavior testable and consumable without making it a runtime dependency
of bashdeps.

### Give the manager an independent version stream

Independent versions could allow separate release cadences, but they would add
coordination and metadata complexity while both executables are built, tested, and
published from the same repository revision.  One project release version is the
simpler contract.

### Put all Bash libraries into both executables

A universal bundle simplifies Make logic, but it would cause product-specific
behavior and dependencies to leak across the architectural boundary.  Explicit
source closures are selected instead.

### Require the GitHub CLI

`gh` provides convenient release lookup and authentication behavior.  It is not
required for the public release information used here, however, and would enlarge
the manager's deployment requirements.  Curl effective-URL discovery is sufficient
for the initial latest-release contract.

### Use the GitHub REST API and parse JSON

The REST API exposes `tag_name` directly, but parsing it correctly requires a JSON
parser such as `jq` or a larger custom parser.  The canonical release redirect
provides the required datum without adding that dependency or creating a partial
JSON implementation in Bash.

### Determine latest by sorting Git tags

Sorting tags would invent semantic-version assumptions and would not necessarily
match the release GitHub designates as latest.  The manager follows GitHub's own
latest-release selection instead.

### Reserve `latest` as a magic version

An upstream tag can legitimately be named `latest`.  Omission of VERSION provides
an unambiguous discovery request while preserving every explicit string as literal
tag data.

### Parse and regenerate manifest records

Regeneration would simplify field updates but would normalize source formatting
and create unrelated diff noise.  It could also alter CRLF/LF state, continuations,
comments, or whitespace.  Surgical replacement is selected because the manifest
is reviewed source, not merely an interchangeable serialization.

### Allow `--all` to skip unsupported dependencies

Skipping would make mixed release/tag and commit-pinned manifests convenient, but
it would make `all` mean "all dependencies understood by this invocation."  The
selected contract fails the transaction so callers cannot mistake a partial update
set for complete maintenance.

### Add dependency creation now

A new package identity alone does not establish the correct artifact URL or local
destination.  Addition, removal, and listing are intentionally left to issue #17
so their contracts can be designed without expanding the first update feature.

## Consequences

The repository becomes a two-product project and publishes twelve release assets
instead of six.

Build, test, documentation, and release automation become larger because each
manifest-manager artifact is validated independently.  In exchange, consumers can
obtain the maintainer tool with the same artifact-quality guarantees as
`bashdeps.bash`.

The bashdeps runtime remains small and unaware of GitHub release selection.
Manager-only code and runtime requirements stay outside the bashdeps executable
unless a later explicit shared-library decision establishes genuine commonality.

Manifest update diffs remain narrow.  Reviewers can focus on the intended identity,
URL, and digest changes without unrelated formatting churn.

Stream-mode callers gain a strong recovery property: after complete STDIN capture,
a failed update returns the original manifest on STDOUT.  Callers must still check
the exit status to distinguish updated output from rollback output.

Commit-pinned and unsupported URL declarations make `--all` fail.  This is an
intentional consequence of making completeness explicit rather than silently
partial.

The manager is GitHub-specific in its initial update support.  Support for another
hosting provider, URL family, authentication model, or release-discovery mechanism
requires a deliberate extension rather than generic URL guessing.

## Follow-Ups

Issue #17 tracks possible `add`, `remove`, and `list` operations.

If multiple source files later become genuinely shared between the products, the
build may add an explicit shared source inventory while retaining product-specific
closures and regression tests against accidental code inclusion.

If authenticated/private GitHub dependencies become a demonstrated requirement,
the manager's transport and credential boundary will require a separate decision.

The existing `src/bashdeps.bash` documentation may be migrated to the revised
`doc/documentation-standard.md` in separate work, as requested, without coupling
that backport to this feature.

## Related Decisions

- Related to: ADR-000
- Preserves and extends externally from: ADR-001
- Uses the manifest grammar from: ADR-002
- Related to transport separation in: ADR-004
- Related to publication safety principles in: ADR-005
- Keeps product capabilities separate from: ADR-006
- Establishes a separate CLI beside: ADR-007
- Extends the release product set defined by: ADR-018
- Uses checksum companion naming from: ADR-019
- Uses physical-line semantics from: ADR-015
- Uses source documentation workflow from: ADR-014 and
  `doc/documentation-standard.md`
