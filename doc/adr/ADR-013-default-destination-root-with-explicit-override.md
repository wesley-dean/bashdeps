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

`dest=` remains the complete project-relative destination.  `--dest-root` is a
containment policy only: it tests whether the declared destination is permitted.
It does not prepend to, rewrite, relocate, or otherwise transform `dest=`.

This ADR supersedes earlier version 1 statements in ADR-002 and ADR-005 that
allowed any normalized repository-relative destination without an explicit CLI
override.  ADR-007 incorporates this option into the public `bashdeps.bash`
command surface.

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

During design review, two meanings for `--dest-root` were considered:

1. treat it as a prefix that is prepended to the manifest's `dest=` value; or
2. treat it as a security boundary against which the complete `dest=` value is
   tested.

The containment model better satisfies the principle of least surprise for this
project.  A reviewer who sees `dest=vendor/mktext.bash` in the manifest should be
able to conclude that the intended final path is `vendor/mktext.bash` without
also inspecting Makefiles, CI commands, or invocation flags for an additional
path prefix.

This differs deliberately from traditional installation `PREFIX` behavior.
`--dest-root` selects the permitted destination namespace; it does not select a
relocation prefix.

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
- Follow the principle of least surprise: `dest=` should visibly name the path
  that bashdeps will actually manage.
- Avoid invocation options that silently relocate otherwise unchanged manifest
  records.

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
dest=vendor-old/tool.bash
```

The destination root itself is a directory boundary and SHALL NOT be accepted as
a file destination.  A valid destination therefore contains at least one path
component beneath the selected root.

Containment SHALL be tested at a path-component boundary.  An implementation
MUST NOT use a naïve string-prefix test that would cause a root such as `vendor`
to permit a destination such as `vendor-old/tool.bash`.

Conceptually, after destination-root normalization, containment is equivalent to:

```bash
[[ $dest == "$dest_root/"* ]]
```

This expression illustrates the required component boundary; it does not replace
the other destination validation and filesystem-safety checks.

### Explicit alternate root

`install`, `sync`, and `verify` SHALL accept an invocation-level option:

```text
--dest-root PATH
```

The version 1 command forms are:

```text
bashdeps.bash install [--dest-root PATH] KEY=VALUE...
bashdeps.bash sync [--dest-root PATH] [MANIFEST]
bashdeps.bash verify [--dest-root PATH] [MANIFEST]
```

The option SHALL precede the manifest path or install declaration fields.

For example:

```text
bashdeps.bash sync --dest-root assets dependencies.txt
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

The selected destination root SHALL be a project-relative path.  It SHALL be
non-empty and SHALL NOT:

- be absolute;
- contain whitespace;
- contain repeated `/` separators within the path;
- contain a component equal to `.` or `..`.

Nested roots such as `third_party/vendor` MAY be selected.

For ordinary directory-argument ergonomics, one or more trailing `/` characters
MAY be supplied and SHALL be removed before validation and containment testing.
These forms are therefore equivalent:

```text
--dest-root vendor
--dest-root vendor/
```

and both select the normalized root:

```text
vendor
```

Trailing-slash normalization does not permit an absolute path, traversal,
interior repeated separators, or any other otherwise-invalid root.  For example,
`/vendor`, `vendor/../other`, and `third_party//vendor` remain invalid.

An invalid `--dest-root` value is invalid CLI input and SHALL return status 2.

### Manifest relationship

The manifest SHALL continue to contain the complete project-relative `dest`
value.  `--dest-root` SHALL NOT prepend to, rewrite, relocate, normalize into, or
otherwise transform `dest`.

For example:

```text
bashdeps.bash sync --dest-root third_party dependencies.txt
```

requires records to declare:

```text
dest=third_party/tool.bash
```

rather than:

```text
dest=tool.bash
```

The selected destination root changes only whether a destination is permitted.
It does not change the destination's meaning.

This keeps the manifest self-describing and makes destination changes visible in
source review.  Two invocations that accept the same manifest record therefore
do not materialize that record at different paths merely because their
`--dest-root` options differ.

`dest-root` SHALL NOT be a manifest field in version 1.  A dependency manifest
therefore cannot weaken its own destination boundary.  Unknown manifest fields
continue to fail closed.

### Filesystem safety remains cumulative

Selecting a destination root does not replace any existing filesystem-safety
rule.

The project root remains the physical current working directory from which
`bashdeps.bash` is invoked.

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

This resembles traditional installation `PREFIX` behavior and initially appeared
attractive because changing the option would relocate the same manifest beneath a
different tree.

It was rejected because it makes the visible `dest=` incomplete.  For example,
`dest=foo.bash` could become `vendor/foo.bash`, `assets/foo.bash`, or another path
depending on invocation state.  A reviewer would have to inspect the caller as
well as the manifest to determine the actual destination.

Version 1 instead keeps `dest` project-relative and complete.  `--dest-root` is
only an allowed-root constraint, so the manifest continues to say exactly where
the artifact will be materialized.

### Require `realpath` containment checks

Canonical path checks can be useful, but missing destinations complicate
portable use, `realpath` behavior differs across environments, and it would add a
runtime dependency.  The selected-root rule is combined with strict lexical path
validation and component-by-component symlink rejection instead.

### Reject a harmless trailing slash on `--dest-root`

Requiring `--dest-root vendor` while rejecting `--dest-root vendor/` would provide
one textual canonical form at the CLI boundary, but directory arguments commonly
appear with or without a trailing slash.  Normalizing trailing slashes before
validation avoids a surprising failure without weakening containment.

## Consequences

The ordinary manifest can write only beneath `vendor/`, substantially reducing
the set of project files it can affect.

Projects with another dependency layout can opt into one explicit alternate root
without disabling traversal or symlink protections.

A caller changing `--dest-root` changes security policy and should treat that
change as review-worthy Make/CI configuration.

The manifest remains self-describing because `dest` always contains the complete
project-relative path.

`--dest-root` does not provide relocation semantics.  Projects that need a true
installation-prefix mechanism would require a separate, explicitly named feature
and architectural decision.

Existing consumers that intentionally materialize dependencies outside `vendor/`
will need to pass `--dest-root` explicitly.

## Open Questions and Follow-Ups

Version 1 does not define an environment variable or repository configuration file
for destination-root policy.  A demonstrated consumer need may justify one later.

## Related Decisions

- Supersedes destination-scope portions of: ADR-002
- Supersedes destination-scope portions of: ADR-005
- Related to: ADR-007
- Related to: ADR-001
- Related to: ADR-003
- Related to: ADR-008
