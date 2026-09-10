# ADR-022: Publish an Ephemeral Generated ADR Landing Page

Date: 2026-09-09

## Status

Accepted

## Intent and Documentation Posture

This Architecture Decision Record extends the existing Doxygen publication
workflow with a generated ADR landing page while keeping mechanically generated
navigation out of maintained source control.

The repository SHALL maintain the stable prose that frames the ADR corpus, SHALL
use `adrctl generate toc` for mechanical ADR title/link enumeration, and SHALL
compose those inputs into an ephemeral `doc/adr/README.md` during documentation
generation.  Doxygen SHALL use that generated Markdown file as the main page of
the published reference site.

The generated landing page is a build input and publication artifact, not a
maintained repository document.  The authoritative sources remain the individual
ADRs, maintained framing fragments, and `doc/decisions.md`.

This decision does not add an ADR relationship graph.  The linked textual table
of contents is the normal navigation surface.

## Context

ADR-016 established `make docs` as the canonical local and CI path for Doxygen
reference generation and established `doc/reference/` as ignored generated
output.  ADR-017 later moved the Doxygen filter into manifest-managed dependency
state while retaining the repository's bootstrap and dependency trust boundaries.

The resulting GitHub Pages site is useful as source reference documentation, but
its index currently lacks a repository-level body of documentation.  A reader who
arrives at the site does not receive the ADR-oriented context and navigation that
now works well in bashlog.

The ADR corpus already contains the information needed to construct a linked
index.  Maintaining a second hand-written title list would duplicate filenames and
titles and would predictably drift.  `adrctl` already owns ADR discovery and TOC
serialization, so bashdeps should consume that report rather than implement a
second ADR parser.

An earlier implementation draft considered committing the generated
`doc/adr/README.md`.  That approach makes the file useful when browsing the ADR
directory directly on GitHub, but it also creates a synchronization obligation:
every ADR change that affects the index must carry an otherwise derivative file
change, and CI must distinguish a current generated file from a stale one.  The
primary requirement here is the published documentation site, not GitHub's
directory README behavior.

The project already treats generated Doxygen HTML as reproducible derivative
output.  Treating the generated Markdown landing page as another ephemeral stage
of the same documentation pipeline gives the project a clearer boundary:
maintained prose and ADRs are source; generated navigation and HTML are products
of the documentation build.

## Decision Drivers

- Give the published reference site a useful project and ADR landing page.
- Keep repository-specific explanatory prose in maintained source.
- Derive ADR titles and links mechanically from authoritative ADR files.
- Reuse `adrctl` rather than creating another ADR discovery implementation.
- Avoid committing derivative navigation solely to feed another generated
  artifact.
- Preserve the existing bashdeps dependency bootstrap and trust model.
- Keep adrctl outside both shipped executable source closures.
- Preserve `make docs` as the canonical documentation-generation entry point.
- Keep generation deterministic and atomic.
- Keep normal ADR navigation textual and renderer-independent.
- Preserve the established distinction between dependency preparation and
  dependency verification.

## Decision

### Maintain framing source and generate the composite page

The repository SHALL maintain:

```text
doc/adr/README.intro.md
doc/adr/README.outro.md
```

These files own stable repository-specific prose around the mechanically generated
ADR list.

Documentation generation SHALL compose those maintained files with
`adrctl generate toc` output into:

```text
doc/adr/README.md
```

The generated `README.md` SHALL be ignored by Git and SHALL NOT be committed as
ordinary repository state.

The responsibility split is:

```text
ADRs + README.intro.md + README.outro.md
    = maintained documentation source

adrctl generate toc
    = mechanical ADR title/link enumeration

Make
    = composition, destination, sequencing, and atomic replacement

doc/adr/README.md
    = ephemeral Doxygen input

doc/reference/
    = ephemeral Doxygen output
```

### Use a pinned adrctl documentation dependency

The repository SHALL add a released `adrctl.bash` artifact to `dependencies.txt`
at:

```text
vendor/adrctl.bash
```

The initial pin SHALL use adrctl v0.0.13 and its release-published SHA-256 digest.

