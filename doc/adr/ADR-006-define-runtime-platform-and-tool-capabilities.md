# ADR-006: Define Runtime Platform and Tool Capabilities

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the minimum runtime capabilities required by `bashdeps` without
claiming support based only on operating-system or distribution names.

## Context

`bashdeps` is implemented in Bash but intentionally performs operations that Bash
cannot provide portably by itself: HTTPS retrieval and SHA-256 calculation.

The project originally considered requiring `curl` and `sha256sum`.  Portability
review identified lean Linux environments, including BusyBox-oriented systems,
where `wget` may be available while `curl` is absent.  Similar differences exist
for SHA-256 utilities across GNU/Linux and other Unix-like systems.

The architecture should therefore describe required capabilities and select among
supported implementations at runtime rather than infer capability from platform
identity.

## Decision Drivers

- Preserve compatibility with lean Linux and BusyBox-oriented environments.
- Avoid unnecessary runtime dependencies when equivalent supported capabilities
  are already present.
- Keep platform claims evidence-based rather than distribution-name-based.
- Keep implementation and testing scope bounded to explicitly supported command
  families.
- Preserve one stable internal contract for download and hashing operations.

## Decision

`bashdeps` SHALL require Bash 4.3 or newer.

Version 1 SHALL require these runtime capabilities:

1. an HTTPS-capable downloader implemented by either `curl` or `wget`;
2. a SHA-256 implementation provided by either `sha256sum` or `shasum` with
   SHA-256 selection support;
3. ordinary POSIX-like filesystem behavior sufficient for files, directories,
   temporary staging, and rename-style publication.

Runtime capability selection SHALL prefer implementations in this order:

```text
download: curl -> wget -> fail
sha256:   sha256sum -> shasum -a 256 -> fail
```

The exact executable path SHALL be discovered at runtime with command lookup
rather than hard-coded distribution assumptions.

The existence of an executable name alone does not prove every optional feature
is available.  Backend adapters SHALL use only behavior they can establish or
shall fail accurately when a required capability cannot be provided.

`bashdeps` SHALL NOT claim support for an operating system solely because the
operating system commonly ships one of these tools.  Documentation may identify
known compatible environments after they are tested, but the normative contract
remains capability-based.

No Python, Perl, Ruby, Node.js, `jq`, YAML parser, JSON parser, package manager,
or Git client SHALL be required for ordinary runtime operation.

Git MAY be used by the build system to derive release metadata when available,
but generated consumer artifacts SHALL NOT require Git at runtime.

## Considered Alternatives

### Require GNU/Linux utilities

This would simplify command selection but would exclude BusyBox-oriented and
other Unix-like environments without a demonstrated need.

### Require curl and sha256sum only

This provides the narrowest implementation, but it creates avoidable installation
requirements on environments that already provide usable `wget` or `shasum`
capabilities.

### Support arbitrary downloader and hashing commands through configuration

This would maximize flexibility but would move command-line construction and
security semantics into configuration.  Version 1 instead supports a small,
tested adapter set.

### Detect the operating system and choose commands from a platform table

Distribution identity is an unreliable proxy for installed capabilities and is
especially weak for containers, embedded systems, and custom BusyBox builds.
Runtime command capability detection is more direct.

## Consequences

The implementation will contain small adapter layers for download and SHA-256
operations.

Tests should exercise each supported adapter where the corresponding tool is
available and should also exercise the explicit no-supported-backend failure
path.

Compatibility documentation can expand over time without changing the core
architecture so long as new environments satisfy the documented capabilities.

## Open Questions and Follow-Ups

Future evidence may justify additional downloader or digest-command adapters.
Those additions should preserve the same backend-independent contracts rather
than leak tool-specific behavior into synchronization logic.

## Related Decisions

- Related to: ADR-001
- Related to: ADR-004
- Related to: ADR-005
