---
id: OME-001
type: roadmap-card
area: project
kind: foundation
priority: high
created: "2026-06-09"
---

# Project Bootstrap

## Summary

Created the new `open-music-event` package as the active ATProtoOME project.

## Why

The project needed a clean Swift-first base for the native app, source-backed event model, ATProto identity, and Skip Android target.

## Rough Shape

- Split the app, domain, source, database, editing, authentication, and shared UI code into separate modules.
- Keep the new project as the place where current OpenMusicEvent app work lands.
- Code pointers: `Package.swift`, `Project.xcworkspace`.

## Open Questions

- None for this roadmap pass.

## Next Step

- Keep this card updated when the package/module boundary changes.
