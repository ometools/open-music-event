---
id: OME-021
type: roadmap-card
area: app
kind: feature
priority: medium
created: "2026-06-09"
---

# Settings and Contributor Policies

## Summary

Edit event settings and contributor policy values from the event viewer.

## Why

Organizer control needs a native editing surface that can still preserve flexible policy values.

## Rough Shape

- Give known policies native controls.
- Preserve unknown or open policy values through source-backed editing.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/EventSettings.swift`, `Sources/OpenMusicEventAppEventViewer/EditEventPolicies.swift`, `Tests/OpenMusicEventAppTests/SettingsFeatureTests.swift`.

## Open Questions

- Which policies should block publishing when required provider data is missing?

## Next Step

- Keep policy editing tests focused on preserving flexible values.
