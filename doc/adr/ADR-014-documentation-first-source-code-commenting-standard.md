# ADR-014: Documentation-First Source Code Commenting Standard

Date: 2026-08-17

## Status

Proposed

## Intent and Scope

This Architecture Decision Record adopts the documentation-first,
narrative-heavy source code commenting standard established by Bootstrap
ADR-045 for bashdeps.

The standard applies to newly written Bash source and to existing Bash source
that is being documented, reviewed, corrected, or refactored.  It is especially
important when source changes are produced or reviewed with AI/LLM assistance.

This ADR is intentionally verbose.  The verbosity is a design choice: source
comments are part of the project's maintainability, safety, reviewability, and
incident-prevention surface.

The standard governs maintained Bash source.  Generated distribution artifacts
inherit comments only through the build process and remain generated state under
ADR-009.

## Context

Source code is read far more often than it is written.  It is read by maintainers
who may be tired, under time pressure, responding to an incident, returning to the
code after a long absence, or reviewing changes they did not author.

Sparse comments force those readers to reconstruct purpose, constraints, safety
properties, and failure behavior directly from executable statements.  That
reconstruction increases cognitive load precisely when clear understanding matters
most.

Bootstrap addressed the same problem through ADR-045, which treats documentation
as architecture and adopts a deliberately human-centered, narrative-heavy source
commenting style.  bashdeps initially carried over the documentation-driven
workflow but lost that concrete source-comment standard: `src/bashdeps.bash`
contains only a short file comment and largely undocumented private helpers.

That omission is particularly unfortunate for bashdeps because the implementation
operates on a software supply-chain boundary.  Its path validation, symlink
checks, staged acquisition, digest verification, downloader capability selection,
and publication rules should be understandable without requiring a future
maintainer to reverse-engineer every branch under pressure.

ADR-011 establishes that the supported public interface is the `bashdeps.bash`
CLI and that `__bashdeps_*` functions remain private implementation details.
Documenting those private functions does not promote them into a supported sourced
API.  The documentation exists for maintainers, reviewers, and generated reference
material; the public compatibility boundary remains unchanged.

## Decision Drivers

- Optimize source for comprehension under stress rather than minimum file size.
- Preserve architectural intent close to the code that implements it.
- Explain safety mechanisms and failure behavior explicitly.
- Make AI-assisted changes easier for humans to audit.
- Reduce reliance on tribal knowledge and reverse engineering.
- Prevent documentation-only work from silently changing executable behavior.
- Surface uncertainty rather than inventing plausible but unsupported rationale.
- Keep a consistent shell documentation syntax across Bootstrap and bashdeps.
- Preserve ADR-011's distinction between documented private helpers and public API.

## Core Premise

Documentation is architecture.

Comments are not decorative metadata.  They are part of the system's safety and
maintainability surface.

Source should read like explanatory technical prose around executable code.  A
maintainer should be able to understand both what a construct does and why it
exists without first reverse-engineering the implementation.

As a guiding norm, maintained source SHOULD target approximately two lines of
meaningful documentation for every line of executable code where that density
improves comprehension.  This is not a mechanical coverage metric.  Repetition
that reduces cognitive load is acceptable; filler that merely inflates comment
volume is not.

Clarity is preferred over cleverness and concision.

## Documentation Targets

The following SHALL be documented when present in maintained Bash source:

- file/module purpose and scope;
- every function, including private helpers;
- configuration and global variables;
- policy-defining constants;
- non-obvious shared data structures;
- validation and safety mechanisms;
- edge cases and exceptional behavior;
- externally visible output and exit-status behavior.

Local variables do not require individual `@var` blocks merely because they
exist.  Their meaning should normally be explained by the containing function's
narrative and parameter documentation.

## Required Documentation Content

Where applicable, documentation SHOULD explain:

- purpose and scope;
- background or motivation;
- inputs and outputs, including their semantics;
- preconditions and assumptions;
- invariants that must remain true;
- failure modes and error handling;
- filesystem, transport, integrity, or other security considerations;
- configuration defaults and precedence;
- side effects and intentionally absent side effects;
- non-goals and excluded behavior;
- concrete examples resembling realistic maintainer or caller usage.

