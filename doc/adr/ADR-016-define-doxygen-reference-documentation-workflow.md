# ADR-016: Define the Doxygen Reference Documentation Workflow

Date: 2026-08-17

## Status

Proposed

## Intent and Scope

This Architecture Decision Record defines the development and publication workflow
used to turn bashdeps' ADR-014 Doxygen-style Bash comments into browsable reference
documentation.

The decision follows the established Bootstrap and mktext project pattern for
local generation: a root-level `Doxyfile`, an on-demand Bash Doxygen filter under
`vendor/`, generated HTML under `doc/reference/`, and `make docs` as the canonical
entry point.  For publication, bashdeps deliberately improves on Bootstrap's
current repository-stored output model by generating the documentation inside a
GitHub Actions Pages workflow and publishing that generated tree directly.

Generated Doxygen HTML is build output.  It SHALL NOT be committed to the bashdeps
repository.

This is development and documentation tooling only.  It does not add a runtime
dependency to `bashdeps.bash`, alter the public CLI, or change generated release
artifacts under `dist/`.

## Context

ADR-014 established a documentation-first source standard based on Bootstrap
ADR-045.  `src/bashdeps.bash` now uses structured Doxygen-style `##` comments for
file, function, and variable documentation.

That source documentation is useful directly in the maintained Bash file, but the
project needs a reproducible way to render it into navigable reference material.
Bootstrap and mktext solve the local-generation portion of the same problem with
Doxygen and the `bash-doxygen` AWK input filter maintained at:

```text
https://github.com/wesley-dean/bash-doxygen
```

Both projects expose documentation generation through Make rather than requiring
contributors to remember raw Doxygen commands or filter setup.

Bootstrap also publishes `doc/reference/` through a GitHub Pages workflow.  Its
current workflow assumes generated reference files are already present in the
repository and uploads that directory.  bashdeps does not need to preserve that
implementation detail: GitHub Actions can generate the same directory from the
maintained source immediately before publishing it.

Generating at deployment time removes a large set of reproducible HTML, CSS,
JavaScript, and image assets from source control while preserving both local
reviewability and hosted documentation.

## Decision Drivers

- Reuse the established Bootstrap and mktext local Doxygen workflow.
- Keep `make docs` as the canonical documentation-generation entry point locally
  and in CI.
- Generate reference material from maintained source rather than distribution
  artifacts.
- Keep the Bash-specific Doxygen preprocessing rule explicit and inspectable.
- Avoid committing downloaded development tooling as maintained project source.
- Treat generated Doxygen output as reproducible build state rather than source.
- Publish current documentation automatically from the default branch.
- Prevent stale generated HTML from surviving source renames or documentation
  removal.
- Keep ordinary `make clean` focused on normal build products while providing a
  broader cleanup target for generated documentation and downloaded tooling.
- Avoid a `docs-stage` workflow whose only purpose would be committing generated
  artifacts that Pages can build itself.

## Decision

### Canonical local entry point

The project SHALL provide:

```text
make docs
```

as the canonical command for generating browsable reference documentation.

The `docs` target SHALL:

1. remove any prior generated reference output;
2. ensure the Bash Doxygen filter is present locally;
3. create `doc/reference/` when necessary; and
4. invoke Doxygen using the repository root `Doxyfile`.

The resulting `doc/reference/` tree is local generated output suitable for
inspection in a browser.  It is not repository source and SHALL remain ignored by
Git.

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

The downloaded filter is development tooling.  It SHALL be ignored by Git and is
not part of the `bashdeps.bash` runtime dependency model or `dependencies.txt`.
Using bashdeps to bootstrap the filter needed only to document bashdeps would add
an unnecessary self-hosting dependency.

### Generated reference directory

Generated Doxygen output SHALL live under:

```text
doc/reference/
```

The complete directory SHALL be ignored by Git.

No generated reference file, including a README sentinel, SHALL be required in the
repository.  The maintained README, ADR-014, ADR-016, Makefile, and Doxyfile are
the documentation-generation source surfaces.

Generated files under `doc/reference/` SHALL NOT be edited manually.  They are
regenerated from maintained source with:

```text
make docs
```

### Documentation cleanup

The project SHALL provide:

