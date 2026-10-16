---
id: OME-032
type: roadmap-card
area: android
kind: compatibility
tags:
  - android
launch: wicked-woods
priority: high
created: "2026-06-09"
---

# Android Compatibility Sweep

## Summary

Work through the non-Observation Skip and Android compatibility blockers that prevent ordinary feature work from progressing cleanly.

## Why

Some Android problems are not product decisions; they are compatibility gaps that make every downstream feature harder to validate. Clearing them as a focused sweep keeps generated Android output as debug evidence instead of the place where durable fixes live.

## Rough Shape

- Track unsupported SwiftUI and framework APIs such as `ContentUnavailableView`, platform-only pickers, and unavailable storage helpers.
- Audit bridge visibility issues, including helper `View` types that cannot be private when Skip needs to bridge them.
- Keep durable fixes in `Package.swift`, source files, or Skip config rather than generated Gradle files.
- Code pointers: `Sources/OpenMusicEventApp`, `Sources/OpenMusicEventAppEventViewer`, `Sources/*/Skip/skip.yml`, `Package.swift`.

## Open Questions

- Which compatibility fixes belong upstream in Skip versus local OpenMusicEvent shims?
- Which Android errors should become explicit regression checks?

## Next Step

- Build a short ordered list of current Android compile/runtime failures after `OME-031` establishes the Observation baseline.
