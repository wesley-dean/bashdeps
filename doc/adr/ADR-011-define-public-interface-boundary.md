# ADR-011: Define Public Interface Boundary

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines whether bashdeps exposes a sourceable Bash library API or an
executable command-line interface.

## Context

The release artifacts are Bash files and therefore can technically be sourced by
a caller.  Technical possibility should not silently become a compatibility
promise.  The current consumers need dependency acquisition as a command, and no
demonstrated use case requires callers to invoke private parsing, transport,
hashing, staging, or publication functions directly.

A public sourced API would freeze function names, variable names, shell-state
behavior, error-return conventions, and namespace interactions that otherwise
remain implementation details.

ADR-007 and ADR-009 define the public executable filename as `bashdeps.bash`.

## Decision Drivers

- Keep the public API as small as the demonstrated use case requires.
- Preserve freedom to refactor internal helpers and adapters.
- Avoid leaking shell variables or helper contracts into consuming processes.
- Keep Make and CI integration process-oriented and explicit.
- Prevent technical sourceability from being mistaken for a supported library
  interface.
- Make the interface name match the distributed executable artifact.

## Decision

The supported public interface for version 1 SHALL be the `bashdeps.bash`
executable CLI defined by ADR-007.

The project SHALL NOT document or guarantee a sourceable public Bash API.

Maintained and generated Bash artifacts MAY be written so sourcing them does not
immediately execute the CLI dispatcher.  That property is defensive behavior,
not a promise that internal functions are supported for direct invocation.

Private functions and variables SHALL use the `__bashdeps_` namespace.

Consumers SHALL NOT be expected to call `__bashdeps_*` functions or depend on
private variable values.  Those names and signatures MAY change without being
considered public API changes so long as documented `bashdeps.bash` CLI behavior
remains stable.

Direct execution SHALL dispatch when the artifact is invoked as a process.
Sourcing SHALL leave the caller responsible for any resulting private definitions
and SHALL not be a documented installation or integration method.

A future sourceable library API requires a separate ADR defining its namespace,
state model, callable functions, error semantics, and compatibility guarantees.

## Considered Alternatives

### Support both CLI and sourced API in version 1

This maximizes reuse but substantially enlarges the compatibility surface before
a consumer has demonstrated the need.

### Fail deliberately when sourced

This makes the boundary unmistakable but is unnecessarily hostile to inspection,
testing, or embedding scenarios.  Remaining inert when sourced is sufficient as
long as no public sourced API is claimed.

## Consequences

Implementation helpers remain free to evolve while tests focus primarily on the
`bashdeps.bash` CLI behavior.

Generated artifacts can still use ordinary Bash source structure and private
functions without turning those helpers into consumer commitments.

Consumers such as Makefiles invoke `bashdeps.bash` as a process rather than
sourcing it into their own shell state.

## Open Questions and Follow-Ups

None for version 1.

## Related Decisions

- Related to: ADR-007
- Related to: ADR-009
- Related to: ADR-010
