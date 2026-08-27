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

Maintain one repeatable Android build, test, and smoke path that proves the generated Fuse app can produce an installable artifact, run app-context tests, launch, and exercise one meaningful event workflow.

## Why

Android support needs a practical acceptance loop. A small parity harness keeps the team from treating a successful Swift build as proof that the translated app works.

## Harness Contract

- `Scripts/android-smoke-build.sh` owns the local Skip checkout, SkipRunner build, package routes, cache fingerprints, and serialized Android compiler entry.
- Its app build action enters Android packaging only through `SkipRunner gradle -p <app>/Android :app:assembleDebug` (or the corresponding release/bundle task). The generated SkipBridge task owns the native Swift package graph and compiler arguments.
- Its `--tests` action runs `OpenMusicEventAppTests` through `skip android test --apk --testing-library testing`, which provides the JNI and Android application context that the bare device executable does not.
- Do not add a direct `skip android build --target ...` shortcut. That builds the source-package module rather than the generated Fuse app product graph.
- Generated Gradle, Kotlin, and Swift package files are diagnostic evidence, never the durable edit surface.
- Keep the SDK, SkipRunner, Gradle, SwiftPM, module, and generated-package caches workspace-specific and represented in the harness fingerprints.

## Evidence Levels

- `--dry-run` proves command selection, local package routing, and cache/configuration wiring only.
- A successful app build proves that the generated Android wrapper produced an APK or AAB; it is not a test pass or launch proof.
- A successful `--tests` run proves the selected Swift Testing target passed inside an instrumentation APK; it is not a UI test.
- `--install --launch` proves installation and process launch on the selected emulator; it does not prove the attendee workflow.
- Maestro or equivalent emulator interaction must separately prove the attendee-facing workflow.

## Rough Shape

- Launch the Android app from the shared package and verify the app shell renders.
- Open an imported event, render the schedule, and exercise one source-backed or settings path.
- Prefer a narrow smoke flow over broad UI automation until the app flow settles.
- Code pointers: `Android`, `Sources/OpenMusicEventApp`, `Sources/OpenMusicEventAppEventViewer`, `Tests/OpenMusicEventAppTests`.

## Open Questions

- Which fixture event should become the Android baseline?

## Next Step

- Define the first smoke path immediately after the app launches reliably on Android.
