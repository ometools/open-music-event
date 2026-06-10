---
id: OME-015
type: roadmap-card
area: tangled
kind: integration
priority: high
created: "2026-06-09"
---

# Tangled Source Download

## Summary

Resolve Tangled repository descriptions and clone source repositories for app import.

## Why

OpenMusicEvent source distribution should work through organizer-owned repositories, with Tangled as one supported source host.

## Rough Shape

- Resolve repository descriptions and clone source repositories for import.
- Expose source download through the app and CLI.
- Code pointers: `Sources/OpenMusicEventSourceClone`, `Sources/OpenMusicEventApp/TangledSourceDownload.swift`, `Tests/OpenMusicEventAppTests/TangledSourceDownloadFeatureTests.swift`.

## Open Questions

- Which source hosts beyond Tangled should the UI name explicitly?

## Next Step

- Keep Tangled-specific code isolated behind source clone/download boundaries.
