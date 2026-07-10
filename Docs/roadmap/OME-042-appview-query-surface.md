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

The query surface is also where "write once, display everywhere" becomes real. The same event graph should be able to power the native app, public web pages, schedule/list embeds, QR/App Clip routes, and third-party renderers without copying content into separate CMS shapes.

## Rough Shape

- Start with queries for event lookup, organizer calendars, event search, and contributor profile lookup.
- Keep local database shape useful to the app without making it the public service contract.
- Defer broad indexing and ranking policy until the first queries are proven.
- Add public-display query shapes that can support:
  - event landing pages
  - schedule embeds
  - stage/venue pages
  - public map/site-map projections
  - communication channel listings
  - QR/App Clip fallback pages
- Keep response shapes domain-specific and stable enough for external renderers, while allowing the first-party app to keep richer local projections.
- Treat public ATProto data as permissionless rendering substrate. Alternate branded or custom experiences can exist outside the first-party app without forcing infinite customization into OME itself.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventSource`, `Sources/OpenMusicEventLexicon`.

## Open Questions

- Which query is the smallest useful AppView endpoint?
- Which response shapes should be app-specific versus lexicon record-shaped?
- Which first public display surface proves the AppView boundary best: event page, schedule embed, or QR fallback page?

## Next Step

- Pick one query and write its desired request/response shape for both first-party app use and at least one public display surface before building service infrastructure.
