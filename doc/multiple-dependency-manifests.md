# Multiple Dependency Manifests

Bashdeps supports an explicit manifest path for `sync` and `verify`.  A consuming
project can therefore use more than one dependency manifest when different
repository operations need different external artifacts.

This is a consumer orchestration pattern rather than a change to the bashdeps
manifest grammar.  Individual dependency records still use the same four fields:

```text
id=...
url=...
dest=...
digest=sha256:...
```

Do not add fields such as `type=`, `dev=`, or `scope=` merely to distinguish why a
dependency exists.  Current bashdeps releases reject unknown fields deliberately.
The Makefile target that selects a manifest supplies the dependency role.

## Separate dependencies by consumer purpose

A project might use manifests such as:

```text
dependencies.txt
dependencies-docs.txt
dependencies-test.txt
```

The names beyond the conventional `dependencies.txt` filename belong to the
consuming project.  Bashdeps does not assign meaning to `docs`, `test`, `dev`, or
other role names.

One possible layout is:

```text
dependencies.txt
    -> artifacts consumed by the ordinary build

dependencies-docs.txt
    -> documentation-only tooling such as bash-doxygen

dependencies-test.txt
    -> test-only fixtures or tools
```

This keeps a build from acquiring documentation or test dependencies it does not
consume, while retaining the same exact URL-and-digest trust model for every
artifact.

For example, a documentation manifest might contain:

```text
id=wesley-dean/bash-doxygen@0.0.6 url=https://raw.githubusercontent.com/wesley-dean/bash-doxygen/v0.0.6/doxygen-bash.awk dest=vendor/doxygen-bash.awk digest=sha256:dc09bccac7cdb69940b2b34f0c2a92d862c5979d578364ec66782ac92338a3ea
```

A build manifest can independently contain only artifacts the build actually
needs.

## Select manifests explicitly from Make

The bootstrap boundary does not change.  Make directly owns the pinned,
SHA-256-verified `vendor/bashdeps.bash` bootstrap.  Each role-specific dependency
target then invokes that verified bootstrap with the appropriate manifest.

For a project with build and documentation dependencies, the relevant Make targets
can look like:

```make
BASHDEPS := vendor/bashdeps.bash
BUILD_DEPS := dependencies.txt
DOCS_DEPS := dependencies-docs.txt

.PHONY: deps deps-check deps-docs deps-docs-check

deps: $(BASHDEPS) $(BUILD_DEPS)
	$(MAKE) --no-print-directory verify-bashdeps
	"$(BASHDEPS)" sync "$(BUILD_DEPS)"

deps-check: verify-bashdeps $(BUILD_DEPS)
	"$(BASHDEPS)" verify "$(BUILD_DEPS)"

deps-docs: $(BASHDEPS) $(DOCS_DEPS)
	$(MAKE) --no-print-directory verify-bashdeps
	"$(BASHDEPS)" sync "$(DOCS_DEPS)"

deps-docs-check: verify-bashdeps $(DOCS_DEPS)
	"$(BASHDEPS)" verify "$(DOCS_DEPS)"
```

The `$(BASHDEPS)` bootstrap target above is the same independently pinned and
verified bootstrap described in the README's consumer Make integration example.

`deps` and `deps-docs` may use the network because `sync` may need to acquire
missing or stale artifacts.  Their corresponding `*-check` targets use `verify`
and should remain offline and non-repairing.

A documentation target can then prepare only documentation dependencies:

```make
docs: deps-docs
	doxygen Doxyfile
```

The normal build does not need to know that `dependencies-docs.txt` exists.

## Projects with no build dependencies

A project does not need to invent a build dependency merely to preserve a common
Make target name.  If the ordinary build consumes no external artifacts, `deps`
and `deps-check` may be explicit no-op targets while role-specific operations
prepare only what they need:

```make
.PHONY: all build deps deps-check deps-docs deps-docs-check docs

all: deps
	$(MAKE) --no-print-directory build

deps:
	@:

deps-check:
	@:

deps-docs: $(BASHDEPS) dependencies-docs.txt
	$(MAKE) --no-print-directory verify-bashdeps
	"$(BASHDEPS)" sync dependencies-docs.txt

deps-docs-check: verify-bashdeps dependencies-docs.txt
	"$(BASHDEPS)" verify dependencies-docs.txt

docs: deps-docs
	doxygen Doxyfile
```

With that arrangement, `make all` does not bootstrap bashdeps or reach the network
merely because documentation has an external tool dependency.  `make docs` may
bootstrap and synchronize documentation state when needed.

A project that prefers a uniform manifest-based `deps` implementation can instead
commit an empty valid `dependencies.txt`; bashdeps accepts an empty manifest.
That approach retains one common target shape at the cost of establishing the
bootstrap even when the build has no ordinary dependencies to synchronize.

## Keep build boundaries explicit

Multiple manifests should make dependency ownership clearer rather than create
hidden acquisition paths.

A useful target contract is:

```text
make deps             synchronize ordinary build dependencies
make deps-check       verify ordinary build dependencies offline
make deps-docs        synchronize documentation dependencies
make deps-docs-check  verify documentation dependencies offline
make build            consume prepared build state without acquiring it
make docs             prepare documentation dependencies, then generate docs
make all              prepare only the dependencies required by the ordinary build,
                      then build
```

Additional roles such as tests can follow the same pattern when a repository
actually needs them.

Do not make `build` depend on `deps-docs`, and do not make an offline check target
depend on a Make target that can bootstrap or repair dependency state.

## Share vendor state carefully

Separate manifests may materialize artifacts beneath the same `vendor/` tree.
This is compatible with bashdeps because `sync` does not prune undeclared files.
Synchronizing `dependencies-docs.txt` therefore does not remove files declared
only by `dependencies.txt`, and vice versa.

Bashdeps validates duplicate identities and destinations within the manifest being
processed.  It does not compare one manifest with another.  The consuming project
therefore owns cross-manifest collision discipline.

Prefer one owning manifest for each destination.  In particular, avoid declaring
the same `dest=` path in multiple role manifests unless the duplication is
intentional, byte-identical, and documented by the consumer.

## Keep dependency meaning outside bashdeps

Multiple manifests preserve a useful architectural boundary:

```text
Make decides when and why a dependency set is needed.
Bashdeps decides whether the declared bytes are present and acceptable.
```

Bashdeps still does not become a package manager, understand dependency scopes,
or infer artifact purpose.  A manifest remains a reviewable declaration of exact
external bytes, while the consuming build system decides which declaration set is
appropriate for each operation.
