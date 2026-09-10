# ADR-023: Add Supplemental Upstream SHA-256 Verification

Date: 2026-09-10

## Status

Accepted

## Intent and Scope

This Architecture Decision Record adds an optional `digest_url` field to bashdeps
dependency declarations.  When present, the field names an explicit HTTPS resource
containing an upstream-published SHA-256 checksum for the declared artifact.

The upstream checksum is supplemental acquisition-time corroboration.  It does not
replace, weaken, or dynamically update the committed `digest=` value that defines
the consuming repository's approved bytes.

The decision applies to both first-class products:

- `bashdeps.bash` accepts and enforces `digest_url` during network acquisition; and
- `manifest-manager.bash` understands, preserves, and, where explicitly present,
  updates and verifies `digest_url` while preparing manifest source changes.

Existing four-field manifests remain fully valid and retain their current runtime
behavior.  Only declarations that explicitly add `digest_url` opt into the new
corroborating network check.

This ADR refines the four-field manifest grammar established by ADR-002, the
acquisition semantics in ADR-003 and ADR-004, the runtime exit-status meaning in
ADR-007, and the manifest-manager update/add contracts in ADR-020 and ADR-021.  It
implements the future architectural decision anticipated by ADR-019 without
changing ADR-019's release checksum naming rules or making remote checksums the
runtime trust authority.

## Context

Bashdeps currently accepts dependency bytes only when their SHA-256 digest matches
a digest committed in the consuming repository's manifest.  That boundary is
intentional: reviewed source states exactly which bytes are authorized, while live
network state remains untrusted input.

Many upstream projects also publish SHA-256 checksum companions beside release
artifacts.  Those checksums can provide useful corroborating evidence.  A mismatch
between an artifact and its published checksum can reveal release-pipeline errors,
mirror inconsistency, accidental replacement, corruption, or other conditions in
which the downloaded artifact should not be accepted even if another source of
information appears plausible.

A fetched upstream checksum is not an independent authorization boundary by
itself.  If an attacker can replace both an artifact and its adjacent checksum
resource, those two live resources can still agree.  Dynamically trusting the
fetched checksum instead of the committed manifest digest would therefore weaken
bashdeps' existing trust model rather than strengthen it.

The useful property is stricter acceptance through conjunction.  When
`digest_url` is declared, a newly downloaded candidate must match both:

1. the consumer-committed `digest=` value; and
2. the SHA-256 value obtained from the explicitly declared `digest_url` resource.

Either source can reject the candidate.  Neither source can authorize bytes the
other rejects.

Issue #14 captures this requirement and supersedes the earlier, less complete
request in issue #10.

## Decision Drivers

- Preserve the committed manifest digest as the consumer's approval boundary.
- Preserve behavior and network characteristics for existing four-field manifests.
- Allow upstream-published checksums to make acquisition stricter without making
  them authoritative.
- Keep `verify` network-free and deterministic from committed source plus local
  bytes.
- Avoid network access for destinations already proven equal to the committed
  digest.
- Reuse the existing bounded downloader policy rather than create a checksum-only
  transport path.
- Keep checksum parsing deliberately narrow, non-executable, and fail-closed.
- Preserve whole-set candidate preflight before publication during `sync`.
- Preserve manifest-manager's surgical source-mutation guarantees.
- Avoid inference of checksum URLs, sidecar names, or hosting-provider conventions
  in the runtime product.
- Keep the public field name descriptive of its value type.
- Leave room for future digest algorithms without adding a redundant
  `digest_type=` field.

## Decision

### Add one optional `digest_url` manifest field

A dependency declaration continues to require exactly one each of:

```text
id=VALUE
url=HTTPS_URL
dest=RELATIVE_PATH
digest=sha256:<64-lowercase-hex>
```

It may additionally contain exactly one:

```text
digest_url=HTTPS_URL
```

`digest_url` is optional.  When absent, existing four-field behavior is unchanged.
This backward-compatibility guarantee includes network behavior: a declaration
without `digest_url` causes no new checksum-resource request and follows the same
acceptance path as before this decision.