adrctl is development/documentation tooling only.  It SHALL NOT be concatenated,
embedded, sourced, or otherwise incorporated into `bashdeps.bash` or
`manifest-manager.bash` release artifacts.

The existing Make-owned `vendor/bashdeps.bash` bootstrap remains outside the
manifest because the dependency manager cannot use its own manifest to obtain its
first executable copy.

### Provide `make adr-index`

The Makefile SHALL expose:

```text
make adr-index
```

The target SHALL consume already-prepared `vendor/adrctl.bash` state.  It SHALL
NOT invoke dependency synchronization itself.

`adr-index` SHALL:

1. require the pinned adrctl artifact and maintained framing files;
2. invoke adrctl through Bash rather than depending on executable mode;
3. call `generate toc` with the maintained intro and outro fragments;
4. write the complete candidate to a same-directory temporary path; and
5. replace `doc/adr/README.md` only after successful generation.

Generation therefore remains safe against an ordinary failed report leaving a
partially written landing page at the selected destination.

The Makefile MAY expose conventional variables for the ADR directory, generated
index, framing files, and adrctl path so the implementation is inspectable and
adaptable without teaching adrctl repository-specific layout policy.

### Integrate generation into `make docs`

`make docs` SHALL ensure dependency state is prepared according to the existing
ADR-017 behavior and SHALL invoke `adr-index` before Doxygen.

The sequencing SHALL be explicit.  The implementation SHALL NOT rely on parallel
Make prerequisite ordering to ensure that adrctl exists before ADR index
generation begins.

`docs-clean` SHALL continue to remove Doxygen output under `doc/reference/` and
SHALL NOT be a prerequisite that races with ADR index generation.  The generated
ADR index may remain in the working tree as ignored derivative state after
`make docs` completes.

A complete generated-state cleanup path MAY remove the ephemeral ADR index along
with other generated state.

### Make the generated page the Doxygen main page

Doxygen SHALL consume maintained Markdown documentation and the generated
`doc/adr/README.md` in addition to maintained source documentation.

The Doxyfile SHALL use:

```text
USE_MDFILE_AS_MAINPAGE = doc/adr/README.md
```

The generated HTML under `doc/reference/` remains ignored and ephemeral.  Making
the generated ADR index the Doxygen main page does not make either generated
surface authoritative documentation source.

### Do not generate an ADR relationship graph

Normal documentation generation SHALL NOT invoke `adrctl generate graph`, embed
Mermaid source, render DOT/Graphviz relationship diagrams, or add graph-specific
link configuration merely as part of ADR navigation.

This does not remove or deprecate graph capabilities from adrctl and does not
prohibit unrelated diagrams governed by other project decisions.  It establishes
only that the ordinary project landing page uses the linked textual ADR index.

## Promises

1. The published Doxygen site has a project-specific ADR landing page as its main
   page.
2. The landing page's ADR enumeration comes from adrctl and the authoritative ADR
   corpus rather than from a second local parser.
3. Stable explanatory prose remains maintained in `README.intro.md` and
   `README.outro.md`.
4. `doc/adr/README.md` is generated during documentation work and is not committed.
5. Failed ADR index generation does not intentionally publish a partial index.
6. `make docs` remains the canonical documentation entry point.
7. adrctl remains outside both consumer executable families and their runtime
   requirements.
8. Normal documentation generation includes no ADR relationship graph.

## Non-Promises

1. Browsing `doc/adr/` directly on GitHub is not promised to show the generated
   table of contents as a directory README.
2. The generated landing page is not an architectural source of truth.
3. The generated index does not replace `doc/decisions.md` or summarize decision
   rationale.
4. This decision does not add graph generation to the documentation pipeline.
5. This decision does not change `bashdeps.bash` or `manifest-manager.bash` public
   behavior.
6. This decision does not make adrctl a consumer runtime dependency.
7. The generated Doxygen tree remains disposable and need not be committed.

## Adversary and Failure Model

The pinned adrctl artifact executes with the authority of the documentation build
and therefore becomes part of the documentation trusted computing base.  Its
committed SHA-256 digest authorizes exact expected bytes but does not prove those
bytes are behaviorally safe.  Dependency review remains required.

