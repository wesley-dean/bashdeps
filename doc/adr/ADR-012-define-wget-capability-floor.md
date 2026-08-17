# ADR-012: Define Wget Capability Floor

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines what version 1 means by a usable `wget` fallback backend.

The decision is intentionally capability-based.  The presence of an executable
named `wget` is not sufficient evidence that the implementation can satisfy the
network bounds established by ADR-004.

## Context

ADR-004 selects `curl` as the preferred download backend and permits `wget` as a
portability fallback.  It also requires the acquisition layer to own a maximum of
three transfer attempts and to use finite timeout controls where the selected
backend exposes a supported form.

Those requirements expose meaningful differences among Wget implementations.
GNU Wget supports `-T` for network timeouts and `-t` for limiting retries.  GNU
Wget also performs multiple retries by default, so invoking it without an
explicit tries limit would make the downloader rather than bashdeps control the
number of attempts.

BusyBox Wget is compile-time configurable.  In particular, timeout support via
`-T SEC` is controlled by a BusyBox feature option.  A system can therefore have
a `wget` command while lacking the timeout control bashdeps expects.

The fallback adapter needs a small capability floor that can be checked without
performing a network request.

## Decision Drivers

- Preserve the acquisition layer's maximum of three attempts.
- Avoid unbounded or unexpectedly large backend-managed retry behavior.
- Apply a finite Wget timeout when Wget is used.
- Support capable BusyBox Wget implementations without assuming every BusyBox
  build contains the same features.
- Avoid introducing another runtime dependency solely to impose an external
  timeout.
- Keep capability detection network-free and side-effect-free.
- Fail accurately when a present command cannot satisfy the required contract.

## Decision

Version 1 SHALL consider `wget` eligible as a fallback backend only when its help
surface advertises both of these short options:

```text
-T
-t
```

The implementation MAY inspect `wget --help` output to establish those
capabilities.  The probe SHALL NOT perform a network request.

The meanings required by bashdeps are:

```text
-T SEC    apply the implementation's supported finite network timeout
-t TRIES  limit backend-managed retrieval attempts
```

When the Wget backend is selected, the version 1 invocation SHALL be equivalent
in substance to:

```text
wget -q -T 120 -t 1 -O CANDIDATE_PATH URL
```

`-t 1` ensures that one invocation represents one acquisition-layer attempt.
Bashdeps may invoke that adapter up to three times as defined by ADR-004.

`-T 120` establishes a finite backend timeout.  Bashdeps SHALL NOT claim that
this timeout has identical semantics across GNU Wget and BusyBox Wget.  For
example, a particular BusyBox implementation may apply the timeout to connect
and read operations without providing the same DNS or total-transfer timing
semantics as GNU Wget.

If `curl` is absent and an installed `wget` does not advertise the required
controls, bashdeps SHALL treat the downloader capability as unavailable and
return the public capability failure status defined by ADR-007.

If an eligible Wget backend is selected but an HTTPS retrieval later fails due
to DNS, connection, TLS, HTTP, timeout, or transfer failure, the operation SHALL
return the acquisition failure category rather than silently weakening the
backend policy.

Mandatory SHA-256 candidate verification remains unchanged and remains the
authority for artifact byte acceptance.

## Considered Alternatives

### Use any command named wget

This maximizes nominal compatibility but cannot preserve the timeout and retry
contract.  Command presence is weaker evidence than capability detection.

### Let Wget manage its default retries

GNU Wget may perform many retries by default.  That would make one bashdeps
attempt expand into an implementation-dependent number of backend attempts and
would contradict the bounded acquisition model.

### Require only -T and allow backend default retries

This establishes a timeout but still loses control of the attempt count.  Both
controls are required.

### Wrap Wget with an external timeout utility

An external watchdog could bound some implementations that lack `-T`, but it
would introduce another runtime dependency and would not solve backend-managed
retry counts by itself.

### Detect GNU Wget and BusyBox by product name

Product identity is less useful than the capabilities bashdeps actually needs.
BusyBox features are compile-time configurable, so identifying a binary as
BusyBox does not prove timeout support.

### Probe capabilities by making a network request

A live probe could test actual HTTPS behavior, but backend selection would then
create network traffic before artifact acquisition and would make deterministic
testing more difficult.  Version 1 uses a local help-surface probe and treats
actual HTTPS failures as acquisition failures.

## Consequences

A capable GNU Wget or BusyBox Wget can serve as the fallback downloader without
requiring curl.

A minimal BusyBox Wget build that lacks the required controls will be rejected as
unsupported even though `wget` exists.  That is an intentional fail-closed
compatibility boundary rather than an assumption that all Wget implementations
are equivalent.

The synchronization engine remains independent of Wget-specific flags; the
capability probe and argv construction remain private adapter behavior.

Tests should model both an eligible Wget help surface and a present-but-ineligible
Wget implementation.

## Open Questions and Follow-Ups

Future evidence may justify a different capability probe or additional safe Wget
forms.  Any such change should preserve the bounded-attempt and finite-timeout
properties rather than broadening compatibility by weakening them.

## Related Decisions

- Related to: ADR-004
- Related to: ADR-006
- Related to: ADR-007
