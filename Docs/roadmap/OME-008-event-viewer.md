---
id: OME-008
type: roadmap-card
area: app
kind: feature
priority: high
created: "2026-06-09"
---

# Event Viewer

## Summary

Open an event into dedicated views for the event's major surfaces.

## Why

Attendees and organizers need one coherent place to inspect schedules, contributors, stages, posters, location, communications, notifications, and settings.

## Rough Shape

- Keep viewer state local to the event feature.
- Use explicit feature dependencies for database-backed views and editing flows.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/EventViewer.swift`, `Sources/OpenMusicEventAppEventViewer/EventViewerState.swift`.

## Open Questions

- Which surfaces should be attendee-first versus organizer/editor-first?

## Next Step

- Continue tightening event viewer navigation around the most common attendee workflows.