Not every item applies to every helper.  Omissions should be intentional rather
than the result of relying on a reader to infer important behavior.

## Bash Doxygen Syntax

bashdeps SHALL use the same Doxygen-style shell syntax established by Bootstrap
ADR-045.

Every Doxygen documentation line SHALL begin with `##` at column 1.

Decorative separator lines made only of repeated `#` characters SHALL NOT be
used.

The shebang remains the first line of executable scripts.  The file-level Doxygen
block follows the shebang.

### File documentation

A file documentation block SHALL include, as applicable and in this conceptual
order:

```text
@file
@brief
@details
@author
@since
@deprecated
@note
@warning
@see
@par Examples
@code
@endcode
```

`@author`, `@since`, `@deprecated`, `@note`, `@warning`, and `@see` are optional
when they do not add useful information.  `@file`, `@brief`, `@details`, and an
examples section are required for maintained Bash source.

File examples SHALL demonstrate realistic use of the executable or source unit
rather than merely repeat its filename without context.

### Function documentation

Every function SHALL have a documentation block immediately before its
declaration.  No blank line shall separate the end of the documentation block
from the function declaration.

A function block SHALL use, as applicable, this conceptual order:

```text
@fn
@brief
@details
@param
@returns
@retval
@author
@since
@deprecated
@note
@warning
@see
@par Examples
@code
@endcode
```

Function signatures in `@fn` SHALL use the simple function name form, for example:

```text
@fn __bashdeps_hash_file()
```

Positional argument names SHALL be semantic names rather than `$1`, `$2`, or
`$@`.  Variadic positional collections MAY use a `name[]` form.  Named or
environment inputs MAY use a `name=` form.  CLI flags and options MAY be named by
their public spelling.

`@returns` SHALL describe data written to standard output.  It SHALL NOT be used
as a synonym for process status.

`@retval` SHALL describe exit statuses, one status per line.

Additional output channels MAY be documented with `@par` sections, for example
`@par Standard Error`, when doing so materially clarifies the contract.

### Global and configuration variables

Global, configuration, and policy-defining variables SHALL use `@var` and
`@brief`.  Additional narrative MAY follow when the variable's lifecycle,
default, or mutation rules are non-obvious.

For example:

```bash
## @var __bashdeps_dest_root
## @brief Project-relative root beneath which declared destinations are allowed.
## @details
## Command handlers reset this policy to `vendor` for each invocation and may
## replace it only after validating an explicit `--dest-root` value.
__bashdeps_dest_root='vendor'
```

Documenting a private global does not make it part of the public interface.

## Required Examples

Every file-level block and every function-level block SHALL contain an
`@par Examples` section followed by `@code` and `@endcode`.

Lines inside shell example blocks SHALL also begin with `##`, ensuring the example
remains documentation and cannot alter executable behavior.

Examples SHOULD resemble realistic maintainer usage whenever that can be inferred
safely from the source and architecture.  They SHOULD demonstrate the purpose of
the function rather than merely restating the function signature.

Private-helper examples are permitted and expected for maintainability even though
those helpers are not supported consumer APIs.

If no realistic example can be established with high confidence, the most
conservative plausible example MAY be documented together with a nearby
`## @TODO` stating that the example requires confirmation.

## Narrative Style

Documentation SHALL use complete sentences and plain technical language.

Comments SHOULD explain motivation, constraints, safety posture, and consequences.
They SHOULD NOT merely translate individual Bash statements into English.

Redundancy is acceptable when it helps a stressed reader retain the relevant
invariant without navigating elsewhere.  Important safety boundaries may therefore
be stated both in ADRs and near the implementing code.

The source remains subordinate to the architecture: comments must describe the
behavior that actually exists and the decisions the repository actually records.
Plausible-sounding rationale must not be invented to make code appear more
intentional than the evidence supports.

## Ambiguity and `@TODO`

When purpose, usage, constraints, or rationale cannot be established with
reasonable confidence from the source and governing documentation, the uncertainty
SHALL be made explicit rather than guessed.

An appropriate Doxygen block SHALL include a specific, neutral `@TODO` comment
that identifies what is unclear.  Examples include:

