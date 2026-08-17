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

The architecture deliberately separates the synchronization engine from the
specific command used to transfer bytes.  `curl` and `wget` are transport
adapters behind one internal download contract rather than dependencies that are
spread throughout the implementation.

## Context

ADR-001 establishes exact-byte materialization as the product boundary.  ADR-002
requires an explicit HTTPS `url` and approved SHA-256 digest for every dependency.
ADR-003 establishes that `install` and `sync` may use the network only when local
state does not already satisfy the declaration, while `verify` is network-free.

The project initially selected `curl` as the sole download client because its
transport controls are explicit and well suited to the required policy.  Further
portability review identified an important class of lean and embedded Linux
environments in which `wget`, often through BusyBox, may already be present while
`curl` is not.  Consumers such as `adrctl`, which acquires and embeds the pinned
`mktext` release artifact as part of its build, benefit from avoiding an
unnecessary dependency on one particular download client.

Requiring `curl` when an otherwise usable HTTPS-capable `wget` is already
available would create an avoidable installation dependency.  Conversely,
treating all `wget` implementations as equivalent would overstate what can be
known about their behavior.  BusyBox applets and individual features can be
selected at build time, and GNU Wget and BusyBox Wget do not expose identical
controls for redirects, timeouts, retries, and diagnostics.

The network layer therefore needs a backend-independent contract with explicit
capability detection and honest backend-specific limits.

## Decision Drivers

- Support lean Linux environments without requiring an avoidable download-client
  installation.
- Keep downloader-specific flags and behavior isolated behind one internal
  abstraction.
- Prefer the transport backend with the strongest predictable control surface
  when more than one is available.
- Require HTTPS for every URL accepted from the manifest.
- Preserve mandatory SHA-256 verification as the authority for acceptable bytes.
- Avoid indefinite or unbounded retry behavior where the selected backend offers
  suitable controls.
- Treat HTTP, TLS, transport, and digest failures as hard failures.
- Never allow retrieved bytes to change the approved digest automatically.
- Keep `verify` completely network-free.
- Keep authenticated/private dependency support outside version 1.
- Make security claims no stronger than the selected backend can enforce.

## Decision

Version 1 SHALL implement network acquisition through a private downloader
abstraction.

The synchronization, manifest, staging, verification, and publication layers
SHALL NOT construct downloader-specific commands directly.  They SHALL request
an acquisition through one internal operation whose conceptual contract is:

```text
download URL CANDIDATE_PATH
```

The downloader abstraction SHALL select a supported backend at runtime in this
order:

1. `curl`, when available and usable;
2. `wget`, when `curl` is unavailable and the available `wget` can perform the
   required HTTPS acquisition;
3. failure when neither supported backend is usable.

Selection SHALL be based on runtime capability rather than operating-system or
distribution-name assumptions.

When both clients are available, `curl` SHALL be preferred because its redirect,
protocol, timeout, and failure controls provide the more explicit policy surface.

Version 1 SHALL support only these two downloader families.  Additional clients
require a deliberate extension of this ADR and a tested adapter rather than
being invoked opportunistically.

### Backend isolation

Downloader-specific argv construction, capability checks, and exit-code handling
SHALL remain inside backend-specific private functions.

The remainder of `bashdeps` SHALL reason only about outcomes such as:

- candidate acquired successfully;
- no supported downloader available;
- downloader lacks a required capability;
- transport or HTTP failure;
- candidate acquired but later rejected by digest verification.

A transport backend SHALL write only to the candidate path supplied by the
staging layer.  No downloader SHALL write directly over a declared destination.

Manifest values SHALL be passed as data arguments.  `bashdeps` SHALL NOT build a
shell command string from a URL or use `eval` to invoke a downloader.

### HTTPS declaration requirement

The manifest grammar SHALL continue to accept only URLs beginning with:

```text
https://
```

Plain `http://`, `ftp://`, `file://`, scheme-relative URLs, and other schemes
remain invalid declarations.

The selected backend SHALL use ordinary certificate verification.  `bashdeps`
SHALL NOT deliberately disable TLS certificate or hostname verification.

