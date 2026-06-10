---
id: OME-042
type: roadmap-card
area: appview
kind: api
priority: high
created: "2026-06-09"
---

# AppView Query Surface

## Summary

Define the first concrete OpenMusicEvent AppView queries for app-friendly discovery and browsing.

## Why

The broad AppView service card needs a narrow query surface before implementation can start without overfitting the local database.

## Rough Shape

- Start with queries for event lookup, organizer calendars, event search, and contributor profile lookup.
- Keep local database shape useful to the app without making it the public service contract.
- Defer broad indexing and ranking policy until the first queries are proven.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventSource`, `Sources/OpenMusicEventLexicon`.

## Open Questions

- Which query is the smallest useful AppView endpoint?
- Which response shapes should be app-specific versus lexicon record-shaped?

## Next Step

- Pick one query and write its desired request/response shape before building service infrastructure.