```text
@TODO Explain why this special case exists.
@TODO Confirm whether this behavior is intentional or historical.
@TODO Document the invariant this branch is preserving.
```

The `@TODO` should surface the uncertainty for human review.  It should not invent
a proposed explanation unless that proposal is separately requested.

A visible `@TODO` is preferable to confident but unsupported documentation.

## Non-Destructive Documentation Updates

Documentation-only work SHALL preserve executable behavior exactly.

When adding or improving comments in existing Bash source:

1. Executable code SHALL remain unchanged.
2. Function bodies, control flow, variable assignments, command invocations,
   shell options, traps, and ordering SHALL be preserved.
3. Existing accurate compliant comments SHOULD be retained.
4. Inaccurate comments MAY be corrected when the correction is strongly supported
   by the source or governing documentation.
5. Ambiguous intent SHALL be marked rather than guessed.
6. The resulting diff SHALL be reviewed specifically for accidental executable
   changes.
7. Non-comment lines SHOULD be compared before and after the change.
8. Syntax checks, linters, behavior tests, and generated-artifact tests SHOULD be
   run where practical.

Destructive helpfulness invalidates a documentation-only change.

## Generated Artifact Relationship

`src/bashdeps.bash` is the maintained implementation under ADR-009.

`dist/bashdeps.dev.bash` retains maintained source comments and therefore carries
this documentation into the developer-oriented artifact.

`dist/bashdeps.bash` intentionally removes full-line comments.  That transformation
does not weaken the maintained-source documentation requirement; the normal
consumer artifact is optimized for distribution while the source and developer
artifact remain the explanatory surfaces.

Generated files SHALL NOT be hand-edited to satisfy this ADR.  The build process
regenerates them from maintained source.

## Public Interface Boundary

Doxygen documentation of `__bashdeps_*` functions and variables is maintenance
documentation only.

It SHALL NOT be interpreted as a supported sourced Bash API.  ADR-011 remains
authoritative: consumers are supported through the `bashdeps.bash` executable CLI,
and private names or signatures may change without constituting a public API
change when CLI behavior remains compatible.

## Considered Alternatives

### Keep comments concise and document only public commands

This would produce smaller maintained source, but it would leave the most
security-sensitive implementation behavior -- parsing, hashing, acquisition,
path safety, staging, and publication -- to be reverse-engineered by maintainers.
The project prefers comprehension under stress over minimal source size.

### Rely exclusively on ADRs and external documentation

ADRs preserve architectural decisions well, but they do not replace local
explanation of how a particular function participates in those decisions.  The
chosen approach keeps high-level rationale in ADRs and puts relevant operational
context beside the implementation.

### Use ordinary `#` prose without structured directives

Free-form comments are readable but provide less consistency and are harder to
turn into browsable reference documentation.  The Doxygen-style structure gives
humans predictable sections while remaining ordinary shell comments.

### Document only public functions

bashdeps deliberately has no public sourced-function API.  Restricting function
documentation to public functions would therefore leave almost the entire
implementation undocumented.  Private helpers are documented for maintainers
without enlarging the compatibility contract.

### Permit documentation updates to clean up nearby code

Combining documentation with opportunistic refactoring makes it harder to prove
that behavior remained unchanged.  Documentation-only changes therefore remain
comment-only; implementation improvements belong in separately reviewable work.

## Consequences

Maintained Bash source becomes substantially larger and more verbose.

Reviewers gain local explanations of purpose, inputs, outputs, invariants, failure
modes, safety properties, and realistic usage.

AI-assisted documentation changes become easier to audit because executable code
is explicitly out of scope and non-comment equivalence is a validation target.

Private implementation details become easier to understand without becoming
public compatibility commitments.

Documentation requires maintenance whenever behavior changes.  Stale documentation
is considered a defect rather than harmless commentary.

## Open Questions and Follow-Ups

A Doxygen generation target and repository configuration may be added when the
project needs browsable generated reference documentation.  This ADR defines the
source-comment contract independently of whether generated HTML is published.

## Related Decisions

- Related to: ADR-009
- Related to: ADR-010
- Related to: ADR-011
- Derived from: Bootstrap ADR-045
