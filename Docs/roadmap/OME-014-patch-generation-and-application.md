---
id: OME-014
type: roadmap-card
area: editing
kind: infrastructure
priority: high
created: "2026-06-09"
---

# Patch Generation and Application

## Summary

Generate source patches from local event edits and apply serialized patches.

## Why

Source-backed proposals need a portable representation that can be reviewed and applied outside the app.

## Rough Shape

- Generate source patches from local event edits.
- Apply and serialize patches through the lower-level source editing package.
- Code pointers: `Sources/OpenMusicEventSourceEditing/OpenMusicEventSourcePatchGeneration.swift`, `Sources/SourceEditing/SourcePatchApplier.swift`, `Tests/OpenMusicEventAppTests/OpenMusicEventSourcePatchGenerationTests.swift`.

## Open Questions

- Which patch review metadata should travel with the patch versus live in Tangled or ATProto records?

## Next Step

- Keep generated patches readable and covered by source patch tests.