When present, `digest_url` is part of the validated declaration.  It must be
non-empty, contain no manifest-token whitespace, and begin with `https://` under
the same declaration-level transport rule as `url=`.

A duplicate `digest_url`, a non-HTTPS value, or any otherwise malformed declaration
fails as invalid declaration/manifest input.  Unknown fields continue to fail
closed.

The field name is `digest_url` rather than `upstream_digest` because the stored
value is a URL, not the digest value itself.  No `digest_type=` field is added.
The algorithm is declared by `digest=`.  Version 1 continues to support only
`sha256:` committed digests, so a version-1 `digest_url` necessarily supplies a
SHA-256 corroborating value.

ADR-015 physical-line folding applies without modification.  `digest_url` may
appear on any physical line of a continued logical record and field order remains
irrelevant.

### Preserve the committed digest as mandatory authority

`digest=` remains mandatory even when `digest_url` is present.

A successful network acquisition for a declaration containing `digest_url` requires
all of the following:

1. the artifact candidate is acquired successfully;
2. the candidate hashes to the SHA-256 value committed in `digest=`;
3. the checksum resource named by `digest_url` is acquired successfully;
4. that resource satisfies the checksum grammar defined by this ADR;
5. the candidate hashes to the SHA-256 value obtained from that resource; and
6. all ordinary filesystem and publication safety checks succeed.

The implementation may compare the candidate with the committed digest before
fetching `digest_url`.  In particular, a candidate already rejected by committed
trust data need not cause an additional network request merely to obtain a second
reason to reject it.

The fetched checksum must never replace, rewrite, or become a fallback for the
committed `digest=` value during `install`, `sync`, or `verify`.

### Treat `digest_url` as acquisition-time corroboration

The upstream checksum is consulted only when bashdeps must acquire the associated
artifact candidate from the network.

If the existing destination is an acceptable ordinary file whose SHA-256 already
matches the committed `digest=`, `install` and `sync` succeed for that destination
without fetching `digest_url`.

This preserves the existing offline/cached-state property: a previously
materialized destination that remains byte-equal to committed trust data does not
become dependent on current upstream availability.

If acquisition is required and `digest_url` is present, however, the checksum
resource is mandatory for that acquisition.  Failure to retrieve or validate it
causes the candidate to fail even when the candidate matches `digest=`.

This is an intentional availability tradeoff.  A maintainer who declares
`digest_url` chooses stricter acquisition acceptance and therefore also chooses to
make successful new acquisition depend on that upstream verification resource.

### Keep `verify` network-free

`verify` continues to perform no network access and no filesystem mutation.

It parses and validates `digest_url` as part of validating the manifest grammar,
but it does not retrieve the resource.  Local destination satisfaction continues
to mean that the destination exists as an acceptable ordinary file and hashes to
the committed `digest=` value.

Therefore `verify` does not claim that the current live upstream checksum still
agrees with the manifest.  `digest_url` is an acquisition-time corroboration
contract, not a continuously refreshed validation source.

### Use the existing downloader abstraction

Artifact and checksum-resource acquisition use the same selected downloader,
retry bounds, timeout behavior, HTTPS redirect restrictions, and staging policy
defined by ADR-004 and its refinements.

No second downloader implementation or checksum-specific network client is added.
A checksum resource is untrusted downloaded data and is written only to private
staging.

The runtime does not infer a checksum URL from the artifact URL, append `.sha256`,
fall back to `.256`, query release metadata, inspect HTML, or follow URLs embedded
inside checksum content.  The manifest's explicit `digest_url` is the complete
network location to request.

ADR-019's `.sha256` producer convention remains useful for projects that publish
such companions, but this ADR does not turn that convention into runtime discovery
behavior.

### Accept a deliberately narrow checksum-resource grammar

The checksum resource is interpreted as text data only.  It is never sourced,
evaluated, shell-expanded, executed, or treated as a command file.

After ordinary LF/CRLF line handling, blank lines are ignored.  Exactly one
non-blank line must remain.  More than one non-blank line is rejected; version 1
does not select an entry from aggregate checksum files such as `SHA256SUMS`.

The one non-blank line may use any of these forms:

