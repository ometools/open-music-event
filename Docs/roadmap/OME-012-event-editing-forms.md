---
id: OME-012
type: roadmap-card
area: editing
kind: feature
priority: high
created: "2026-06-09"
---

# Event Editing Forms

## Summary

Edit event details, calendars, stages, images, and policies from the native app.

## Why

Organizer-facing editing should happen in the app while still producing source-backed changes.

## Rough Shape

- Use focused form features so edits can be tested before they become source patches.
- Keep edit invalidation explicit when the baseline changes.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/EditEvent.swift`, `Sources/OpenMusicEventAppEventViewer/EditEventInfo.swift`, `Tests/OpenMusicEventAppTests/EditEventSourcePatchInvalidationTests.swift`.

## Open Questions

- Which edit forms are required before the first organizer review workflow feels complete?

## Next Step

- Fill gaps in source-backed forms one small event surface at a time.
