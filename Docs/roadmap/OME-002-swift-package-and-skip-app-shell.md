---
id: OME-002
type: roadmap-card
area: app
kind: foundation
priority: high
created: "2026-06-09"
---

# Swift Package and Skip App Shell

## Summary

Built the shared Swift package around a native iOS app and Skip-translated Android app.

## Why

OpenMusicEvent should be a real native app first, with shared Swift code carrying the cross-platform implementation.

## Rough Shape

- Keep platform launch and deployment files in their platform directories.
- Use shared Swift modules for the app shell and feature surfaces.
- Code pointers: `Sources/OpenMusicEventApp`, `Darwin`, `Android`.

## Open Questions

- None for this roadmap pass.

## Next Step

- Keep platform-specific app setup small and push shared behavior into Swift modules.