A failed report generator could otherwise leave truncated or partial Markdown.
Same-directory temporary generation followed by replacement only on success
bounds that ordinary failure mode.

A compromised or defective generator could produce incorrect links or prose.
The maintained ADRs and framing remain reviewable source, while publication and CI
provide observable generated output.  The generated page is deliberately not
promoted into authoritative source merely because Doxygen publishes it.

The implementation MUST preserve the product source closures.  Documentation-only
adrctl bytes must not become part of either released executable.

The implementation also avoids executing ADR Markdown or framing files as shell
code.  They are data consumed by adrctl and ordinary file composition.

## Operational Constraints

- `vendor/adrctl.bash` MUST be declared in `dependencies.txt` with an immutable
  release URL and approved SHA-256 digest.
- adrctl MUST remain documentation/development tooling only.
- `make adr-index` MUST consume prepared dependency state and MUST NOT synchronize
  dependencies.
- `make docs` MUST sequence dependency preparation before ADR index generation.
- `doc/adr/README.intro.md` and `doc/adr/README.outro.md` MUST remain maintained
  source.
- `doc/adr/README.md` MUST be generated atomically and MUST be ignored by Git.
- Doxygen MUST use the generated ADR index as its main page.
- generated `doc/reference/` output MUST remain ignored and ephemeral.
- ADR title/link enumeration MUST come from adrctl rather than a bashdeps-local
  parser.
- normal documentation generation MUST NOT invoke `adrctl generate graph` or add
  a relationship-graph section.
- neither released executable family may include adrctl bytes or require adrctl at
  runtime.

## Considered Alternatives

### Commit the generated `doc/adr/README.md`

This would make the generated index visible automatically when browsing the ADR
directory on GitHub.  It was rejected because the primary consumer is the
published Doxygen site and committing the derivative page creates an avoidable
synchronization and CI-drift obligation.

### Maintain the ADR list by hand

This avoids another documentation dependency, but duplicates ADR filenames and
titles in maintained source and creates predictable drift.  It was rejected.

### Generate the list with Make, grep, or a local Bash parser

The implementation could be short, but it would create another definition of ADR
discovery and title extraction.  `adrctl` already owns those semantics and is the
appropriate focused producer.

### Make `doc/decisions.md` the Doxygen main page

The decision map is useful maintained prose, but its purpose is concise decision
summary rather than mechanically complete ADR navigation.  Keeping those roles
separate makes both documents clearer.

### Generate a landing page only inside the Pages workflow

This would satisfy hosted publication but would make local `make docs` differ from
the Pages build.  The canonical Make target should produce the same documentation
shape locally and in CI.

### Make `adr-index` synchronize dependencies

This would be convenient from a pristine checkout but would blur the repository's
existing dependency boundaries.  The focused generation target consumes prepared
state; the higher-level documentation target performs whatever preparation its
existing governance allows.

### Publish an ADR relationship graph

The graph adds renderer and presentation complexity while providing less practical
navigation value than the linked textual index.  The routine documentation path
therefore remains text-only.

## Consequences

The GitHub Pages site gains a useful project-level entry page without adding a
committed derivative Markdown file.

The repository gains two small maintained framing documents and one pinned
executable documentation dependency.  The documentation trusted computing base
therefore expands by the reviewed adrctl artifact.

Local `make docs` leaves an ignored generated `doc/adr/README.md` in addition to
ignored `doc/reference/` output.  That makes the intermediate page inspectable
without turning it into maintained source.

Doxygen becomes a broader documentation portal by processing selected maintained
Markdown as well as source-level Doxygen comments.  Runtime behavior, release
artifact count, and executable source closures remain unchanged.

## Related Decisions

- Related to: ADR-008: Define Bootstrap and Make Integration
- Related to: ADR-010: Define Development and Testing Workflow
- Related to: ADR-014: Documentation-First Source Code Commenting Standard
- Extends: ADR-016: Define the Doxygen Reference Documentation Workflow
- Extends: ADR-017: Self-Host Build and Development Dependency Management
- Preserves: ADR-018: Three-Flavor Release Artifacts with Bash-Minifier
