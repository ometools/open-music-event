---
id: OME-033
type: roadmap-card
area: android
kind: testing
tags:
  - android
launch: wicked-woods
priority: high
created: "2026-06-09"
---

# Android Parity Smoke Harness

## Summary

Create a repeatable Android smoke path that proves the shared Swift app can launch and exercise one meaningful event workflow.

## Why

Android support needs a practical acceptance loop. A small parity harness keeps the team from treating a successful Swift build as proof that the translated app works.

## Rough Shape

- Launch the Android app from the shared package and verify the app shell renders.
- Open an imported event, render the schedule, and exercise one source-backed or settings path.
- Prefer a narrow smoke flow over broad UI automation until the app flow settles.
- Code pointers: `Android`, `Sources/OpenMusicEventApp`, `Sources/OpenMusicEventAppEventViewer`, `Tests/OpenMusicEventAppTests`.

## Open Questions

- Should the first smoke harness use Skip tooling, Maestro, or a smaller command-line launch check?
- Which fixture event should become the Android baseline?

## Next Step

- Define the first smoke path immediately after the app launches reliably on Android.