```text
make docs-clean
```

`docs-clean` SHALL remove the complete generated `doc/reference/` directory.

Cleaning before every documentation generation prevents removed functions,
renamed files, or obsolete pages from remaining in the output tree.

### GitHub Pages publication

The repository SHALL provide:

```text
.github/workflows/static.yml
```

for GitHub Pages publication.

The workflow SHALL run on pushes to `main` and support manual
`workflow_dispatch` execution.  It SHALL:

1. check out the repository;
2. install Doxygen;
3. run `make docs`, thereby using the same generation path as local development;
4. configure GitHub Pages;
5. upload `doc/reference/` as the Pages artifact; and
6. deploy that artifact to the `github-pages` environment.

The workflow SHALL request only the permissions needed for repository checkout and
Pages deployment:

```text
contents: read
pages: write
id-token: write
```

The Pages workflow SHALL use GitHub's Pages deployment concurrency group and SHALL
NOT cancel an in-progress production deployment merely because a newer deployment
was queued.

Generated documentation SHALL exist only in the workflow workspace and the Pages
artifact.  Publishing documentation SHALL NOT create source-control commits.

### No documentation staging target

The project SHALL NOT provide a `docs-stage` target in version 1.

A staging target would imply that generated reference output belongs in source
control.  Since Pages generates and publishes the documentation directly from
maintained source, there is nothing generated that a maintainer should stage.

### Cleanup boundaries

The existing:

```text
make clean
```

SHALL remain focused on ordinary build output under `dist/`.

The project SHALL provide:

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

The Pages workflow SHALL install Doxygen explicitly rather than assuming the
hosted runner image happens to contain it.

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

### Commit generated Doxygen output

Bootstrap's current Pages workflow uploads a repository-resident
`doc/reference/` tree.  This works, but it duplicates reproducible output in Git
and requires maintainers to remember to regenerate and commit it whenever source
documentation changes.

bashdeps instead generates the site in the Pages workflow from the exact source
revision being deployed.  This keeps Git history focused on authoritative source
while guaranteeing that published reference documentation corresponds to the
committed `main` revision that triggered deployment.

### Provide `docs-stage`

A staging convenience is useful only when generated documentation is meant to be
committed.  Under the selected Pages model it would encourage the wrong workflow,
so it is intentionally omitted.

### Publish a prebuilt documentation artifact from another workflow

A separate validation workflow could build and retain the site for a later Pages
job.  The project does not need that indirection in version 1.  The Pages workflow
can invoke the canonical `make docs` target directly.

### Make `clean` remove all documentation tooling and output

That is the mktext behavior, but Bootstrap separates ordinary build cleanup from
broader generated-state cleanup.  bashdeps already has a focused `clean` target,
so `distclean` preserves that existing meaning while offering the broader cleanup
operation explicitly.

### Add Doxygen generation to `make all`

Documentation generation requires additional development tools and potentially a
network download on first use.  It is intentionally opt-in through `make docs` and
the Pages workflow and SHALL NOT become part of the ordinary build path.

## Consequences

Contributors can generate browsable source reference documentation locally with
one stable command shared conceptually with Bootstrap and mktext.

The repository gains a small development-tooling dependency on Doxygen and a
locally downloaded Bash filter when documentation generation is requested.

Generated HTML, CSS, JavaScript, images, indexes, and related Doxygen files do not
inflate repository history or require review as source changes.

GitHub Pages always builds from the maintained source revision being deployed,
reducing the chance of source/documentation drift.

`make docs` begins from a clean generated-output directory, reducing stale-page
risk.

Normal build, test, runtime, manifest, and release behavior remain unchanged.

## Follow-Ups

If the Bash Doxygen filter distribution model changes later, the local filter URL
or acquisition policy may be revised without changing the public bashdeps CLI.

A future CI decision may add documentation validation to pull requests, but
version 1 publishes Pages from `main` and does not make Doxygen generation part of
the ordinary test or release workflows.

## Related Decisions

- Related to: ADR-009
- Related to: ADR-010
- Implements generated-reference follow-up from: ADR-014
- Derived from: Bootstrap and mktext Doxygen/Make documentation scaffolding
- Publication model informed by: Bootstrap `.github/workflows/static.yml`
