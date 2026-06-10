---
id: OME-006
type: roadmap-card
area: database
kind: persistence
priority: high
created: "2026-06-09"
---

# Local Database and Import Pipeline

## Summary

Added the local SQLite schema, migrations, import insertion, image storage, source provenance, and downloaded source bookkeeping.

## Why

The app needs fast local browsing and editing over imported source data, including provenance back to the source repository.

## Rough Shape

- Import source-backed event data into local app storage.
- Keep durable metadata, provenance, images, and search-friendly data in the database layer.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Tests/OpenMusicEventDatabaseTests`.

## Open Questions

- Which imported fields should remain source-only versus database-derived cache data?

## Next Step

- Keep migrations tested as new persisted fields are added.
