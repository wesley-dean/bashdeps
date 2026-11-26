# ADR-026: Migrate Routine Dependency Updates to Centrally Managed Renovate

Date: 2026-11-26

## Status

Accepted

## Decision

The repository SHALL use the centrally managed Jenkins-hosted Renovate
service for routine dependency version updates.  Enrollment SHALL be
explicit through a minimal root `renovate.json`.  Each configured
Dependabot version-update ecosystem SHALL set
`open-pull-requests-limit: 0` while retaining its other ecosystem,
directory, schedule, cooldown, grouping, and commit conventions.

Dependabot security updates, dependency graph, and vulnerability alerts
SHALL remain separate from Renovate routine updates.  The existing
`dependabot[bot]`-scoped non-major automatic merge request workflow SHALL
remain applicable only to Dependabot PRs, including security updates.
Renovate SHALL continue to require GitHub protections, CI gates, and
human code-owner approval; no bypass or automatic approval is authorized.

**This decision partially supersedes ADR-025**, specifically its
designation of scheduled Dependabot updates as the active routine-update
provider and its prohibition against a restrictive routine PR limit.
The earlier ADR remains authoritative for its independent security
response, dependency review, supply-chain boundaries, and review safeguards.
The previous decision remains in the ADR corpus as historical context.

## Context and Constraints

The prior weekly grouped Dependabot policy was adopted to reduce routine PR
noise.  A self-hosted Renovate service has since been established under
Jenkins, with centrally managed policy, signed commits, and native
platform auto-merge subject to required approval.  Continuing both
routine update providers would duplicate PRs and review effort.

This project's specific trust boundaries include Bashdeps bootstrap, verified dependency manifests, and release artifacts.
Existing immutable GitHub Actions pins, SHA-256-verified build dependencies,
and imported coding standards remain unchanged.  The migration must not
alter runtime APIs, artifacts, release contracts, dependency trust, or
network behavior.

## Assumptions

- The Jenkins job discovers `wesley-dean/*` but requires the repository's
  explicit Renovate enrollment to process it.
- The `wesley-dean-renovate` account must have accepted write-level
  collaborator access and cannot bypass mandatory approval or checks.
- GitHub alerts and security-update settings are independently configured.
  A repository file does not prove their effective state.
- The centralized runner manages its own schedules and configuration, so
  this repository adds no Renovate credentials, jobs, or workflows.

These are assumptions to verify operationally, not proven outcomes.

## Options Considered

1. **Keep Dependabot for scheduled version updates.** Rejected: duplicates
   the existing central Renovate service.
2. **Delete Dependabot configuration.** Rejected: preserving metadata,
   historical policy, and the security-update boundary is preferable.
3. **Deploy Renovate independently per repository.** Rejected: duplicates
   scheduling, credentials, signing, and operational maintenance.
4. **Apply Dependabot-specific auto-merge logic to Renovate.** Rejected:
   this would blur bot identity and approval requirements.
5. **Replace immutable dependency SHAs with floating tags.** Rejected:
   weakens supply-chain protections.

## Migration and Compatibility

The change adds root `renovate.json`, disables scheduled Dependabot
version-update PR creation, updates maintained documentation, and may correct
GitHub Actions comment annotations to verified, Renovate-compatible
release tags.  No executable action SHA shall change as part of a
comment-only migration.  If an upstream tag cannot be verified, the pin and
its existing annotation are left untouched and reported.

Existing routine Dependabot PRs remain open until the migration has merged
and Renovate enrollment is effective.  Only conclusively routine PRs may be
closed afterward with an explanatory comment linking the migration.
Security PRs, ambiguous cases, and human-authored changes remain for review.

The effective availability of Dependabot security updates, branch protections,
required review, and Renovate machine-account access must be verified
independently.  CI or Jenkins execution shall not be claimed without
observed evidence.

## Consequences and Threat Model

Central Renovate gains repository branch and pull-request write authority.
A compromised bot credential, GitHub Action, or dependency release can
affect CI and publication.  Preserve least privilege, signed commits,
immutable SHA pins, CODEOWNER approval, required checks, and targeted
review for privileged release and artifact-publishing actions.
Central policy reduces local duplication but creates operational dependence
on the shared Jenkins runner.

## Related Decisions

- ADR-025: Previous grouped Dependabot maintenance policy,
  partially superseded by this decision.
- Other accepted ADRs governing build dependencies, artifact publication,
  runtime contracts, and coding standards remain in force.
