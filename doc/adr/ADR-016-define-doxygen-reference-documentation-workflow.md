# ADR-016: Define the Doxygen Reference Documentation Workflow

Date: 2026-08-17

## Status

Proposed

## Intent and Scope

This Architecture Decision Record defines the development workflow used to turn
bashdeps' ADR-014 Doxygen-style Bash comments into browsable reference
documentation.

The decision intentionally follows the established Bootstrap and mktext project
pattern: a root-level `Doxyfile`, an on-demand Bash Doxygen filter under
`vendor/`, generated HTML under `doc/reference/`, and Make targets that make
regeneration and cleanup explicit.

This is development and documentation tooling only.  It does not add a runtime
dependency to `bashdeps.bash`, alter the public CLI, or change generated release
artifacts under `dist/`.

## Context

ADR-014 established a documentation-first source standard based on Bootstrap
ADR-045.  `src/bashdeps.bash` now uses structured Doxygen-style `##` comments for
file, function, and variable documentation.

That source documentation is useful directly in the maintained Bash file, but
the project currently lacks the scaffolding needed to render it into navigable
reference material.  Bootstrap and mktext solve the same problem with Doxygen and
the `bash-doxygen` AWK input filter maintained at:

```text
https://github.com/wesley-dean/bash-doxygen
```

Both projects expose documentation generation through Make rather than requiring
contributors to remember raw Doxygen commands or filter setup.

bashdeps should use the same operational model so documentation generation is
predictable across the related Bash projects.

## Decision Drivers

- Reuse the established Bootstrap and mktext documentation workflow.
- Keep `make docs` as the canonical documentation-generation entry point.
- Generate reference material from maintained source rather than distribution
  artifacts.
- Keep the Bash-specific Doxygen preprocessing rule explicit and inspectable.
- Avoid committing downloaded development tooling as maintained project source.
- Keep generated reference output separate from hand-maintained prose and ADRs.
- Prevent stale generated HTML from surviving source renames or documentation
  removal.
- Preserve a README sentinel that explains how `doc/reference/` is produced.
- Keep ordinary `make clean` focused on normal build products while providing a
  broader cleanup target for generated documentation and downloaded tooling.

## Decision

### Canonical entry point

The project SHALL provide:

```text
make docs
```

as the canonical command for generating browsable reference documentation.

The `docs` target SHALL:

1. remove stale generated reference output while preserving the hand-maintained
   `doc/reference/README.md` sentinel;
2. ensure the Bash Doxygen filter is present locally;
3. create `doc/reference/` when necessary; and
4. invoke Doxygen using the repository root `Doxyfile`.

### Doxygen configuration

The repository SHALL contain a root-level:

```text
Doxyfile
```

The configuration SHALL:

- identify the project as `bashdeps`;
- use `src/bashdeps.bash` as the maintained documentation input;
- process `*.bash` files through the Bash Doxygen AWK filter;
- generate HTML reference documentation under `doc/reference/`;
- disable LaTeX, man-page, RTF, and XML generation for version 1;
- exclude tests, generated distribution artifacts, and vendored tooling from
  documentation input; and
- retain the warning posture used by Bootstrap and mktext.

Generated documentation SHALL describe maintained source.  `dist/bashdeps.bash`
and `dist/bashdeps.dev.bash` SHALL NOT be Doxygen input because they are generated
artifacts under ADR-009.

### Bash Doxygen filter

The Makefile SHALL define the local filter path as:

```text
vendor/doxygen-bash.awk
```

and the upstream source as:

```text
https://raw.githubusercontent.com/wesley-dean/bash-doxygen/refs/heads/main/doxygen-bash.awk
```

When the filter is absent, its Make target SHALL download it to a temporary file,
make the resulting file executable, and rename it into place only after the
transfer succeeds.

The downloaded filter is development tooling.  It is not part of the
`bashdeps.bash` runtime dependency model and is not managed by `dependencies.txt`.
Using bashdeps to bootstrap the filter that is needed only to document bashdeps
would add an unnecessary self-hosting dependency.

### Generated reference directory

Generated Doxygen output SHALL live under:

```text
doc/reference/
```

