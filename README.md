# bashdeps

[![Dependabot Updates](https://github.com/wesley-dean/bashdeps/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/wesley-dean/bashdeps/actions/workflows/dependabot/dependabot-updates)
[![MegaLinter](https://github.com/wesley-dean/bashdeps/actions/workflows/megalinter.yml/badge.svg)](https://github.com/wesley-dean/bashdeps/actions/workflows/megalinter.yml)
[![Scorecard supply-chain security](https://github.com/wesley-dean/bashdeps/actions/workflows/scorecard.yml/badge.svg)](https://github.com/wesley-dean/bashdeps/actions/workflows/scorecard.yml)
[![Tests](https://github.com/wesley-dean/bashdeps/actions/workflows/test.yml/badge.svg)](https://github.com/wesley-dean/bashdeps/actions/workflows/test.yml)
[![Documentation](https://github.com/wesley-dean/bashdeps/actions/workflows/static.yml/badge.svg)](https://github.com/wesley-dean/bashdeps/actions/workflows/static.yml)

`bashdeps` is a small Bash tool for downloading, verifying, and materializing
exact external artifacts declared by a repository.  The runtime executable is
named `bashdeps.bash`.

The repository also ships `manifest-manager.bash`, a separate maintainer-side CLI
for inspecting and preparing deliberate changes to bashdeps manifest declarations.
The two executables share repository governance and release versions, but they
retain separate runtime responsibilities and source closures.

Bashdeps is designed for projects that need a few pinned files without adopting a
package manager or repeating download and checksum logic in every Makefile.

A dependency can be a Bash library, script, template, data file, image, generated
input, or another ordinary file.  Bashdeps does not infer what the file means or
whether it should be executable.  It verifies bytes and places them where the
repository declares.

## Why

A filename does not prove which bytes are present.

The failure that motivated this project appeared in `adrctl`: a cached `mktext`
artifact could remain at an expected vendor path after the desired version
changed, allowing surrounding build metadata to describe one version while the
actual embedded bytes belonged to another.

Bashdeps treats the committed SHA-256 digest as the authority for acceptable
bytes.  Existing files are hashed before reuse, downloaded candidates are hashed
before publication, and successful synchronization ends by hashing final
destinations again.

`manifest-manager.bash` does not weaken that boundary.  Its `list` command can
inspect validated complete identities without changing source.  Its `add` command
can append one complete declaration supplied explicitly by the maintainer without
acquiring or trusting remote bytes.  Its `remove` command can delete one exact
logical dependency record while preserving comments, blank lines, and every other
source byte.  Its `update` command can discover a proposed GitHub release,
retrieve candidate bytes, calculate a proposed digest, and update manifest source
surgically.  Resulting source changes remain subject to normal review and commit
before `bashdeps.bash` later treats them as approved input.

## Requirements

### bashdeps.bash

Runtime requirements are capability-based rather than distribution-based:

- Bash 4.3 or newer;
- `curl` or a usable HTTPS-capable `wget` when download is required;
- `sha256sum` or `shasum -a 256`;
- ordinary Unix-like filesystem utilities used for staging and publication.

Downloader preference is:

```text
curl -> wget -> failure
```

Version 1 considers a `wget` fallback usable only when its help surface advertises
both `-T` timeout control and `-t` tries control.  The adapter uses `-T 120 -t 1`
so one Wget invocation represents one bounded bashdeps acquisition attempt.  A
minimal BusyBox build that lacks those controls is rejected rather than used with
weaker network bounds.  See ADR-012 for the rationale and compatibility boundary.

SHA-256 command preference is:

```text
sha256sum -> shasum -a 256 -> failure
```

A downloader is not needed for `verify` or when `install`/`sync` find that all
required bytes already match.

### manifest-manager.bash

The manifest manager requires Bash 4.3 or newer and ordinary Unix-like filesystem
utilities used for staging and publication.  Additional capabilities are
command-specific:

- `list`, `add`, and `remove` require no network client or SHA-256 command;
- `update` requires `curl` and `sha256sum` or `shasum -a 256` when release
  discovery, artifact retrieval, or hashing is required.

It does not require the GitHub CLI (`gh`), `jq`, Git, Python, or `bashdeps.bash`.
An omitted update version is resolved through GitHub's canonical
`OWNER/REPO/releases/latest` redirect rather than through the GitHub JSON API.

## Manifest

The conventional manifest filename is `dependencies.txt`.

Each dependency is one logical record using named fields.  The compact one-line
form remains valid:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

For readability, the same logical record may use explicit trailing continuation
markers:

```text
id=wesley-dean/mktext@0.0.7 \
  url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash \
  dest=vendor/mktext.bash \
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

Those two forms mean exactly the same thing.

A standalone `\` at the end of a physical content line means that the very next
physical line continues the same logical record.  The marker is removed, leading
horizontal whitespace on the next line is ignored for presentation, and the two
fragments are joined with one ASCII space before normal field parsing.

Indentation by itself has no semantic meaning.  This avoids accidental whitespace
changes joining records that the author did not explicitly continue.

The continuation marker must be the final character before the newline and must
be separated from the preceding field text by horizontal whitespace.  Trailing
spaces after `\` are invalid.

Blank lines and full-line comments are ignored outside a continuation.  After a
trailing continuation marker, however, the next physical line must contain record
content.  A blank line, comment line, or end of file at that point makes the
manifest invalid.

The `\` marker is only a bashdeps manifest convention.  It does not introduce
Bash escaping, quoting, expansion, or evaluation semantics.

Inline comments are not supported.

The required fields are:

```text
id=
url=
dest=
digest=
```

Field order is irrelevant, including across continued physical lines.  `id=` does
not have to be the first field.

After folding, records are split on horizontal whitespace into field tokens.  Each
field token is then split only at its first `=`.  Additional equals signs remain
part of the value, so URLs such as this are unambiguous:

```text
url=https://example.test/download?first=1&second=2
```

Values cannot contain literal spaces or tabs in version 1.

Unknown fields fail closed.  This makes the named-field format extensible without
allowing an older bashdeps version to silently ignore newer semantics.  A future
field such as `mode=0775` can therefore be introduced deliberately without
changing the basic record shape.

See ADR-015 for the physical-line folding rules and why bashdeps retains its named
field grammar instead of adopting indentation-sensitive or INI-style syntax.

### Identity

`id` is opaque metadata to `bashdeps.bash`.  The recommended convention is:

```text
PACKAGE@VERSION
```

Bashdeps does not perform semantic-version resolution.

The manifest manager preserves that opacity for `list` output, explicit `add`
input, and exact `remove` selection.  The `update` command interprets only the
narrower GitHub-oriented identity shape it needs for release maintenance.  None
of these behaviors changes runtime manifest semantics.

### URL

Version 1 accepts HTTPS URLs only.

### Destination

`dest` is the complete project-relative destination path.  It is interpreted
relative to the physical current working directory from which bashdeps is invoked.
Bashdeps does not discover a Git repository root and does not make destinations
relative to the manifest file.

By default, destinations must be strictly beneath:

```text
vendor/
```

For example:

```text
dest=vendor/mktext.bash
dest=vendor/templates/report.tmpl
```

The default policy rejects arbitrary project paths such as `Makefile`,
`.github/workflows/build.yml`, `src/generated.bash`, and paths that merely share
the textual prefix such as `vendor-old/item`.

Projects with a legitimate alternate dependency tree may select one explicitly
for the invocation:

```bash
bashdeps.bash sync --dest-root assets dependencies.txt
```

A corresponding manifest still declares the complete destination:

```text
dest=assets/logo.png
```

`--dest-root` is a containment policy only.  It does not prepend, rewrite, or
relocate `dest`.  Therefore `--dest-root assets` with `dest=vendor/tool.bash` is
rejected rather than producing `assets/vendor/tool.bash`.

A trailing slash on the option is harmless: `--dest-root vendor` and
`--dest-root vendor/` are equivalent.

Absolute paths, traversal components, textual aliases such as `./path`, repeated
separators, and existing symbolic-link path components are rejected.  The
selected destination root remains subject to the same project-relative and
symlink-safety rules.

Missing destination directories are created automatically when publication is
required.  For `sync`, directory creation occurs only after all required
candidates have been downloaded and SHA-256 verified successfully.

See ADR-013 for the destination-root security boundary and rationale.

### Digest

Every dependency requires:

```text
digest=sha256:<64 lowercase hexadecimal characters>
```

The upstream project does not need to publish a checksum.  A consuming repository
can calculate the SHA-256 digest of the exact artifact it reviewed and commit that
digest itself.

When upstream does publish a SHA-256 checksum, that published value can be used as
the committed `digest=` value.  Bashdeps still compares the downloaded bytes with
the committed digest; it does not dynamically replace the trusted digest from a
live upstream checksum during synchronization.

## Usage

### Install one artifact

```bash
bashdeps.bash install \
  id=wesley-dean/mktext@0.0.7 \
  url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash \
  dest=vendor/mktext.bash \
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

For an alternate destination root:

```bash
bashdeps.bash install --dest-root assets \
  id=example@1 \
  url=https://example.test/item.dat \
  dest=assets/item.dat \
  digest=sha256:...
```

A manifest record deliberately resembles the field list passed to `install`.
Manifest continuation is separate from Bash command continuation: when a shell
command uses its own `\`-newline syntax, the shell processes that before bashdeps
receives argv.  Bashdeps applies ADR-015 folding only while reading manifest
files.  For example:

```bash
bashdeps.bash install \
  id=example@1 \
  'url=https://example.test/file?first=1&second=2' \
  dest=vendor/example.dat \
  digest=sha256:...
```

If the destination already contains the approved bytes, `install` returns without
downloading or replacing it.

### Synchronize a manifest

```bash
bashdeps.bash sync
```

This uses `dependencies.txt` and the default destination root `vendor`.

An alternate manifest can be supplied explicitly:

```bash
bashdeps.bash sync path/to/dependencies.txt
```

An alternate destination root is explicit invocation policy:

```bash
bashdeps.bash sync --dest-root assets path/to/dependencies.txt
```

`sync` validates the complete manifest, identifies missing or mismatched
artifacts, acquires and verifies every required candidate, and only then begins
intentional publication.

It does not literally invoke `install` once per logical record because doing so
would lose whole-manifest preflight.

Bashdeps does not prune undeclared files.

### Verify existing state

```bash
bashdeps.bash verify
```

or:

```bash
bashdeps.bash verify path/to/dependencies.txt
bashdeps.bash verify --dest-root assets path/to/dependencies.txt
```

`verify` performs no network access and no intentional filesystem mutation.  It
succeeds only when every declared destination exists within the selected
destination root and has the approved bytes.  Extra undeclared files are ignored.

## Manifest Manager

`manifest-manager.bash` provides conservative maintainer operations over manifest
source without making the runtime synchronizer responsible for release discovery
or trust changes.

### List dependency identities

List complete validated identity values from the default manifest:

```bash
manifest-manager.bash list
```

Use an alternate manifest or read a manifest from standard input:

```bash
manifest-manager.bash list --filename dependencies-docs.txt
manifest-manager.bash list -f - <dependencies.txt
```

`list` validates the complete manifest before writing output, then emits each full
logical `id` value on its own line in manifest order.  It does not strip version
text or reinterpret the identity as a GitHub package name.  A valid empty manifest
produces no output and succeeds.

`list -f -` is read-only stream input.  On failure it does not echo the original
manifest to STDOUT; STDOUT belongs to list data.  This differs deliberately from
the transactional rollback contract used by mutating stream commands.

### Add a declaration

Append one complete dependency declaration supplied explicitly by the maintainer:

```bash
manifest-manager.bash add \
  id=acme/tool@v1 \
  url=https://example.test/tool \
  dest=vendor/tool \
  digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

All four named fields are mandatory, although their argument order is arbitrary.
`add` does not infer a repository convention, artifact URL or filename,
destination, or digest.  It performs no network access and does not calculate a
digest from remote bytes.

The existing manifest is validated before append.  Duplicate identities and
destinations fail.  Existing bytes remain an exact prefix of the candidate, and
only the new record is serialized canonically as one line in `id`, `url`, `dest`,
`digest` order.  The new record is appended at absolute EOF after any existing
comments or blank lines.

The last observed LF or CRLF line-ending style is reused.  LF is used when no
line-ending style exists.  If a non-empty manifest lacks a final line terminator,
one selected separator is inserted before the new record.  The new record always
ends with the selected line terminator.

### Remove a declaration

Remove one dependency by its exact complete `id=` value:

```bash
manifest-manager.bash remove acme/tool@v1
```

An alternate manifest may be selected explicitly:

```bash
manifest-manager.bash remove \
  --filename dependencies-docs.txt \
  acme/filter@v2
```

`remove` treats the identity as opaque data.  It does not strip version text or
interpret the argument as a GitHub package prefix.  Zero exact matches fail, and
duplicate identities are rejected as invalid manifest state before mutation.

A successful removal deletes only the selected logical record's physical source
chunk.  Continued records lose all physical continuation lines that belong to the
record.  Adjacent comments and blank lines remain unchanged because the manifest
grammar does not assign them to a dependency.  No separator, line ending, or
cleanup whitespace is inserted after deletion.

The candidate is proved to equal the original ordered source chunks with exactly
one selected record omitted, then the complete candidate is reparsed before
publication.  `remove` requires no network access or digest calculation.

### Update existing declarations

Update one dependency to the repository's GitHub latest release:

```bash
manifest-manager.bash update wesley-dean/bash-doxygen
```

Update to an explicit tag exactly as supplied:

```bash
manifest-manager.bash update wesley-dean/bash-doxygen v0.0.14
manifest-manager.bash update wesley-dean/bash-doxygen@v0.0.14
```

The literal tag `latest` is not special when supplied explicitly.  Omitting the
version is what requests GitHub's canonical latest release.

Update an alternate manifest:

```bash
manifest-manager.bash update \
  --filename dependencies-docs.txt \
  wesley-dean/bash-doxygen
```

Attempt a whole-manifest update transaction:

```bash
manifest-manager.bash update --all
```

`--all` does not silently skip commit-pinned or unsupported declarations.  If any
dependency cannot be updated safely, the entire manifest update fails.

### Transactional mutation stdin/stdout mode

For `update`, `add`, and `remove`, a filename of `-` reads the complete manifest
from standard input and writes one complete manifest representation to standard
output.  For example:

```bash
manifest-manager.bash remove -f - acme/tool@v1 \
  <dependencies.txt \
  >dependencies.new.txt
```

After the complete input has been captured:

```text
success -> stdout is the complete mutated manifest, status 0
failure -> stdout is the complete original manifest, nonzero status
```

Diagnostics go to standard error.  Callers must inspect the exit status rather
than treating the presence of output as proof that a mutation succeeded.

### Surgical source preservation

The manager parses a logical view for validation and dependency selection, but it
does not regenerate existing manifest source from parsed fields.

For `update`, it retains raw record bytes and changes only the intended `id`,
`url`, and `digest` values for selected records.  `dest` is never changed by
`update`.

For `add`, every pre-existing byte remains unchanged and the complete original is
an exact prefix of the candidate.  Only the newly appended record and any required
separator line ending are newly serialized.

For `remove`, comments and blank lines remain independent chunks and the candidate
contains every original chunk except exactly one selected record chunk.  No
surviving byte is normalized or reformatted.

Successful manager mutations use operation-specific preservation proofs before
publication.  File-mode publication is staged and occurs only after the complete
requested operation has succeeded.

The current update command supports unambiguous GitHub raw-content and
release-download URL forms.  It fails rather than guessing when the existing URL,
identity, or artifact relationship cannot be established safely.  `add` likewise
fails rather than inventing missing declaration data, and `remove` requires an
exact complete identity instead of inferring package semantics.

ADR-021 governs the complete `list`, `add`, and `remove` command set.

See [Manifest Manager Behavior Specification](doc/manifest-manager-spec.md),
ADR-020, and ADR-021 for the complete contracts and rationale.

## File Modes

Newly materialized artifacts use mode `0644`.

Bashdeps does not infer executability from filenames, extensions, shebangs, URLs,
identities, or file contents.

An already-correct file is accepted by digest and is not chmodded merely to
normalize its mode.  `verify` ignores mode entirely.

## Exit Statuses

The `bashdeps.bash` public exit status contract is:

```text
0  success, help, or version output
1  verify completed but one or more destinations are absent or mismatched
2  invalid CLI usage, invalid manifest, or invalid declaration
3  required runtime capability is unavailable or unusable
4  network acquisition failed
5  acquired candidate bytes do not match the approved digest
6  filesystem safety, staging, or publication failed
```

The `manifest-manager.bash` public exit categories are:

```text
0  success, help, version, or successful no-op
2  invalid CLI, manifest, dependency selection, or declaration
3  required runtime capability unavailable or unusable
4  latest-release discovery or network acquisition failed
5  exact-mutation or preservation safety check failed
6  input, staging, filesystem, output, or publication failed
```

Commands use only relevant categories.  `list` normally uses 0, 2, and 6; `add`
and `remove` normally use 0, 2, 5, and 6.  These commands require no network or
hashing capabilities.

A malformed or unterminated continuation is status 2, including a blank/comment
line where a trailing `\` requires immediate continued record content.

An invalid `--dest-root` value or a destination outside the selected root is
status 2 for `bashdeps.bash` because it is invalid invocation/declaration policy
rather than a publication failure.

Diagnostics are written to standard error.  Successful `install`, `sync`, and
`verify` operations normally produce no standard output.  Successful manager
mutation file operations are likewise quiet; mutation stream mode reserves
standard output for the manifest, while `list` reserves it for identity values.

## Trust Boundary

SHA-256 equality means the local bytes match the digest committed by the consuming
project.  It does not prove that upstream software is safe, correctly labeled,
free from vulnerabilities, or worthy of trust.

The manifest itself is trusted source code.  A change that modifies both a URL
and its approved digest intentionally changes which bytes the repository trusts
and should receive the same review attention as other supply-chain-sensitive
source changes.

The manifest manager prepares such a source change but does not authorize it for
runtime use.  Review and commit remain the trust boundary consumed later by
`bashdeps.bash`.

The default `vendor/` destination root limits where an ordinary manifest may
materialize those trusted bytes.  A Makefile or CI change that supplies
`--dest-root` changes that security policy and should also be review-worthy.

Manifest contents are never sourced or evaluated as shell code.

## Consumer Make Integration

A project needs a small bootstrap path for bashdeps itself.  That bootstrap
belongs in the consuming Makefile, outside `dependencies.txt`, because bashdeps
cannot use its own manifest until the executable already exists.

A typical layout is:

```text
Makefile
  -> directly bootstrap and verify vendor/bashdeps.bash
  -> make deps
       -> vendor/bashdeps.bash sync dependencies.txt
            -> vendor/mktext.bash
            -> vendor/doxygen-bash.awk
```

The consuming Makefile pins the bashdeps release URL and SHA-256 digest, verifies
candidate bytes before publishing `vendor/bashdeps.bash`, and verifies the cached
bootstrap artifact again before using it.  The manifest then owns ordinary
project dependencies such as `mktext` and the Doxygen filter.

The following excerpt shows the relevant boundary.  Replace the placeholder
version and digest with the exact bashdeps release selected by the consuming
repository.  This example uses `sha256sum`; a consumer that standardizes on
`shasum -a 256` can use the equivalent verification command.

```make
BASHDEPS_VERSION := <version>
BASHDEPS := vendor/bashdeps.bash
BASHDEPS_URL := https://github.com/wesley-dean/bashdeps/releases/download/v$(BASHDEPS_VERSION)/bashdeps.bash
BASHDEPS_SHA256 := <64-lowercase-hex-digest>

.PHONY: deps deps-check FORCE verify-bashdeps

FORCE:

$(BASHDEPS): FORCE
	@mkdir -p "$(dir $@)"
	@if [[ -f "$@" ]] && \
		printf '%s  %s\n' "$(BASHDEPS_SHA256)" "$@" | sha256sum -c - >/dev/null 2>&1; then \
		chmod 0755 "$@"; \
		exit 0; \
	fi; \
	tmp="$@.tmp"; \
	trap 'rm -f "$$tmp"' EXIT; \
	curl -fsSL "$(BASHDEPS_URL)" -o "$$tmp"; \
	printf '%s  %s\n' "$(BASHDEPS_SHA256)" "$$tmp" | sha256sum -c - >/dev/null; \
	chmod 0755 "$$tmp"; \
	mv "$$tmp" "$@"; \
	trap - EXIT

verify-bashdeps:
	test -x "$(BASHDEPS)"
	printf '%s  %s\n' "$(BASHDEPS_SHA256)" "$(BASHDEPS)" | sha256sum -c - >/dev/null

deps: $(BASHDEPS) dependencies.txt
	$(MAKE) --no-print-directory verify-bashdeps
	"$(BASHDEPS)" sync dependencies.txt

deps-check: verify-bashdeps dependencies.txt
	"$(BASHDEPS)" verify dependencies.txt
```

The forced bootstrap target validates cached bytes every time `deps` is requested.
Correct bytes are reused without network access.  Missing or mismatched bytes are
downloaded to staging, verified, and only then published at the bootstrap path.

`deps-check` deliberately has no dependency on `$(BASHDEPS)`, so a missing or
invalid bootstrap executable causes the check to fail rather than reaching the
network or repairing state.

The recommended target boundary is therefore:

```text
make deps        bootstrap/verify bashdeps if needed, then sync dependencies.txt
make deps-check  verify existing bashdeps, then verify dependencies.txt offline
make build       build only from current local inputs
make all         deps, then build
```

A project using a non-default dependency tree should make that policy visible in
its Makefile, for example:

```text
vendor/bashdeps.bash sync --dest-root third_party dependencies.txt
```

### Multiple dependency manifests

A consuming project may select different manifest files for different repository
operations, such as build, documentation, or test dependencies.  This keeps
artifact purpose in the consuming Makefile rather than adding dependency-type
metadata to the bashdeps record grammar.

For example, a project can use `dependencies.txt` for build inputs and
`dependencies-docs.txt` for documentation-only tools, with corresponding
`deps`/`deps-check` and `deps-docs`/`deps-docs-check` targets.  Projects with no
ordinary build dependencies can keep `deps` as an explicit no-op while preparing
role-specific dependencies only when those operations are requested.

See [Multiple Dependency Manifests](doc/multiple-dependency-manifests.md) for
complete Make examples, network/check boundaries, empty-build-dependency patterns,
and cross-manifest destination considerations.

## Self-Hosting in This Repository

The bashdeps source repository follows the same architecture without asking the
unreleased source tree to bootstrap itself:

```text
bashdeps source tree
  -> Make bootstraps and verifies released vendor/bashdeps.bash
  -> released vendor/bashdeps.bash syncs dependencies.txt
       -> vendor/doxygen-bash.awk
       -> vendor/bash-minifier.bash
  -> source tree builds/tests the next bashdeps and manifest-manager revision
```

The Makefile currently pins released bashdeps v0.0.6 as the bootstrap tool.  The
bootstrap is intentionally excluded from `dependencies.txt`.

The manifest currently manages two external development/build artifacts:

- `bash-doxygen` v0.0.6 for reference documentation; and
- Bash-Minifier at commit `9c824e20815a5bca2153ec25ecc02a4edea1430e`
  for the minified release flavor.

The Bash-Minifier upstream file is `Minify.sh`; bashdeps materializes the reviewed
bytes at `vendor/bash-minifier.bash`.  The build invokes that managed file through
`bash`, so dependency mode remains owned by bashdeps rather than inferred from its
purpose.

A clean `make build` fails clearly until `vendor/bash-minifier.bash` has been
prepared.  It does not download or repair the missing dependency.  `make all`
explicitly runs dependency synchronization first and then builds both executable
families, while `make deps-check` verifies existing bootstrap and manifest state
without network repair.

See ADR-017 for the self-hosting and dependency-management architecture, ADR-018
for the build-input and three-flavor release decisions, and ADR-020 for the
second-product release model.

## Build and Release Artifacts

Maintained product source lives at:

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

The build uses explicit source inventories for each executable.  Code needed only
by `manifest-manager.bash` is not incorporated into `bashdeps.bash`, and
bashdeps-only runtime code is not incorporated into the manager.  A component may
become shared only when both products genuinely require it.

After dependencies have been prepared, `make build` generates exactly twelve
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

For each product, the `.dev.bash` artifact is the complete assembled developer
artifact and retains source/documentation comments.  The ordinary `.bash` artifact
is derived from the complete developer artifact by removing full-line comments
while retaining the shebang.  The `.min.bash` artifact is derived from the
completed comment-stripped artifact through the commit-pinned Bash-Minifier
dependency.

All six Bash artifacts are executable.  Each family exposes the same observable
CLI behavior across its source, developer, ordinary, and minified representations.
Each artifact has one checksum companion whose filename is the artifact name plus
`.sha256`.

The checksum file uses conventional checksum-tool syntax, so from `dist/` the
ordinary runtime artifact can be verified with:

```bash
sha256sum -c bashdeps.bash.sha256
```

and the ordinary manifest-manager artifact with:

```bash
sha256sum -c manifest-manager.bash.sha256
```

or the supported `shasum` equivalent.

New releases publish only `.sha256` checksum companions.  Historical releases
that published `.256` companions remain unchanged.  A tool that explicitly
retrieves release checksum sidecars may try `.256` only when the preferred
`.sha256` asset is confirmed absent; transport, authorization, server,
malformed-content, and checksum-mismatch failures should fail rather than trigger
a legacy fallback.

That compatibility rule does not change bashdeps' trust model.  `bashdeps.bash`
continues to accept dependency bytes only when they match the SHA-256 digest
committed in the consuming repository; it does not dynamically replace that
trusted digest with a live `.sha256` or `.256` sidecar.

This project does not generate an aggregate `SHA256SUMS` file.

The public behavior suites are run against maintained source and all three
generated representations for their respective products.  Minified artifacts are
accepted only when syntax, Bash 4.3 compatibility, checksum, and public behavior
tests pass.

The build consumes `vendor/bash-minifier.bash`, but released executables remain
independent of `dependencies.txt`, `vendor/bashdeps.bash`,
`vendor/bash-minifier.bash`, and `vendor/doxygen-bash.awk` at runtime.

See ADR-019 for checksum companion naming and ADR-020 for the two-product release
and source-closure contract.

## Development

The project follows documentation-driven, test-second development.  Maintained
Bash source follows ADR-014.  New manifest-manager source follows the revised
repository standard in `doc/documentation-standard.md`; existing scripts will be
backported to that revised standard separately rather than as part of issue #17.

Common targets are:

```bash
make all
make deps
make deps-check
make build
make check
make format
make test
make test-source
make test-dev
make test-dist
make test-min
make test-build-deps
make docs
make docs-clean
make clean
make distclean
```

`make deps` may use the network to bootstrap the pinned released bashdeps tool and
synchronize `dependencies.txt`.  `make deps-check` is the offline, non-repairing
verification path.  `make build` remains network-free and does not acquire or
verify dependencies, but it requires the already-prepared
`vendor/bash-minifier.bash` build input.  Use `make all` for a fresh checkout or
run `make deps` before `make build`.

Bats is the primary behavior-test framework.  Ordinary tests use controlled local
fixtures rather than live public network services.  Both executable families are
tested independently against maintained source and every generated release
representation.

### Generate reference documentation

Doxygen reference documentation is generated from the maintained Bash product
source with:

```bash
make docs
```

Local documentation generation requires Doxygen.  `make docs` prepares the
manifest-managed `vendor/doxygen-bash.awk` through `make deps`, applies the
executable mode required by Doxygen, and writes the generated site under
`doc/reference/`.

The released bootstrap, manifest-managed Bash-Minifier and Doxygen filter, and
generated reference directory are generated state ignored by Git.  Use
`make docs-clean` to remove only generated reference documentation or
`make distclean` to remove normal build output, reference documentation, and the
complete generated `vendor/` tree.

Generated Doxygen output is not committed to this repository.  On pushes to
`main`, `.github/workflows/static.yml` installs Doxygen, runs the same `make docs`
target, verifies synchronized dependency state, and publishes `doc/reference/` to
GitHub Pages at:

```text
https://wesley-dean.github.io/bashdeps/
```

See ADR-016 for the Pages generation/publication decision and ADR-017 for the
superseding dependency-acquisition boundary.

## Architecture

Architecture Decision Records are stored in `doc/adr/`.

The normative behavior specifications are:

```text
doc/bashdeps-spec.md
doc/manifest-manager-spec.md
```

AI-assisted contributors should review `AGENTS.md` before substantive changes.

## Public Interface

The supported public interfaces are the `bashdeps.bash` and
`manifest-manager.bash` executable CLIs.

Neither product provides a supported sourceable library API.  Private
`__bashdeps_*` and `__manifest_manager_*` functions are implementation details.

## License

See [LICENSE](LICENSE).

## Contributing

Contributions are welcome.  Please read [CONTRIBUTING.md](CONTRIBUTING.md) and
follow the documented architecture and public behavior contracts.
