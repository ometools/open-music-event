---
id: OME-020
type: roadmap-card
area: database
kind: feature
priority: medium
created: "2026-06-09"
---

# Event Search

## Summary

Add local event search over durable event metadata and indexed display text.

## Why

Attendees need fast local discovery inside imported calendars and events.

## Rough Shape

- Keep the search index in the database layer.
- Let UI features consume search without owning indexing rules.
- Code pointers: `Sources/OpenMusicEventDatabase/EventSearch.swift`, `Tests/OpenMusicEventDatabaseTests/DatabaseMigrationTests.swift`.

## Open Questions

- What should the first app-level search surface include beyond events?

## Next Step

- Finish database-backed search before expanding UI discovery scope.
