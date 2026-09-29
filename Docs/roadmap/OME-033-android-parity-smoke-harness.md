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

- `Scripts/android-smoke-build.sh` owns Skip checkout selection, the SkipRunner build, package routes, cache fingerprints, and direct Android command execution. It does not own compiler scheduling; the invoking local shell or CI runner owns job concurrency.
- Its app build action enters Android packaging only through `SkipRunner gradle -p <app>/Android :app:assembleDebug` (or the corresponding release/bundle task). The generated SkipBridge task owns the native Swift package graph and compiler arguments.
- Its `--tests` action runs `OpenMusicEventAppTests` through `skip android test --apk --testing-library testing`, which provides the JNI and Android application context that the bare device executable does not. The test APK reuses the canonical debug app APK's DEX payload so bridged Kotlin and Java types are available alongside the native Swift test libraries.
- The Fastlane `android_tests` lane builds the generated app first, then passes that exact APK into the instrumentation packaging step. A direct `--tests` invocation therefore requires a successful canonical app build in the same app root (or an explicit `OME_ANDROID_TEST_APP_APK`).
- `SKIPLOCAL` is required for this local workflow. It identifies the canonical local `skipstone` package root used for dependency routing and SkipRunner source fingerprints. It defaults to `~/Developer/swift-packages/3rd-party/skip/skipstone`; set it explicitly when that checkout lives elsewhere.
- `SKIP_COMMAND_OVERRIDE` is a separate executable seam. Use it only to validate an isolated SkipRunner change while leaving `SKIPLOCAL` pointed at the canonical package root. Once the runner fix lands upstream, omit the override and let the harness build the runner from `SKIPLOCAL`.
- Android tests run serially by default because several database-backed stories are not process-global parallel safe. `OME_ANDROID_TEST_PARALLELISM` can raise the Swift Testing worker width after a test has proven isolation, and `OME_ANDROID_TEST_FILTER` selects a focused suite or test while diagnosing a failure.
- Do not add a direct `skip android build --target ...` shortcut. That builds the source-package module rather than the generated Fuse app product graph.
- Generated Gradle, Kotlin, and Swift package files are diagnostic evidence, never the durable edit surface.
- Keep the SDK, SkipRunner, Gradle, SwiftPM, module, and generated-package caches workspace-specific and represented in the harness fingerprints.
- Pin Gradle 9.4.1 or newer for the generated Android Gradle Plugin 9.2 build; Gradle 9.0.0 is no longer compatible.

## Local Fastlane Commands

Run these from the repository root. `Scripts/fastlane-local.sh` owns the repository-local Bundler environment; `fastlane/Fastfile` owns lane orchestration and policy.

```sh
export SKIPLOCAL="$HOME/Developer/swift-packages/3rd-party/skip/skipstone"
export GRADLE_BIN=/path/to/gradle-9.4.1/bin/gradle

Scripts/fastlane-local.sh ios_tests device:<booted-ios-simulator-udid>
Scripts/fastlane-local.sh android_tests device:<android-emulator-serial>
Scripts/fastlane-local.sh suite \
  ios_device:<booted-ios-simulator-udid> \
  android_device:<android-emulator-serial>
Scripts/fastlane-local.sh ui_tests \
  ios_device:<booted-ios-simulator-udid> \
  android_device:<android-emulator-serial>
Scripts/fastlane-local.sh all_tests \
  ios_device:<booted-ios-simulator-udid> \
  android_device:<android-emulator-serial>
```

For a temporary isolated SkipRunner build, add:

```sh
export SKIP_COMMAND_OVERRIDE=/absolute/path/to/SkipRunner
```

The `suite` lane runs both platform test suites and reports either platform's failure after attempting both. The standalone `ui_tests` lane checks Maestro and the device appearance profiles, builds both apps, then runs the Testival attendee and refresh stories on each platform with fresh fixture state. It compares their screenshots against the platform baselines.

`all_tests` runs host tests, both platform suites, Android Compose regressions, then the dual-platform visual suite. The Compose fixture is excluded from the host runner because its generated entry point otherwise invokes Android UI tests through the host JVM. The dedicated `compose_tests` lane executes it on the emulator and requires fresh reports containing both regressions with no failures or skips. The UI phase uses the guarded Android `--no-prebuild` path to reuse validated native products while repackaging the automation configuration.

Temporary local dependency overrides must use paths whose final component
matches the canonical package identity. The current isolated validation uses
`OME_FILE_TREE_PATH` (`swift-file-tree`), `OME_CLOCKS_PATH` (`swift-clocks`),
`OME_CUSTOM_DUMP_PATH` (`swift-custom-dump`) and
`OME_DEBUG_SNAPSHOTS_PATH` (`swift-debug-snapshots`), and
`OME_SKIP_AUTHENTICATION_SERVICES_PATH` (`skip-authentication-services`). Use a symlink to an
isolated workspace when needed; a custom basename can introduce a second package
identity in Xcode.

The Android graph exports a SwiftUI compatibility module. Optional
`canImport(SwiftUI)` imports in packages without declared UI dependencies can
therefore pull in JNI modules they cannot resolve. The isolated companion fixes
remove unused FileTree UI code and restrict Clocks, CustomDump and DebugSnapshots
Apple SwiftUI extensions to non-Android builds. Exact Android compiler probes
failed before each guard and passed afterward; the complete final Android suite
passed 354 tests after the DebugSnapshots fix.

## Current Local Proof

Validated in the isolated `open-music-event-local-fastlane` workspace on
2026-09-30, using the local companion dependency overrides:

- Host: 978 tests in 95 suites passed.
- iOS Simulator: 356 tests in 30 suites passed.
- Android instrumentation: 354 tests in 31 suites passed.
- Android Compose: both regression tests passed in fresh JUnit reports, with no skips.
- Testival attendee and refresh stories passed on both platforms.
- All 18 screenshot comparisons passed with zero changed pixels.

The final seven Android baseline updates cover the tab bar after Comms replaced
the direct Contributors tab. Contributors remains accessible under More. After
correcting the task-owned emulator profile, those seven images had no changed
content pixels above the tab bar; Browse and event detail retained their original
baselines. Comparator tolerances were unchanged.

The Android image preflight checks AVD name, OS release, appearance, resolution,
density, cutout insets and status-bar height. A renamed Pixel 7 profile and a
cached 136-pixel status bar both failed the guard. The baseline profile uses
1080×2400 at 420 dpi, no cutout, and a 63-pixel status bar. Removing an emulator
overlay can require a reboot before Android refreshes its cached insets.

Private-auth baseline and recovery evidence is tracked separately in
`Docs/PrivateAuthenticationE2E.md`. These normal-suite results do not establish
browser callback or OAuth refresh behavior.

The Android instrumentation path uses an isolated SkipRunner build supplied
through `SKIP_COMMAND_OVERRIDE`. The source changes and companion fixes remain
isolated; this is local validation, not proof of a landed or remote-only build.

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

