---
id: OME-031
type: roadmap-card
area: android
kind: infrastructure
tags:
  - android
launch: wicked-woods
priority: high
created: "2026-06-09"
---

# Skip Observation Support

## Summary

Add or unblock Skip-compatible Observation support for the Android app.

## Why

Several Android-facing app surfaces depend on Swift Observation behavior, either directly through `@Observable` or indirectly through TCA/SwiftUI binding patterns. Until this is supported cleanly in Skip, Android work will keep running into framework-level limits instead of feature-level issues.

## Rough Shape

- Identify the exact Skip/Android compile and runtime failures around `Observation`, `@Observable`, `@Bindable`, and store invalidation.
- Decide whether the durable fix belongs upstream in Skip/SkipFuse, in a local compatibility shim, or in targeted app refactors that avoid unsupported observation patterns.
- Keep the first pass narrow: prove the app shell and one event-viewer surface can build and invalidate correctly on Android.
- Code pointers: `Sources/OpenMusicEventApp/ViewModel.swift`, `Sources/OpenMusicEventApp`, `Sources/OpenMusicEventAppEventViewer`, `Sources/OpenMusicEventApp/Skip/skip.yml`, `Sources/OpenMusicEventAppEventViewer/Skip/skip.yml`, `Package.swift`.

## Open Questions

- Which Observation features are missing in Skip versus only missing in this app's current module setup?
- Should the first fix be proposed upstream before adding local workarounds?
- Which Android blocker should become the acceptance test for this support?

## Next Step

- Reproduce the smallest Android failure that needs Observation support, then choose upstream fix, local shim, or targeted app refactor based on that concrete error.
