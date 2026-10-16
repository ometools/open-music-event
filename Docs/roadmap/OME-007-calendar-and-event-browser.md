---
id: OME-007
type: roadmap-card
area: app
kind: feature
priority: high
created: "2026-06-09"
---

# Calendar and Event Browser

## Summary

Browse imported calendars and event rows from the app root.

## Why

The app needs a simple entry point before a user reaches the richer event viewer.

## Rough Shape

- Show imported calendars and event rows with event artwork.
- Route into event details, settings, source download, and creation flows.
- Code pointers: `Sources/OpenMusicEventApp/MyEvents.swift`, `Sources/OpenMusicEventApp/OpenMusicEventBrowser.swift`, `Tests/OpenMusicEventAppTests/NavigationTests.swift`.

## Open Questions

- How much discovery belongs here before AppView-backed search exists?

## Next Step

- Keep the browser focused on local calendars and imported events until service-backed discovery is defined.
