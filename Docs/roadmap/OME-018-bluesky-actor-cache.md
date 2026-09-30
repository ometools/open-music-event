---
id: OME-018
type: roadmap-card
area: identity
kind: infrastructure
priority: medium
created: "2026-06-09"
---

# Bluesky Actor Cache

## Summary

Cache Bluesky actor information needed by event and contributor surfaces.

## Why

Actor display data is useful in the app, but it should not become part of the core event domain records.

## Rough Shape

- Cache actor data behind a dedicated package.
- Keep actor lookup separate from OpenMusicEvent record modeling.
- Code pointers: `Packages/swift-bluesky/Sources/Bluesky` in the local Atmosphere
  family checkout, and `Tests/BlueskyActorCacheTests` in OME.

## Open Questions

- Which actor fields should be cached for offline or low-connectivity event use?

## Next Step

- Use concrete contributor and auth UI needs to decide the next cache fields.
