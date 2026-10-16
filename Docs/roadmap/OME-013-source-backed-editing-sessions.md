---
id: OME-013
type: roadmap-card
area: editing
kind: infrastructure
priority: high
created: "2026-06-09"
---

# Source-Backed Editing Sessions

## Summary

Materialize editable sessions from a source repository baseline and local database state.

## Why

The app needs to know what changed, what baseline it changed from, and whether the source has drifted.

Organizers should not have to think in source files, branches, or repository state. Source-backed sessions are the machinery that lets the app remain the authoring surface while still producing portable, reviewable, source-controlled changes.

## Rough Shape

- Build editing sessions around source provenance and baseline database state.
- Track invalidations when local edits no longer match the source baseline.
- Keep source/Git/Tangled concepts behind organizer-friendly language such as workspace, draft, review, proposed changes, and publish.
- Let app-authored edits produce source diffs from coherent local state instead of asking the organizer to manage source directly.
- Treat source drift and baseline invalidation as recoverable workflow states, not as primary app vocabulary.
- Code pointers: `Sources/OpenMusicEventSourceEditing`, `Sources/SourceEditing`, `Tests/SourceEditingTests`.

## Open Questions

- How visible should source drift and invalidation be to non-technical organizers?
- Which source-backed states need organizer copy, and which should remain maintainer/debug detail?

## Next Step

- Keep invalidation tests close to each new editable event surface.
