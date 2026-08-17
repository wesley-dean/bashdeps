# ADR-013: Default Destination Root with Explicit Override

Date: 2026-08-17

## Status

Proposed

## Intent and Documentation Posture

This ADR tightens the version 1 destination policy so dependency artifacts are
confined beneath a dedicated directory by default while preserving an explicit,
reviewable escape hatch for projects with legitimate alternate layouts.

The default destination root is `vendor/`.  Callers may select a different
project-relative destination root for one invocation with `--dest-root PATH`.
The manifest itself cannot broaden the destination boundary.

This ADR supersedes earlier version 1 statements in ADR-002, ADR-005, and ADR-007
that allowed any normalized repository-relative destination without an explicit
CLI override.

## Context

The original destination model allowed any normalized path beneath the physical
current working directory.  Absolute paths, `..` traversal, symbolic-link path
components, and special destination file types were already rejected.

That model prevents obvious filesystem escape, but it still gives a trusted
manifest authority to replace arbitrary ordinary files inside the project tree.
For example, a manifest could intentionally target `Makefile`, source files, CI
configuration, or other project-owned files.

Most dependency consumers already place externally acquired artifacts beneath a
dedicated `vendor/` tree.  Making that convention the default security boundary
reduces the blast radius of an accidental or malicious manifest change while
retaining an explicit mechanism for projects that use another dedicated tree.

The resulting model is conceptually similar to a configurable installation
`PREFIX`, with one important distinction: `--dest-root` constrains the declared
`dest=` value; it does not rewrite or prepend text to that value.

## Decision Drivers

- Make the safe and conventional dependency layout the default.
- Prevent an ordinary manifest from targeting arbitrary project files.
- Preserve legitimate alternate dependency trees without disabling path safety.
- Keep the exception explicit in the invoking command or Makefile rather than in
  dependency-controlled manifest data.
- Preserve the existing physical-project-root, traversal, file-type, and symlink
  protections.
- Avoid adding `realpath` as a new mandatory runtime dependency.
- Keep destination semantics deterministic and easy to review.

## Decision

Version 1 SHALL define the default destination root as:

```text
vendor
```

Without an explicit override, every `dest` value SHALL name an ordinary file
strictly beneath that root.  For example:

```text
dest=vendor/mktext.bash
dest=vendor/templates/report.tmpl
dest=vendor/data/schema.json
```

The following SHALL be invalid under the default policy:

```text
dest=Makefile
dest=src/generated.bash
dest=assets/logo.png
dest=vendor
```

The destination root itself is a directory boundary and SHALL NOT be accepted as
a file destination.  A valid destination therefore contains at least one path
component beneath the selected root.

### Explicit alternate root

`install`, `sync`, and `verify` SHALL accept an invocation-level option:

```text
--dest-root PATH
```

The version 1 command forms become:

```text
bashdeps install [--dest-root PATH] KEY=VALUE...
bashdeps sync [--dest-root PATH] [MANIFEST]
bashdeps verify [--dest-root PATH] [MANIFEST]
```

The option SHALL precede the manifest path or install declaration fields.

For example:

```text
bashdeps sync --dest-root assets dependencies.txt
```

permits declarations such as:

```text
dest=assets/logo.png
```

while still rejecting:

```text
dest=vendor/tool.bash
dest=Makefile
dest=../outside
dest=/etc/passwd
```

for that invocation.

The selected destination root SHALL be a normalized project-relative path.  It
SHALL be non-empty and SHALL NOT:

- be absolute;
- contain whitespace;
- begin or end with `/`;
- contain repeated `/` separators;
- contain a component equal to `.` or `..`.

Nested roots such as `third_party/vendor` MAY be selected.

An invalid `--dest-root` value is invalid CLI input and SHALL return status 2.

### Manifest relationship

The manifest SHALL continue to contain the complete project-relative `dest`
value.  `--dest-root` SHALL NOT prepend to, rewrite, normalize into, or otherwise
transform `dest`.

For example:

```text
bashdeps sync --dest-root third_party dependencies.txt
```

requires records to declare:

```text
dest=third_party/tool.bash
```

rather than:

```text
dest=tool.bash
```

This keeps the manifest self-describing and makes destination changes visible in
source review.

`dest-root` SHALL NOT be a manifest field in version 1.  A dependency manifest
therefore cannot weaken its own destination boundary.  Unknown manifest fields
continue to fail closed.

### Filesystem safety remains cumulative

Selecting a destination root does not replace any existing filesystem-safety
rule.

The project root remains the physical current working directory from which
`bashdeps` is invoked.

Both the selected root and the complete destination path remain subject to the
existing rules that reject:

- absolute paths and traversal components;
- textual aliases such as `.` components and repeated separators;
- existing symbolic-link path components;
- an existing symbolic-link final destination;
- directories or special files where an ordinary destination file is expected.

A syntactically valid selected root that resolves through an existing symbolic
link is therefore rejected by the filesystem-safety layer when a declared path
is inspected.

Version 1 continues to document the limits of race resistance in a pure Bash
implementation rather than claiming `openat`-style concurrent filesystem safety.

### Parent directory creation

Missing directories beneath the selected destination root MAY be created with the
existing publication behavior.

For `sync`, directory creation SHALL occur only after complete manifest
validation and successful preflight of every required downloaded candidate.
For `install`, directory creation SHALL occur only after the declaration and
candidate have been validated.

No separate `--mkdir` option is required in version 1.

## Considered Alternatives

### Require `vendor/` with no override

This provides the narrowest policy and the least CLI surface.  It was rejected
because some legitimate consumers may keep externally managed artifacts beneath a
different dedicated project subtree.

### Continue allowing any repository-relative destination

This preserves maximum flexibility, but a manifest can then replace arbitrary
ordinary project files.  Requiring an explicit alternate root provides a better
secure-by-default posture.

### Add a manifest field such as `root=`

This would let the same data being constrained broaden its own write boundary.
The override is intentionally invocation policy rather than dependency data.

### Interpret `--dest-root` as a prefix to prepend to `dest`

This resembles traditional installation `PREFIX` behavior but makes the
manifest's visible destination incomplete.  Version 1 instead keeps `dest`
project-relative and uses the option only as an allowed-root constraint.

### Require `realpath` containment checks

Canonical path checks can be useful, but missing destinations complicate
portable use, `realpath` behavior differs across environments, and it would add a
runtime dependency.  The selected-root rule is combined with strict lexical path
validation and component-by-component symlink rejection instead.

## Consequences

The ordinary manifest can write only beneath `vendor/`, substantially reducing
the set of project files it can affect.

Projects with another dependency layout can opt into one explicit alternate root
without disabling traversal or symlink protections.

A caller changing `--dest-root` changes security policy and should treat that
change as review-worthy Make/CI configuration.

The manifest remains self-describing because `dest` always contains the complete
project-relative path.

Existing consumers that intentionally materialize dependencies outside `vendor/`
will need to pass `--dest-root` explicitly.

## Open Questions and Follow-Ups

Version 1 does not define an environment variable or repository configuration file
for destination-root policy.  A demonstrated consumer need may justify one later.

## Related Decisions

- Supersedes destination-scope portions of: ADR-002
- Supersedes destination-scope portions of: ADR-005
- Supersedes command-form portions of: ADR-007
- Related to: ADR-001
- Related to: ADR-003
- Related to: ADR-008
