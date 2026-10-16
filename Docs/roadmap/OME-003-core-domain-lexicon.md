---
id: OME-003
type: roadmap-card
area: domain
kind: model
priority: high
created: "2026-06-09"
---

# Core Domain Lexicon

## Summary

Modeled the core OpenMusicEvent records and supporting value types.

## Why

The app needs a Swift-first domain model that can still map cleanly to ATProto-ready record shapes.

## Rough Shape

- Cover organizers, calendars, events, stages, schedules, performances, contributors, posters, channels, images, and policies.
- Keep record identity explicit without making ATProto the first user-facing concept.
- Code pointers: `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventLexicon/MusicEvent.swift`.

## Open Questions

- Which record shapes should become first-class published ATProto records first?

## Next Step

- Let the editing and AppView work identify the first narrow publishing boundary.
