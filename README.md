# bashdeps

`bashdeps` is a small Bash tool for downloading, verifying, and materializing
exact external artifacts declared by a repository.  The distributed executable is
named `bashdeps.bash`.

It is designed for projects that need a few pinned files without adopting a
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

## Requirements

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

## Manifest

The conventional manifest filename is `dependencies.txt`.

Each dependency is one logical record using named fields.  The compact one-line
form remains valid:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

For readability, the same logical record may be folded across indented physical
lines:

```text
id=wesley-dean/mktext@0.0.7
  url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash
  dest=vendor/mktext.bash
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

Those two forms mean exactly the same thing.

A non-comment content line beginning in column 1 starts a logical record.  A
non-comment content line beginning with one or more spaces or tabs continues the
current record.  Continuation indentation is removed and the text is joined to
the logical record with one ASCII space before normal field parsing.

Conceptually:

```text
foo
  bar
  bazzle
```

becomes:

```text
foo bar bazzle
```

A continuation line with no preceding logical record is invalid rather than being
silently repaired.

Blank lines and full-line comments are ignored and do not terminate a folded
record.  This is valid:

```text
id=wesley-dean/mktext@0.0.7
  url=https://example.test/mktext.bash

  # Keep mktext under the default dependency tree.
  dest=vendor/mktext.bash
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

Inline comments are not supported.

The required fields are:

```text
id=
url=
dest=
digest=
```

Field order is irrelevant, including across folded physical lines.  `id=` does not
have to be the first physical field; any valid field may begin the logical record
in column 1.

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
field grammar instead of adopting an INI-style format.

### Identity

`id` is opaque metadata to bashdeps.  The recommended convention is:

```text
PACKAGE@VERSION
```

Bashdeps does not perform semantic-version resolution.

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
Physical-line folding applies to manifest files; interactive `install` arguments
continue to follow ordinary shell argv and quoting rules.  For example:

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

## File Modes

Newly materialized artifacts use mode `0644`.

Bashdeps does not infer executability from filenames, extensions, shebangs, URLs,
identities, or file contents.

An already-correct file is accepted by digest and is not chmodded merely to
normalize its mode.  `verify` ignores mode entirely.

## Exit Statuses

The public exit status contract is:

```text
0  success, help, or version output
1  verify completed but one or more destinations are absent or mismatched
2  invalid CLI usage, invalid manifest, or invalid declaration
3  required runtime capability is unavailable or unusable
4  network acquisition failed
5  acquired candidate bytes do not match the approved digest
6  filesystem safety, staging, or publication failed
```

An invalid folded record, including a continuation before any current logical
record, is status 2.

An invalid `--dest-root` value or a destination outside the selected root is
status 2 because it is invalid invocation/declaration policy rather than a
publication failure.

Diagnostics are written to standard error.  Successful `install`, `sync`, and
`verify` operations normally produce no standard output.

## Trust Boundary

SHA-256 equality means the local bytes match the digest committed by the consuming
project.  It does not prove that upstream software is safe, correctly labeled,
free from vulnerabilities, or worthy of trust.

The manifest itself is trusted source code.  A change that modifies both a URL
and its approved digest intentionally changes which bytes the repository trusts
and should receive the same review attention as other supply-chain-sensitive
source changes.

The default `vendor/` destination root limits where an ordinary manifest may
materialize those trusted bytes.  A Makefile or CI change that supplies
`--dest-root` changes that security policy and should also be review-worthy.

Manifest contents are never sourced or evaluated as shell code.

## Consumer Make Integration

A project still needs a small bootstrap path for bashdeps itself.  The recommended
pattern keeps the pinned bashdeps artifact outside `dependencies.txt`, for
example:

```text
.build/bashdeps.bash
```

The consuming Makefile independently pins and verifies that artifact.

The recommended target boundary is:

```text
make deps        bootstrap bashdeps.bash if needed, then bashdeps.bash sync
make deps-check  bashdeps.bash verify using an already-present bootstrap artifact
make build       build only from current local inputs
make all         deps, then build
```

A project using a non-default dependency tree should make that policy visible in
its Makefile, for example:

```text
bashdeps.bash sync --dest-root third_party dependencies.txt
```

`deps-check` should fail rather than silently download a missing bashdeps
bootstrap artifact, preserving its network-free meaning.

## Build and Release Artifacts

Maintained source lives at:

```text
src/bashdeps.bash
```

`make build` generates:

```text
dist/bashdeps.dev.bash
dist/bashdeps.dev.bash.256
dist/bashdeps.bash
dist/bashdeps.bash.256
```

`bashdeps.dev.bash` retains source comments.

`bashdeps.bash` is the normal consumer artifact and removes full-line source
comments while preserving executable behavior.

Each Bash artifact has one checksum companion whose filename is the artifact name
plus `.256`.  The checksum file uses conventional checksum-tool syntax, so from
`dist/` the normal artifact can be verified with:

```bash
sha256sum -c bashdeps.bash.256
```

or the supported `shasum` equivalent.

This project does not generate an aggregate `SHA256SUMS` file and does not
generate a minified artifact.

The same public behavior suite is run against maintained source and both generated
Bash artifacts.

## Development

The project follows documentation-driven, test-second development.  Maintained
Bash source follows the documentation-first Doxygen-style standard defined by
ADR-014 and derived from Bootstrap ADR-045.

Common targets are:

```bash
make all
make build
make check
make format
make test
make test-source
make test-dev
make test-dist
make clean
```

Bats is the primary behavior-test framework.  Ordinary tests use controlled local
fixtures rather than live public network services.

## Architecture

Architecture Decision Records are stored in `doc/adr/`.

The normative behavior specification is `doc/bashdeps-spec.md`.

AI-assisted contributors should review `AGENTS.md` before substantive changes.

## Public Interface

The supported public interface is the `bashdeps.bash` executable CLI.

Bashdeps does not provide a supported sourceable library API in version 1.
Private `__bashdeps_*` functions are implementation details.

## License

See [LICENSE](LICENSE).

## Contributing

Contributions are welcome.  Please read [CONTRIBUTING.md](CONTRIBUTING.md) and
follow the documented architecture and public behavior contract.
