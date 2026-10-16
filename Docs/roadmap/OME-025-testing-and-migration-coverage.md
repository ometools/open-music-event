---
id: OME-025
type: roadmap-card
area: testing
kind: coverage
priority: high
created: "2026-06-09"
---

# Testing and Migration Coverage

## Summary

Cover core source, database, app, auth, editing, schedule, and shared UI behavior with focused package tests.

## Why

The app is moving through schema, source, editing, and platform changes; tests keep those seams honest.

## Rough Shape

- Keep migrations and source insertion covered as durable data changes.
- Keep feature tests focused on state, navigation, and source-backed editing behavior.
- Code pointers: `Tests`, `Tests/OpenMusicEventDatabaseTests`, `Tests/OpenMusicEventAppTests`.

## Open Questions

- Which workflows need UI automation once the app experience settles?

## Next Step

- Add tests next to each new source-backed editing or persistence slice.
