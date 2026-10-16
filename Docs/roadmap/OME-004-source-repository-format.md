---
id: OME-004
type: roadmap-card
area: source
kind: data-format
priority: high
created: "2026-06-09"
---

# Source Repository Format

## Summary

Defined organizer-owned source repositories for calendars and events.

## Why

Organizers need a durable, reviewable source of truth that can be imported into the app and proposed against.

## Rough Shape

- Use calendar files, event folders, YAML records, Markdown contributor files, schedules, posters, stages, and channels.
- Keep fixtures as executable examples of the current file layout.
- Code pointers: `Sources/OpenMusicEventSource`, `Tests/OpenMusicEventSourceTests/Fixtures/Organizer`.

## Open Questions

- Which parts of the source format should remain flexible while the app workflows settle?

## Next Step

- Keep source format changes covered by parser and insertion tests.
