---
id: OME-005
type: roadmap-card
area: source
kind: validation
priority: high
created: "2026-06-09"
---

# Source Parsing and Validation

## Summary

Parse source repository files into draft domain records and validate source trees.

## Why

Source data must be trusted enough for import, browsing, and edit proposals without requiring organizers to hand-edit app databases.

## Rough Shape

- Convert YAML and Markdown source files into OpenMusicEvent draft records.
- Validate before local insertion or use as an editable baseline.
- Code pointers: `Sources/OpenMusicEventSource/SourceValidation.swift`, `Tests/OpenMusicEventSourceTests`.

## Open Questions

- Which validation failures should be warnings instead of hard errors?

## Next Step

- Keep validation output useful for both CLI users and app users.
