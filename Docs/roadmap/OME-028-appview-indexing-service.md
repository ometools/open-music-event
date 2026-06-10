---
id: OME-028
type: roadmap-card
area: service
kind: appview
priority: high
created: "2026-06-09"
---

# AppView / Indexing Service

## Summary

Define the service boundary for indexing public OpenMusicEvent records and serving app-friendly queries.

## Why

The app will eventually need network-backed discovery and query APIs without making the local database a premature service contract.

## Rough Shape

- Index public OpenMusicEvent records once publishing exists.
- Serve app-friendly queries for discovery and browsing.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventSource`.

## Open Questions

- What is the minimum useful query surface for the first AppView?
- Which parts of the local database shape should not leak into the service API?

## Next Step

- Draft the service boundary after the first publishable records are chosen.
