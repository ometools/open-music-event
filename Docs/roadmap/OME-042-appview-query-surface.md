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

Define the first concrete OpenMusicEvent AppView queries for app-friendly event loading.

## Why

The broad AppView service card needs a narrow query surface before implementation can start without overfitting the local database. The first query should serve Wicked Woods event data, not community discovery.

The query surface is also where "write once, display everywhere" becomes real. The same event graph should be able to power the native app, public web pages, schedule/list embeds, QR/App Clip routes, and third-party renderers without copying content into separate CMS shapes.

## Rough Shape

```gpt-5
- Start with one [[OME-070-wicked-woods-appview-event-snapshot|event snapshot query]] for a known source-managed event.
- Include event identity, stages, performances, schedule rows, poster/site-map references, and source/publish provenance needed by the app.
- Keep local favorites and personal schedule state out of the hosted response in the first slice.
- Defer organizer calendar browsing, event search, contributor profile lookup, community discovery, and ranking policy until the event snapshot is proven.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventSource`, `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventAppEventViewer`.
```

## Open Questions

- Which query is the smallest useful AppView endpoint?
- Which response shapes should be app-specific versus lexicon record-shaped?
- Should the first endpoint identify an event by source reference, OME AT URI, public slug, or a generated snapshot ID?
- Which parts of the response should be record-shaped, and which should be hydrated app projection?

## Next Step

- Write the Wicked Woods event snapshot request/response shape before building broader service infrastructure.