An installed `wget` command that cannot successfully perform HTTPS retrieval is
not a usable `wget` backend for `bashdeps`.

### Redirect behavior

Cross-host HTTPS redirects are legitimate for common release hosting and SHALL
not be rejected merely because the hostname changes.

The `curl` backend SHALL restrict redirects to HTTPS and SHALL apply a redirect
limit of 10.

Portable `wget` implementations do not provide one uniform control surface for
restricting every redirect hop to HTTPS or configuring an identical redirect
limit.  Version 1 therefore SHALL NOT claim that the `wget` backend can enforce
the same redirect-scheme and redirect-count guarantees as the `curl` backend.

This limitation does not weaken the manifest byte-identity rule: bytes acquired
through either backend SHALL still be rejected unless their SHA-256 digest
matches the approved declaration exactly.

If future evidence identifies a reliable common mechanism for inspecting or
restricting redirect hops across supported `wget` implementations, that stronger
transport guarantee may be added without changing the manifest model.

### HTTP and transport failure behavior

An unsuccessful downloader exit status SHALL be treated as an acquisition
failure.

Ordinary HTTP errors, DNS failures, connection failures, TLS failures, unsupported
HTTPS behavior, timeout failures, and unsuccessful transfers SHALL never produce
an eligible publication candidate.

The acquisition layer SHALL NOT interpret an error response body as a successful
artifact merely because bytes were written to a temporary path.

A failed acquisition SHALL never cause the approved manifest digest to change
automatically.

### Timeout and retry policy

The acquisition layer SHALL use bounded retries under its own control rather
than relying exclusively on downloader-specific automatic retry behavior.

An artifact MAY be attempted initially and retried up to two additional times for
transport failures, for a maximum of three acquisition attempts.  A one-second
delay SHOULD separate retry attempts.

Digest mismatch occurs after transport and SHALL NOT be treated as a transient
network condition.  A digest mismatch SHALL NOT trigger automatic trust,
automatic digest replacement, or an unbounded reacquisition loop.

The `curl` backend SHALL use a connection timeout of 10 seconds and a maximum
total transfer time of 120 seconds per attempt.

A usable `wget` backend SHOULD use its available finite timeout control.  Because
GNU Wget and configurable BusyBox Wget implementations do not provide identical
timeout semantics, version 1 SHALL NOT claim byte-for-byte or second-for-second
network timing equivalence between backends.

If the detected `wget` lacks a timeout capability that the implementation has
defined as necessary for safe non-interactive operation, `bashdeps` MAY reject
that `wget` as an unsupported backend rather than silently weakening the
operation.  The exact capability probe belongs to implementation and platform
testing, while the fail-closed behavior is normative.

### Candidate handling and digest authority

A successful transfer establishes only that bytes were retrieved.

Every candidate acquired through `curl` or `wget` SHALL be SHA-256 verified
against the approved manifest declaration before it is eligible for publication.

The downloader backend has no authority to establish artifact identity.  HTTP
metadata, remote filenames, timestamps, ETags, Content-Length, server-provided
checksums, and downloader success statuses SHALL NOT substitute for the committed
SHA-256 digest.

This separation is particularly important because the supported download clients
have different transport capabilities.  The transport adapter retrieves bytes;
the verification layer decides whether those bytes are the approved artifact.

### `curl` backend policy

