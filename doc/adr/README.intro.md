# Architecture Decision Records

Architecture Decision Records preserve the reasoning behind consequential
technical and process decisions in bashdeps.  They document the constraints,
tradeoffs, rejected alternatives, compatibility expectations, and failure models
that shape both `bashdeps.bash` and `manifest-manager.bash`.

The repository uses several complementary documentation layers:

- ADRs explain why durable architectural decisions exist and what constraints
  follow from them.
- [`doc/decisions.md`](../decisions.md) provides concise summaries and navigation
  for the decision corpus.
- [`doc/bashdeps-spec.md`](../bashdeps-spec.md) describes the accepted runtime
  behavior of `bashdeps.bash`.
- [`doc/manifest-manager-spec.md`](../manifest-manager-spec.md) describes the
  accepted maintainer-facing behavior of `manifest-manager.bash`.
- [`doc/documentation-standard.md`](../documentation-standard.md) governs source
  documentation for new maintained Bash work in this repository.
- Doxygen reference pages preserve implementation-level contracts close to the
  maintained source.

The ADRs remain authoritative when a shorter summary or generated navigation
surface appears to disagree with them.

## Index
