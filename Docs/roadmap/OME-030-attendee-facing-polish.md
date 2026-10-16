---
id: OME-030
type: roadmap-card
area: app
kind: polish
launch: wicked-woods
priority: medium
created: "2026-06-09"
---

# Attendee-Facing Polish

## Summary

Polish browsing, event discovery, search, schedule navigation, image loading, and offline behavior for attendee use.

Atendees should not know about editing the event, it should look like the legacy version, with editing only surfacing to maintainers.
## Why

The app needs to feel useful and calm for attendees, not just technically correct for organizers and developers.

## Rough Shape

- Improve event discovery, schedule navigation, and media loading.
- Keep UI improvements grounded in the current event viewer and local database model.
- Code pointers: `Sources/OpenMusicEventAppEventViewer`, `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventImages`.

## Open Questions

- Which attendee workflow should define the first polish pass: finding an event, reading the schedule, or saving plans?

## Next Step

- Pick one real imported event and use it as the polish baseline.
