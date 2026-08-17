# ADR-010: Define Development and Testing Workflow

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the development orchestration and test strategy used to verify
bashdeps' public behavior and generated artifacts.

## Context

Bashdeps manipulates supply-chain inputs and filesystem state.  Tests therefore
need to cover more than happy-path command dispatch: parser strictness, digest
identity, downloader selection, offline verification, staging, failure before
publication, path safety, and generated artifact equivalence are all observable
contracts.

The project follows the same documentation-driven, test-second discipline used by
mktext: architecture and public behavior are documented first, implementation
realizes that behavior, and automated tests verify the resulting contract.

## Decision Drivers

- Test public behavior rather than private helper structure where practical.
- Run the same behavior suite against every shipped Bash artifact.
- Keep ordinary test runs deterministic and independent of public network access.
- Exercise downloader and hashing adapters without requiring every host to have
  every supported implementation installed.
- Make build, static checking, formatting, and behavior testing explicit Make
  operations.
- Keep generated artifacts from becoming untested secondary implementations.

## Decision

Make SHALL be the canonical development orchestration interface.

The project SHALL provide at least these targets:

```text
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

`make all` SHALL perform `build` only.  It SHALL NOT implicitly run static
analysis or behavior tests.

`make test` SHALL run the public behavior suite against:

1. `src/bashdeps.bash`;
2. `dist/bashdeps.dev.bash`;
3. `dist/bashdeps.bash`.

Generated-artifact tests SHALL depend on `make build` and SHALL additionally
verify expected artifact properties such as shebang, executable mode, embedded
metadata, and checksum-file consistency.

Bats SHALL be the primary behavior-test framework.

### Test isolation

Ordinary behavior tests SHALL NOT depend on live public network services.

Tests SHALL use temporary project directories and controlled fixture bytes.
Downloader behavior SHOULD be exercised through PATH-injected fake `curl` and
`wget` commands that record arguments and produce deterministic fixture output.
This allows tests to verify backend selection, fallback, failure mapping, and
staging behavior independent of the host's installed tools.

Hash-backend selection SHOULD likewise be testable with PATH-controlled fixtures
or narrowly scoped adapter tests.

The test suite SHALL include cases for:

- blank lines and full-line manifest comments;
- named-field order independence;
- splitting each field at the first `=` only;
- URLs containing additional `=` characters;
- duplicate, missing, and unknown fields;
- duplicate identities and destinations;
- invalid URLs, paths, and digests;
- correct local bytes requiring no network;
- missing and mismatched local bytes requiring acquisition;
- candidate digest mismatch preventing publication;
- complete-manifest preflight before sync publication;
- verify performing no network access or mutation;
- curl preference and wget fallback;
- no supported downloader or digest backend;
- symbolic-link destination/path rejection;
- preservation of existing stale bytes when replacement acquisition fails;
- final verification after publication;
- documented exit-status categories;
- help and version behavior;
- equivalent observable behavior across source and both distribution artifacts.

### Static and syntax validation

`make check` SHALL perform Bash syntax validation on maintained executable test
helpers and source, and SHALL invoke ShellCheck for maintained shell source.

`make format` SHALL apply the repository's canonical shfmt configuration to
maintained shell source and executable test helpers.

Generated `dist/` artifacts SHALL be validated for syntax and behavior but SHALL
not be formatted or edited as maintained source.

### Regression discipline

A bug fix SHOULD include a regression test that demonstrates the formerly broken
observable behavior.

A behavioral change is normally incomplete until its governing documentation and
public tests agree.

## Considered Alternatives

### Test only src/bashdeps.bash

This would miss defects introduced by metadata injection or comment removal.
Generated artifacts are shipped products and require independent execution.

### Use live GitHub release URLs in ordinary tests

Live tests provide realism but introduce network availability, rate limits,
upstream changes, and nondeterminism.  Network-client behavior is better tested
through controlled adapters; optional integration tests can be added separately.

### Test private functions directly

Some narrow adapter tests may justify direct helper invocation, but broad testing
of helper names would freeze implementation structure unnecessarily.  Public CLI
behavior remains the primary contract.

## Consequences

The suite will contain more fixture infrastructure than a typical tiny Bash
script, but it will be able to test failure behavior deterministically without
reaching the public Internet.

Changing the internal downloader implementation remains possible as long as the
public behavior and adapter contract continue to pass.

The build transformation is continuously checked for semantic equivalence rather
than trusted by inspection alone.

## Open Questions and Follow-Ups

Optional end-to-end tests against real HTTPS services may be introduced later as
non-required CI coverage.  They SHALL NOT become the only evidence for ordinary
acquisition behavior.

## Related Decisions

- Related to: ADR-006
- Related to: ADR-007
- Related to: ADR-008
- Related to: ADR-009