```text
<64-hex-digest>
sha256:<64-hex-digest>
<64-hex-digest><horizontal-whitespace><filename-text>
<64-hex-digest><horizontal-whitespace>*<filename-text>
sha256:<64-hex-digest><horizontal-whitespace><filename-text>
sha256:<64-hex-digest><horizontal-whitespace>*<filename-text>
```

The algorithm prefix in fetched checksum text is optional.  When no algorithm
prefix is present, SHA-256 is assumed.  Therefore these checksum tokens are
semantically equivalent:

```text
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

If an algorithm prefix is present, version 1 accepts only `sha256:`.  Any other
explicit algorithm identifier is rejected rather than ignored, reinterpreted, or
guessed.  This defaulting rule applies only to checksum data fetched from
`digest_url`; the committed manifest `digest=` field retains its existing required
canonical `sha256:` prefix.

The 64 hexadecimal digits are accepted case-insensitively and normalized to
lowercase before comparison.  The committed `digest=` field remains canonical
lowercase manifest text as already required by ADR-002.

For conventional checksum-tool records, `filename-text` must be non-empty.  It is
treated as opaque, non-executable data and is not used as an authorization input.
Version 1 does not require it to equal the artifact URL basename or destination
basename.  The explicit manifest association between `url=` and `digest_url=`
defines which checksum resource corroborates which dependency.

There is no checksum-file comment syntax.  Content that is not one of the accepted
single-entry forms is malformed.  Embedded URLs, shell syntax, tool directives, or
other text receive no special interpretation.

Supporting aggregate multi-entry files, filename-based selection, additional
checksum-tool dialects, signatures, attestations, or other verification formats
requires a later decision.

### Preserve staged whole-set preflight

For `sync`, every artifact candidate required by the operation and every declared
`digest_url` verification required for those candidates must pass before
intentional publication begins.

A checksum mismatch or malformed checksum for a later dependency therefore
prevents earlier staged candidates from being published, preserving ADR-003 and
ADR-005 whole-set preflight behavior.

Checksum resources are transient verification inputs.  They are removed with
private staging on completion or failure and are not published into the dependency
destination tree.

### Refine runtime failure categories

Existing public exit categories are reused.

For `bashdeps.bash`:

```text
2  invalid declaration or manifest, including invalid digest_url syntax
4  artifact or digest_url network acquisition failed
5  acquired integrity verification failed
```

Status 5 includes:

- an artifact candidate that does not match committed `digest=`;
- a malformed, empty, or multi-entry checksum resource that cannot yield exactly
  one accepted SHA-256 value; and
- an artifact candidate that does not match the SHA-256 value obtained from
  `digest_url`.

This refines ADR-007's status-5 wording from only candidate/committed-digest
mismatch to the broader acquisition-time integrity-verification failure category.
It does not change the numeric public status.

All failure paths preserve the existing rule that unverified candidate bytes are
not intentionally published.  Private staging cleanup removes downloaded artifact
and checksum-resource data on failure while an existing destination remains
untouched.

## Manifest Manager Contract

### Parse and preserve `digest_url`

`manifest-manager.bash` accepts the same optional `digest_url` field as
`bashdeps.bash` and validates its declaration syntax under the shared manifest
grammar.

The field becomes part of the manager's logical record view while its exact source
bytes remain part of the retained raw record and source-chunk representations.

`list` output remains unchanged: it emits complete validated `id` values only.

`remove` remains an exact physical-record removal.  A selected record's
`digest_url` disappears only because the complete selected record is removed;
unrelated records are preserved byte-for-byte under ADR-021.

### Extend `add` without adding inference

`manifest-manager.bash add` continues to require explicit `id=`, `url=`, `dest=`,
and `digest=` arguments and may additionally accept one explicit `digest_url=`
argument.

`add` performs no network access and does not calculate or infer a checksum URL.
Supplying `url=` does not cause `.sha256`, `.256`, release metadata, or any other
checksum location to be derived automatically.

When `digest_url` is supplied, the canonical appended record order is:

```text
id=... url=... dest=... digest=... digest_url=...
```

When it is absent, the existing four-field canonical appended record is unchanged.
All ADR-021 prefix-preservation, newline, validation, and transaction guarantees
remain in force.

### Extend `update` only for an already-declared `digest_url`

`manifest-manager.bash update` does not add `digest_url` to a record that does not
already declare it.

For a selected record that does declare `digest_url`, update treats it as another
version-specific immutable GitHub resource associated with the dependency.  Before
network work, both the artifact `url=` and `digest_url=` must satisfy the manager's
supported update relationship and URL-family rules from ADR-020.

The manager derives the target artifact URL and target checksum URL by replacing
the recognized current ref/tag with the exact selected target tag.  It does not
infer sidecar names or change the checksum URL path beyond that existing ref/tag
transformation.

For such a record, a proposed update requires:

1. successful target-version selection under the existing explicit/latest rules;
2. successful derivation of both target URLs;
3. successful artifact acquisition;
4. SHA-256 calculation over the exact artifact bytes;
5. successful checksum-resource acquisition;
6. successful parsing of exactly one supported upstream SHA-256 value; and
7. equality between the artifact SHA-256 and the upstream value.

Only after those checks may the manager propose the new committed `digest=` value.
The consuming repository's review and commit of the resulting manifest remains the
authorization boundary.

If the target artifact URL is identical to the currently declared immutable URL,
the existing ADR-020 rule still requires the downloaded artifact bytes to match
the currently committed digest.  When `digest_url` is present, the same-target
operation also retrieves and validates the explicitly declared checksum resource.
A successful operation that produces no field changes remains a no-op and leaves
the manifest path untouched in file mode.

For a record with `digest_url`, surgical update may change only:

```text
id
url
digest
digest_url
```

`dest` remains immutable under the update operation.  Each changed old value must
satisfy ADR-020's exact-once substitution proof, the complete candidate must pass
the reverse-substitution preservation proof, and the candidate manifest must
reparse successfully before publication or stream output.

Under `update --all`, every selected record's artifact and declared checksum
verification completes before the single output/publication step.  A failure for
one checksum resource fails the entire source transaction.

### Manifest-manager failure categories

The manager retains its existing public numeric categories:

```text
2  invalid CLI, manifest, dependency selection, declaration, or unsupported update relationship
3  required runtime capability unavailable or unusable
4  release discovery or network acquisition failed
5  integrity, exact-mutation, or preservation safety check failed
6  input, staging, filesystem, output, or publication failed
```

A malformed or mismatching upstream checksum during `update` is status 5.  Failure
to retrieve the checksum resource is status 4.  `add`, `list`, and `remove` do not
acquire `digest_url` and therefore do not gain new network failure behavior.

## Security and Trust Properties

The committed digest and upstream checksum are intentionally different kinds of
input.

The committed `digest=` is reviewed source controlled by the consuming repository
and remains the acceptance authority across time.  The `digest_url` response is
live remote data controlled by an upstream endpoint and is useful only as
corroborating evidence during acquisition.

Requiring both values can detect disagreement between committed trust data,
artifact bytes, and upstream-published checksum data.  It cannot prove that the
upstream publisher or release pipeline is uncompromised, and it does not protect
against an attacker capable of replacing both an artifact and the checksum
resource while also somehow causing those malicious bytes to equal the already
committed consumer digest.

The checksum parser therefore deliberately provides no execution or discovery
surface.  It extracts one narrowly formatted digest value and nothing else.

## Considered Alternatives

### Replace `digest=` with the fetched upstream checksum

Rejected.  This would move authorization from reviewed repository source to live
remote state and directly contradict ADR-001's exact-byte trust boundary.

### Make `digest=` optional when `digest_url` is present

Rejected for the same reason.  Upstream availability and upstream control are not
a substitute for the consuming repository's committed approval of exact bytes.

### Name the field `upstream_digest`

Considered, but rejected because the value is a URL rather than a digest.  The
chosen `digest_url` name makes the stored type apparent and pairs directly with
`digest=`.

### Add `digest_type=`

Rejected.  The algorithm is already explicit in the committed `digest=` prefix.
Version 1 supports only `sha256:`, and future algorithm support should extend the
digest contract rather than duplicate algorithm metadata across fields.

### Infer `.sha256` from `url=`

Rejected.  Upstream naming is not universal, inference would broaden runtime
behavior, historical `.256` compatibility would introduce fallback policy, and a
wrong inference could turn a clear explicit declaration into ambiguous network
behavior.  `digest_url` is explicit source.

### Re-fetch upstream checksums during `verify`

Rejected.  This would make verification network-dependent, reduce deterministic
offline usefulness, and turn live upstream state into part of local-state
verification even though the committed digest already proves byte equality with
approved source.

### Require checksum-record filenames to match the artifact basename

Rejected for version 1.  Artifact URLs, redirects, destination names, and upstream
checksum naming conventions do not necessarily expose the same basename.  The
manifest already associates one explicit checksum URL with one dependency.  The
filename field is therefore parsed only as conventional sidecar syntax and is not
authoritative.

### Support aggregate checksum files

Deferred.  Selecting one entry safely introduces filename-selection rules,
duplicate-name behavior, encoding questions, and broader parser semantics that are
unnecessary for the initial one-resource/one-digest contract.

### Share one executable checksum-parser module between both products

Not required by this decision.  Both products must implement identical public
checksum semantics, but ADR-020's explicit source-closure boundary remains in
force.  Implementation may keep product-private helpers rather than introducing a
new shared source module solely to remove a small amount of duplication.

## Consequences

Existing four-field manifests remain valid and behaviorally backward-compatible.
They do not acquire a new network dependency, do not fetch checksum resources, and
continue to use the committed `digest=` exactly as before.

A declaration with `digest_url` makes fresh or corrective acquisition stricter:
accepted bytes must agree with both committed consumer trust data and the declared
upstream checksum resource.

Such a declaration is also less available during required network acquisition,
because a missing or malformed checksum resource now blocks publication even when
the artifact itself is reachable.

`verify` remains fast, offline, and stable against upstream outages or later
checksum-sidecar changes.

The manifest grammar grows from exactly four required fields to four required
fields plus one optional field.  Older bashdeps releases continue to reject the
new field as unknown, which is the intended fail-closed compatibility behavior.
Consumers must therefore update bashdeps before committing manifests that use
`digest_url`.

The manager parser, `add`, and `update` contracts expand accordingly, while `list`
and `remove` retain their existing observable output and mutation semantics.

The implementation requires negative tests for malformed checksum content,
multiple checksum entries, checksum mismatch, checksum transport failure, cached
local state, offline `verify`, transactional multi-record failure, downloader
fallback behavior, folded manifests, manager surgical updates, stream rollback,
and optional-field add/remove/list behavior.  It also requires regression coverage
showing that four-field manifests retain their pre-ADR behavior and network access
patterns.

## Follow-Ups

The implementation PR shall update the current behavior specifications, CLI/help
text, README examples where appropriate, maintained Bash source, and Bats tests to
conform to this decision.

Future work may consider aggregate checksum files, additional digest algorithms,
signed checksum material, provenance attestations, or other independently useful
verification evidence.  Those features are outside this ADR and must preserve the
consumer-committed authorization boundary unless a later ADR explicitly changes
that model.

## Related Decisions

- Preserves: ADR-001, which defines the committed exact-byte trust boundary.
- Refines: ADR-002, by adding one optional `digest_url` manifest field while
  preserving existing four-field declarations unchanged.
- Refines: ADR-003, by adding supplemental checks during required acquisition while
  preserving cached-state and offline-verify semantics.
- Refines: ADR-004, by routing checksum acquisition through the existing network
  adapter without making remote checksum data authoritative.
- Preserves: ADR-005 whole-set staging and publication safety.
- Refines: ADR-007 status 5 to include acquisition-time integrity verification
  failures involving the declared upstream checksum.
- Preserves: ADR-015 physical-line folding semantics.
- Implements the future-decision point identified by: ADR-019.
- Refines: ADR-020, by allowing surgical update of an already-declared
  `digest_url` and requiring its checksum to corroborate proposed artifact bytes.
- Refines: ADR-021, by allowing an optional explicit `digest_url` on `add` while
  preserving no-inference behavior and existing list/remove contracts.
