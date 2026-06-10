---
id: OME-035
type: roadmap-card
area: source
kind: publishing
priority: high
created: "2026-06-09"
---

# Binary Image Patch Publishing

## Summary

Define how source-backed image changes publish when patches contain binary assets instead of only UTF-8 text.

## Why

The current source patch path is shaped around text patches. Event posters, contributor images, and imported local image blobs need a publishing story that does not corrupt binary data or hide image provenance.

## Rough Shape

- Separate text source patches from binary image asset publication where needed.
- Preserve source image references, local blob context, and attachment relationships.
- Decide whether binary assets travel through Tangled blobs, source repository commits, ATProto blobs, or a staged combination.
- Code pointers: `Sources/SourceEditing/SourcePatchGitPatchCodec.swift`, `Sources/OpenMusicEventSourceEditing`, `Sources/OpenMusicEventDatabase/LocalImageStorage.swift`.

## Open Questions

- Which binary image workflow is needed first: posters, contributor images, or event icons?
- Should image publication be part of the same proposal as text source edits?

## Next Step

- Reproduce a source-backed image edit end to end and identify the first binary handoff boundary.
