---
id: OME-024
type: roadmap-card
area: packaging
kind: android
tags:
  - android
launch: wicked-woods
priority: medium
created: "2026-06-09"
---

# Android / Skip Packaging

## Summary

Keep Android app configuration, Gradle files, launcher assets, and Fastlane metadata under the Android project.

## Why

Android should ship from the same Swift codebase through Skip while keeping generated/platform setup contained.

## Rough Shape

- Use Skip build phases and per-module Skip configuration where shared SwiftUI needs Android translation.
- Keep Android release assets and metadata under the Android tree.
- Code pointers: `Android`, `Android/fastlane`, `Sources/OpenMusicEventApp/Skip/skip.yml`.

## Open Questions

- Which Android-specific polish needs to be tracked outside the shared SwiftUI feature work?
- How much Android packaging work is blocked by [[OME-031-skip-observation-support|Skip Observation Support]]?

## Next Step

- Keep Android packaging checks close to Skip parity checks, and treat [[OME-031-skip-observation-support|Skip Observation Support]] as the next infrastructure blocker to clear.
