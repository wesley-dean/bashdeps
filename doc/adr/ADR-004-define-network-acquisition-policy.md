# ADR-004: Define Network Acquisition Policy

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR defines the version 1 network behavior used when `bashdeps` must acquire
an artifact whose declared destination is missing or whose existing bytes do not
match the approved digest.

The network layer is intentionally narrow.  It retrieves bytes from explicitly
declared HTTPS URLs.  It does not discover releases, negotiate versions,
authenticate to private registries, or decide whether newly retrieved bytes
should become trusted.

## Context

ADR-001 establishes exact-byte materialization as the product boundary.  ADR-002
requires an explicit HTTPS `url` and approved SHA-256 digest for every dependency.
ADR-003 establishes that `install` and `sync` may use the network only when local
state does not already satisfy the declaration, while `verify` is network-free.

HTTP behavior can otherwise become surprisingly broad.  Redirects may change
hosts, retries can mask persistent failures, unlimited transfers can hang builds,
and multiple download clients can differ subtly in TLS, redirect, timeout, and
error semantics.

The project therefore needs one explicit acquisition policy that remains small
enough to test and reason about.

## Decision Drivers

- Require encrypted transport for every network hop.
- Support common release hosting that redirects to a different HTTPS host.
- Avoid indefinite connection or transfer hangs.
- Retry a small number of transient failures without creating an unbounded loop.
- Use one download implementation rather than maintaining `curl` and `wget`
  behavior in parallel.
- Treat HTTP, TLS, transport, and digest failures as hard failures.
- Never allow retrieved bytes to change the approved digest automatically.
- Keep `verify` completely network-free.
- Keep authenticated/private dependency support outside version 1.

## Decision

Version 1 SHALL require `curl` for network acquisition.

`bashdeps` SHALL NOT provide a `wget` fallback in version 1.  Supporting one
client keeps transport behavior, diagnostics, and tests consistent.  A future
platform requirement may justify another client through a separate architectural
decision.

### HTTPS-only transport

The initial manifest grammar accepts only URLs beginning with:

```text
https://
```

Every redirect followed during acquisition SHALL also use HTTPS.

`bashdeps` SHALL configure `curl` so an initial HTTPS request cannot redirect to
HTTP or another non-HTTPS scheme.

A redirect to a different host MAY be followed when the resulting URL remains
HTTPS.  This behavior is necessary for common release-asset hosting patterns,
including services that redirect a stable release URL to a separate object or
content host.

Version 1 SHALL NOT use behavior equivalent to `curl --location-trusted` and
SHALL NOT deliberately forward authentication credentials across redirect hosts.
Authenticated URLs and private dependency acquisition are outside the initial
scope.

### HTTP failure behavior

HTTP response failures SHALL be treated as acquisition failures rather than as
candidate artifact content.

The acquisition implementation SHALL use `curl` failure behavior equivalent to
`--fail` so ordinary HTTP error responses do not proceed to publication as though
they were successful artifacts.

DNS failures, connection failures, TLS failures, redirect-policy violations,
timeouts, and unsuccessful transfers SHALL also be hard acquisition failures.

A failed acquisition SHALL never cause the approved manifest digest to be
changed automatically.

### Redirect limit

An acquisition SHALL follow no more than 10 redirects.

Exceeding that limit SHALL fail the artifact acquisition.

### Connection and transfer time limits

Each acquisition SHALL use a connection timeout of 10 seconds.

Each transfer attempt SHALL use a maximum total transfer time of 120 seconds.

These limits are intentionally finite defaults rather than user-configurable
version 1 manifest properties.  They are long enough for the small build inputs
that motivated the project while preventing ordinary builds from hanging
indefinitely on network failure.

A future demonstrated need for very large artifacts or unusually slow links may
justify configurable acquisition limits.

### Retry policy

`bashdeps` SHALL permit two retries after an initially unsuccessful transfer when
`curl` classifies the failure as retryable under its supported retry behavior.

Retries SHALL use a one-second delay.

The retry policy SHALL NOT bypass the HTTPS-only scheme rule, redirect limit,
per-attempt transfer timeout, or digest verification requirement.

A digest mismatch SHALL NOT be treated as a transient network condition and
SHALL NOT trigger automatic acceptance, digest replacement, or an unbounded
redownload loop.

### Candidate handling

Network output SHALL be written only to staging or another temporary candidate
path defined by the publication ADR.

`curl` SHALL NOT write directly over the declared destination.

A successful transfer establishes only that bytes were retrieved.  The candidate
SHALL still be SHA-256 verified against the approved declaration before it is
eligible for publication.

### Command behavior

The intended `curl` policy is equivalent in substance to a command using:

```text
--fail
--silent
--show-error
--location
--proto =https
--proto-redir =https
--max-redirs 10
--connect-timeout 10
--max-time 120
--retry 2
--retry-delay 1
```

The exact argv construction is an implementation detail, but the observable
security and timeout behavior above is normative.

The implementation SHALL pass URL values as data arguments to `curl`.  It SHALL
NOT construct a shell command string from manifest content or use `eval`.

### Network boundaries by operation

`bashdeps install` MAY access the network only when the declared destination is
missing or mismatched.

`bashdeps sync` MAY access the network only for manifest records whose declared
destinations are missing or mismatched.

`bashdeps verify` SHALL NOT access the network under any circumstance.

A correct existing destination SHALL therefore be reusable without a network
request.

## Considered Alternatives

### Support both `curl` and `wget`

This would broaden platform compatibility, but it would create two transport
implementations with different flags, redirect behavior, TLS handling, retry
semantics, and diagnostics.  No current consumer requires that complexity.

### Reject cross-host redirects

A same-host-only policy would narrow the trust path but would reject common
release hosting where a public HTTPS release URL redirects to another HTTPS
content host.  Digest verification remains the byte-authority check, so HTTPS
cross-host redirects are accepted in version 1.

### Permit HTTP

A digest can detect changed bytes after download, but allowing plaintext
transport unnecessarily exposes retrieval metadata and content to active network
interference.  HTTPS is available for the intended dependency sources and is
required.

### No explicit timeouts

Relying entirely on client defaults reduces policy code but can leave developer
or CI operations waiting much longer than intended during network failures.
Finite limits make failure behavior more predictable.

### Unlimited or aggressive retries

More retries might overcome unstable networks but would increase build latency
and can amplify upstream failures.  Version 1 chooses a small bounded retry
policy.

### Automatically trust changed bytes after a digest mismatch

This would make updates convenient but would destroy the manifest's role as the
trusted byte declaration.  Digest changes remain source changes subject to
review.

## Consequences

A project with correct local dependency bytes can run `install` or `sync` without
network access for those records.

Missing or mismatched artifacts require `curl` and reachable HTTPS sources.

Common HTTPS redirect-based release hosting remains usable, including cross-host
redirects, while downgrade redirects are rejected.

Network failures are bounded by explicit timeout and retry limits rather than
being allowed to continue indefinitely.

The project intentionally does not support private/authenticated artifacts in
version 1.

The required `curl` capability and any minimum supported version will be recorded
with the external-command/platform requirements.

## Open Questions and Follow-Ups

Subsequent ADRs need to define:

- exact staging and publication filesystem behavior;
- minimum supported `curl` and Bash capabilities;
- diagnostics and exit-status mapping for acquisition failures;
- whether future consumers justify authenticated URLs, mirrors, or configurable
  timeout policy.

## Related Decisions

- Related to: ADR-000
- Related to: ADR-001
- Related to: ADR-002
- Related to: ADR-003
