# bashdeps

`bashdeps` is a small Bash tool for downloading, verifying, and materializing
exact external artifacts declared by a repository.

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

Each dependency occupies one line and uses named fields:

```text
id=wesley-dean/mktext@0.0.7 url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash dest=vendor/mktext.bash digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

The required fields are:

```text
id=
url=
dest=
digest=
```

Field order is irrelevant.

Records are split on horizontal whitespace into field tokens.  Each field token
is then split only at its first `=`.  Additional equals signs remain part of the
value, so URLs such as this are unambiguous:

```text
url=https://example.test/download?first=1&second=2
```

Values cannot contain literal spaces or tabs in version 1.

Blank lines and full-line comments are ignored:

```text
# Rendering dependency
id=wesley-dean/mktext@0.0.7 url=https://example.test/mktext.bash dest=vendor/mktext.bash digest=sha256:...
```

Inline comments are not supported.

Unknown fields fail closed.  This makes the named-field format extensible without
allowing an older bashdeps version to silently ignore newer semantics.  A future
field such as `mode=0775` can therefore be introduced deliberately without
changing the basic record shape.

### Identity

`id` is opaque metadata to bashdeps.  The recommended convention is:

```text
PACKAGE@VERSION
```

Bashdeps does not perform semantic-version resolution.

### URL

Version 1 accepts HTTPS URLs only.

### Destination

`dest` is relative to the physical current working directory from which bashdeps
is invoked.  Bashdeps does not discover a Git repository root and does not make
destinations relative to the manifest file.

Absolute paths, traversal components, textual aliases such as `./path`, and
existing symbolic-link path components are rejected.

### Digest

Every dependency requires:

```text
digest=sha256:<64 lowercase hexadecimal characters>
```

The upstream project does not need to publish a checksum.  A consuming repository
can calculate the SHA-256 digest of the exact artifact it reviewed and commit that
digest itself.

## Usage

### Install one artifact

```bash
bashdeps install \
  id=wesley-dean/mktext@0.0.7 \
  url=https://github.com/wesley-dean/mktext/releases/download/v0.0.7/mktext.bash \
  dest=vendor/mktext.bash \
  digest=sha256:213cee4663512954f486c8a6ff00ddd36a9b4c48ceb3e9b71d9ec70a36c1e0dd
```

A manifest record deliberately resembles the field list passed to `install`.
When an interactive shell would interpret characters inside a value, quote that
argument normally.  For example:

```bash
bashdeps install \
  id=example@1 \
  'url=https://example.test/file?first=1&second=2' \
  dest=vendor/example.dat \
  digest=sha256:...
```

If the destination already contains the approved bytes, `install` returns without
downloading or replacing it.

### Synchronize a manifest

```bash
bashdeps sync
```

This uses `dependencies.txt` by default.

An alternate manifest can be supplied explicitly:

```bash
bashdeps sync path/to/dependencies.txt
```

`sync` validates the complete manifest, identifies missing or mismatched
artifacts, acquires and verifies every required candidate, and only then begins
intentional publication.

It does not literally invoke `install` once per line because doing so would lose
whole-manifest preflight.

Bashdeps does not prune undeclared files.

### Verify existing state

```bash
bashdeps verify
```

or:

```bash
bashdeps verify path/to/dependencies.txt
```

`verify` performs no network access and no intentional filesystem mutation.  It
succeeds only when every declared destination exists and has the approved bytes.
Extra undeclared files are ignored.

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
make deps        bootstrap bashdeps if needed, then bashdeps sync
make deps-check  bashdeps verify using an already-present bootstrap artifact
make build       build only from current local inputs
make all         deps, then build
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
dist/bashdeps.bash
dist/SHA256SUMS
```

`bashdeps.dev.bash` retains source comments.

`bashdeps.bash` is the normal consumer artifact and removes full-line source
comments while preserving executable behavior.

This project does not generate a minified artifact.

The same public behavior suite is run against maintained source and both generated
Bash artifacts.

## Development

The project follows documentation-driven, test-second development.

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

The supported public interface is the executable CLI.

Bashdeps does not provide a supported sourceable library API in version 1.
Private `__bashdeps_*` functions are implementation details.

## License

See [LICENSE](LICENSE).

## Contributing

Contributions are welcome.  Please read [CONTRIBUTING.md](CONTRIBUTING.md) and
follow the documented architecture and public behavior contract.
