---
id: OME-027
type: roadmap-card
area: atproto
kind: publishing
priority: high
created: "2026-06-09"
---

# Real ATProto Record Publishing

## Summary

Publish real OpenMusicEvent records to ATProto when the app-side editing and proposal flow is ready.

## Why

ATProto should become the durable network layer for event records once the native app and source-backed workflow have proven the right boundary.

## Rough Shape

- Keep the first implementation narrow.
- Avoid changing source repository semantics until the publishing boundary is clear.
- Code pointers: `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventSourceEditing`.

## Open Questions

- Which record type should be published first?
- What review or authority checks must happen before publishing?

## Next Step

- Define the smallest record publishing slice after source proposals are useful end to end.
