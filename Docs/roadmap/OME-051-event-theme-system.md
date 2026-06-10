---
id: OME-051
type: roadmap-card
area: app
kind: theming
tags:
  - event
  - identity
  - attendee
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# Event Theme System

## Summary

```gpt-5
Let each event provide its own visual identity through palette, logo, imagery, and accents while OME keeps consistent app chrome around it.
```

## Why

```gpt-5
The logo's rainbow direction avoids committing OME to one color. The product should use that flexibility by allowing festivals, conferences, comedy events, venues, and organizers to bring their own visual language without making the app feel fragmented.
```

## Rough Shape

```gpt-5
- Model event theme inputs: event logo, poster/artwork, dominant colors, accent colors, and safe fallback colors.
- Model organization-level chrome inputs separately from per-event theme inputs when they affect app-wide surfaces.
- Apply theme accents to event headers, event rows, stage chips, badges, schedule markers, and selected high-emphasis controls.
- Keep OME navigation, settings, and system surfaces mostly neutral.
- Add contrast and legibility checks so imported event colors cannot break text or controls.
- Define behavior for events with no art, poor art, or conflicting dark/light assets.
- Code pointers: `Sources/OpenMusicEventAppEventViewer`, `Sources/OpenMusicEventImages`, `Sources/OpenMusicEventDatabase`.
```

## Open Questions

```gpt-5
- Should event theme colors be explicit source data, derived from images, or both?
- Which event/org chrome fields should live in source data versus white-label build configuration?
- Which surfaces should theme in v1: event rows, event headers, schedule stages, or all three?
- How much event identity should appear when multiple events are visible in the same list?
```

## Next Step

```gpt-5
Define the v1 event theme contract and apply it to one event row plus one event header before widening the system.
```
