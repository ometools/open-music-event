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

## Rough Shape

- Build editing sessions around source provenance and baseline database state.
- Track invalidations when local edits no longer match the source baseline.
- Code pointers: `Sources/OpenMusicEventSourceEditing`, `Sources/SourceEditing`, `Tests/SourceEditingTests`.

## Open Questions

- How visible should source drift and invalidation be to non-technical organizers?

## Next Step

- Keep invalidation tests close to each new editable event surface.
