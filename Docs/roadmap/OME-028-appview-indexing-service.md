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

Define the service boundary for indexing OpenMusicEvent records and serving app-friendly event data.

## Why

The app will eventually need network-backed discovery and query APIs without making the local database a premature service contract. The first AppView slice should support Wicked Woods organizer-published event data before community discovery.

## Rough Shape

```gpt-5
- Start with OME-owned, source-managed event records and source-derived projections.
- Serve a [[OME-070-wicked-woods-appview-event-snapshot|Wicked Woods event snapshot]] before building broad community discovery.
- Keep the API compatible with cacheable bundles or object-store publishing because event source data is read-heavy.
- Treat community-calendar ingestion, RSVP counts, public favorites, and public attendance as later AppView phases.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventSource`, `Sources/OpenMusicEventLexicon`, and the AppView baseline workspace.
```

## Open Questions

- What is the minimum useful query surface for the first AppView?
- Which parts of the local database shape should not leak into the service API?
- Should the first AppView data source be indexed ATProto records, source-derived SQLite projections, generated bundles, or a hybrid?
- What cache headers, manifests, and invalidation rules are needed for a Wicked Woods event snapshot?

## Next Step

- Draft the Wicked Woods event snapshot boundary and connect it to the source release / OME publish pipeline.
