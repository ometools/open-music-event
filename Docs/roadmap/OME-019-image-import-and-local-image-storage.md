---
id: OME-019
type: roadmap-card
area: media
kind: feature
priority: medium
created: "2026-06-09"
---

# Image Import and Local Image Storage

## Summary

Import source image references and store local image data for browsing and editing.

## Why

Images make event browsing useful, but the app needs local storage and source provenance to keep them reliable.

## Rough Shape

- Store local image data in the database layer.
- Share image-loading UI across event viewer surfaces.
- Code pointers: `Sources/OpenMusicEventDatabase/LocalImageStorage.swift`, `Sources/OpenMusicEventImages`, `Sources/OpenMusicEventAppEventViewer/ImportImages.swift`.

## Open Questions

- Which image assets should be bundled, cached, downloaded, or treated as source artifacts?

## Next Step

- Keep image import tied to source-backed editing and local storage tests.
