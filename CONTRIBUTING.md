# Welcome

I'm so glad you're thinking about contributing to an open source project.
If you're unsure about anything, just ask -- or submit the issue
or pull request anyway. The worst that can happen is you'll be
politely asked to change something. I love all friendly contributions!

I encourage you to read this project's CONTRIBUTING policy
(you are here), its [LICENSE](LICENSE.md), and its [README](/README.md).

## Policies

To ensure a welcoming environment for all of our project, I request that
all contributors should adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## Commit messages and release versioning

Release versioning is calculated from the message of the commit that becomes
`HEAD` on `main`.  Issue titles, issue labels, pull-request labels, and the
messages of earlier commits in a pull request do not directly select the release
version increment.

The release workflow uses a Conventional Commits-style prefix recognized by the
pinned semantic-version action:

- `feat:` increments the minor version;
- `BREAKING CHANGE:` increments the major version;
- `build:`, `chore:`, `ci:`, `docs:`, `fix:`, `perf:`, `refactor:`, `revert:`,
  `style:`, and `test:` increment the patch version; and
- an unrecognized prefix also falls back to a patch increment.

Consequently, the final commit placed on `main` must carry the intended prefix.
With a squash merge, this normally means making the squash commit subject conform
to the rule.  With a traditional merge commit, the merge commit message itself is
the relevant message; a default `Merge pull request ...` subject is not recognized
as a feature or breaking-change declaration and therefore produces a patch bump.

For example, a backward-compatible feature intended to move `v0.0.12` to
`v0.1.0` should land on `main` with a commit subject such as:

```text
feat: add manifest update support
```

A breaking change must begin with the exact form recognized by the current
versioning action, for example:

```text
BREAKING CHANGE: revise manifest grammar
```

This repository's current automation does not infer release significance from an
issue's `enhancement` label or from the issue title.

## Public domain

This project is in the public domain within the United States, and copyright
and related rights in the work worldwide are waived through the
[CC0 1.0 Universal public domain dedication](https://creativecommons.org/publicdomain/zero/1.0/).

All contributions to this project will be released under the CC0 dedication.
By submitting a pull request or issue, you are agreeing to comply with
this waiver of copyright interest.