Where supported by the selected `curl`, the backend policy SHALL be equivalent in
substance to:

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
```

Retries are intentionally managed by the acquisition layer rather than requiring
`curl --retry` semantics.

The exact argv construction remains an implementation detail.  The HTTPS-only
redirect restriction and timeout behavior described above are normative for the
`curl` backend.

### `wget` backend policy

The `wget` adapter SHALL use non-interactive retrieval and explicit output to the
staging candidate path.

It SHALL avoid options that disable TLS certificate verification.

It SHALL use finite timeout controls when the detected implementation provides
the required supported form.

The adapter SHALL account for differences between GNU Wget and BusyBox Wget
without exposing those differences to the synchronization engine.  Flavor or
capability detection MAY inspect supported command behavior or help output, but
`bashdeps` SHALL fail rather than assume an option exists and then silently run
with weaker semantics.

The `wget` backend SHALL not be described as feature-equivalent to the `curl`
backend.  It is a portability backend implementing the same artifact-acquisition
role under the explicitly documented transport limitations above.

### Network boundaries by operation

`bashdeps install` MAY access the network only when the declared destination is
missing or mismatched.

`bashdeps sync` MAY access the network only for manifest records whose declared
destinations are missing or mismatched.

`bashdeps verify` SHALL NOT access the network under any circumstance.

A correct existing destination SHALL therefore be reusable without a network
request or the presence of either downloader.

## Considered Alternatives

### Require only `curl`

This provides the most uniform transport behavior and was the original decision.
It was reconsidered because lean environments, including BusyBox-oriented systems,
may have a usable `wget` while lacking `curl`.  Requiring installation of another
client is unnecessary when a verified fallback can satisfy the core acquisition
role.

### Prefer `wget` when available

This might align with minimal Linux environments, but `curl` provides stronger
and more explicit protocol and redirect controls for the policy required here.
`curl` therefore remains the preferred backend when both are present.

### Treat `curl` and `wget` as identical implementations

This would simplify documentation but would be inaccurate.  GNU Wget, BusyBox
Wget, and `curl` expose different capabilities and failure semantics.  The
architecture normalizes the role and high-level outcomes without pretending the
transport mechanisms are identical.

### Scatter client detection throughout synchronization code

Individual call sites could choose whichever downloader is present.  This was
rejected because it would tightly couple synchronization behavior to external
command details and make testing, portability, and later backend changes harder.
A private transport adapter creates a single architectural boundary.

### Reject cross-host redirects

A same-host-only policy would narrow the trust path but would reject common
release hosting where a public HTTPS release URL redirects to another HTTPS
content host.  Digest verification remains the byte-authority check, so cross-host
redirects are acceptable when supported by the selected backend.

### Permit HTTP manifest URLs

A digest can detect changed bytes after download, but allowing plaintext URLs
unnecessarily weakens transport.  The declared source itself must remain HTTPS.

### No explicit timeouts or retry bounds

Relying entirely on client defaults reduces policy code but can leave developer
or CI operations waiting much longer than intended during network failures.
Version 1 uses bounded retries and backend timeout controls where they can be
reliably applied.

### Automatically trust changed bytes after a digest mismatch

This would make updates convenient but would destroy the manifest's role as the
trusted byte declaration.  Digest changes remain source changes subject to
review.

## Consequences

A project with correct local dependency bytes can run `install` or `sync` without
network access and without requiring either downloader for those already-satisfied
records.

When acquisition is required, `curl` is used when available.  A usable `wget`
provides a portability fallback when `curl` is absent.  If neither supported
backend can perform the required HTTPS retrieval, acquisition fails explicitly.

The downloader abstraction creates a clean separation between dependency-state
logic and external transport utilities.  Future downloader support can be added
behind that boundary without changing manifest, staging, digest, or publication
semantics.

Transport guarantees are backend-aware rather than falsely uniform.  In
particular, version 1 does not claim identical redirect controls or timeout
semantics for portable `wget` implementations.

Mandatory SHA-256 verification remains the backend-independent authority for
whether acquired bytes may be published.

The project intentionally does not support private/authenticated artifacts in
version 1.

Downloader capability requirements and the SHA-256 command selection will be
recorded with the external-command/platform requirements.

## Open Questions and Follow-Ups

Subsequent ADRs need to define:

- exact runtime capability probes used to accept or reject a `wget` backend;
- SHA-256 command selection and minimum Bash capabilities;
- diagnostics and exit-status mapping for downloader selection and acquisition
  failures;
- whether future consumers justify authenticated URLs, mirrors, configurable
  timeout policy, or stronger portable redirect inspection.

## Related Decisions

- Related to: ADR-000
- Related to: ADR-001
- Related to: ADR-002
- Related to: ADR-003
