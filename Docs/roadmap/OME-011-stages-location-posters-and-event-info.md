---
id: OME-011
type: roadmap-card
area: app
kind: feature
priority: medium
created: "2026-06-09"
---

# Stages, Location, Posters, and Event Info

## Summary

Browse event metadata, stage details, posters, location, contact, and communication surfaces.

## Why

These surfaces make the event useful beyond the schedule and give organizers a richer source-backed event profile.

## Rough Shape

- Keep event info, stages, posters, location, contact, and communications in the event viewer.
- Split the higher-quality site map / wayfinding work into [[OME-062-site-map-and-wayfinding|Site Map and Wayfinding]].
- Keep these views source-backed so edits can flow through the proposal pipeline.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/EventInfoViewer.swift`, `Sources/OpenMusicEventAppEventViewer/StagesViewer.swift`, `Sources/OpenMusicEventAppEventViewer/PostersViewer.swift`.

## Open Questions

- Which of these surfaces should become primary tabs versus secondary detail views?

## Next Step

- Use attendee-facing polish work to decide the final navigation weight.