The directory SHALL contain a hand-maintained `README.md` sentinel explaining
that the remaining content is generated and is regenerated with:

```text
make docs
```

Generated files under `doc/reference/` SHALL NOT be edited manually.

The generated HTML MAY be committed so it can be browsed directly from repository
artifacts and reviewed alongside documentation changes.  The source comments and
Doxyfile remain authoritative inputs; generated HTML is reproducible output.

### Documentation cleanup

The project SHALL provide:

```text
make docs-clean
```

`docs-clean` SHALL remove generated contents beneath `doc/reference/` while
preserving `doc/reference/README.md`.

Cleaning before every documentation generation prevents removed functions,
renamed files, or obsolete pages from remaining in the output tree.

### Documentation staging

The project SHALL provide:

```text
make docs-stage
```

`docs-stage` SHALL depend on `docs` and then stage the complete generated
`doc/reference/` change set with Git.  This includes deletions so stale generated
files are removed from a documentation update rather than remaining tracked.

The target is a convenience for maintainers.  It does not alter the requirement
to review generated documentation before committing it.

### Cleanup boundaries

The existing:

```text
make clean
```

SHALL remain focused on ordinary build output under `dist/`.

The project SHALL add:

```text
make distclean
```

which SHALL extend normal cleanup by:

- running `docs-clean`;
- removing `vendor/doxygen-bash.awk` when present; and
- removing the empty `vendor/` directory when possible.

This separation keeps normal build cleanup unsurprising while still providing a
single command that returns the checkout close to a fresh development state.

### Development dependency boundary

Doxygen and the filter-fetching command are development-time requirements for
`make docs`; they are not runtime requirements for `bashdeps.bash`.

The Make target MAY rely on `curl`, matching the established Bootstrap and mktext
documentation scaffolding.  This use of curl is independent of bashdeps' runtime
downloader abstraction because it belongs to repository development tooling, not
the shipped CLI.

## Considered Alternatives

### Generate documentation directly from `dist/bashdeps.dev.bash`

The developer artifact retains source comments, but it is generated state with
injected build metadata.  Generating documentation from maintained source keeps
the documentation pipeline anchored to the authoritative implementation and
avoids making `make docs` depend on `make build`.

### Commit the Bash Doxygen filter

Committing the filter would eliminate the first-run download but would make a
separate upstream tool appear to be maintained bashdeps source.  The established
Bootstrap and mktext pattern downloads the filter on demand, and bashdeps adopts
that convention for consistency.

### Ignore generated reference documentation

Keeping HTML exclusively local would reduce repository churn, but it would also
remove the `docs-stage` review workflow used by Bootstrap and make generated
reference material less accessible to repository readers.  Version 1 therefore
permits generated reference output to be committed while keeping it clearly
identified as generated.

### Make `clean` remove all documentation tooling and output

That is the mktext behavior, but Bootstrap separates ordinary build cleanup from
broader generated-state cleanup.  bashdeps already has a focused `clean` target,
so `distclean` preserves that existing meaning while offering the broader cleanup
operation explicitly.

### Add Doxygen generation to `make all`

Documentation generation requires additional development tools and potentially a
network download on first use.  It is intentionally opt-in through `make docs` and
SHALL NOT become part of the ordinary build path.

## Consequences

Contributors can generate browsable source reference documentation with one
stable command shared conceptually with Bootstrap and mktext.

The repository gains a small development-tooling dependency on Doxygen and a
locally downloaded Bash filter when documentation generation is requested.

Generated documentation can be reviewed and committed without being mistaken for
hand-maintained prose.

`make docs` begins from a clean generated-output directory, reducing stale-page
risk.

Normal build, test, runtime, manifest, and release behavior remain unchanged.

## Follow-Ups

If the Bash Doxygen filter distribution model changes later, the local filter URL
or acquisition policy may be revised without changing the public bashdeps CLI.

A future CI decision may choose to regenerate or validate reference documentation,
but version 1 does not require `make docs` to run as part of ordinary Tests,
CodeQL, or release workflows.

## Related Decisions

- Related to: ADR-009
- Related to: ADR-010
- Implements generated-reference follow-up from: ADR-014
- Derived from: Bootstrap and mktext Doxygen/Make documentation scaffolding
