---
id: OME-070
type: roadmap-card
area: appview
kind: api
tags:
  - wicked-woods
  - appview
  - organizer
launch: wicked-woods
priority: high
created: "2026-06-17"
---

# Wicked Woods AppView Event Snapshot

## Summary

```gpt-5
Serve the first hosted/AppView-backed event snapshot for Wicked Woods from OME source-published data, before building community discovery.
```

## Why

```gpt-5
The first AppView value for Wicked Woods is not global community browsing. It is a stable hosted surface for event-ready OME data: event details, stages, performances, posters, site map, schedule data, and links that native apps, App Clips, QR routes, and white-label builds can consume.
```

## Rough Shape

```gpt-5
- Start with a known Wicked Woods event snapshot endpoint rather than a general community search endpoint.
- Hydrate from source-managed OME records or source-derived indexed data.
- Return app-ready data for event detail, stages, performances, poster/site-map references, and schedule rows.
- Keep user-specific state such as local favorites out of the hosted snapshot in the first slice.
- Keep community-calendar ingestion and public social signals out of this first endpoint.
- Preserve cacheability: event source data is read-heavy, and the endpoint should be compatible with later bundle/object-store publishing.
- Code pointers: AppView baseline workspace, `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventAppEventViewer`.
```

## Open Questions

```gpt-5
- Should the first snapshot be a JSON API response, a generated bundle manifest, or both?
- What is the minimum event snapshot needed for QR/App Clip/native event loading?
- Should the AppView read directly from indexed ATProto records, source-derived SQLite projections, or generated bundle artifacts in the first version?
- Which fields must be stable enough to cache aggressively, and which require faster invalidation?
```

## Next Step

```gpt-5
Write the first event snapshot request/response shape for Wicked Woods and decide whether it is served dynamically from SQLite or published as a cacheable bundle.
```
