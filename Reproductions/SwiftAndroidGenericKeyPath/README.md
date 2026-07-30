# Swift Android Generic Key-Path Reproduction

This package removes Open Music Event, OAuth, JNI, Compose, and UI code from the failure. It compares direct Observation registrar mutations with the minimal `Sharing` plus Android `SkipSharing` construction used by Open Music Event.

The crashing test is opt-in on Android so the controls can complete before deliberately triggering the runtime trap.

## Host control

Run `swift test` from this directory. All three tests should pass on macOS.

The Android commands below use the exact Swift 6.3.3 fixture that reproduced the failure. They assume the local SkipRunner symlink and isolated SwiftPM home created by the OME Android harness:

```sh
export REPRO_ROOT="$PWD"
export TOOLCHAIN="$HOME/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain"
export SDK="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android"
export LANE="$HOME/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh"
export CFFIXED_USER_HOME=/private/tmp/ome-android-smoke/swiftpm-home
export PATH=/private/tmp/ome-skip-bin:/opt/homebrew/bin:/usr/bin:/bin
```

## Android control

```sh
"$LANE" \
  --cache-root /private/tmp/woody-swift-compiler-caches-633 \
  --repo "$REPRO_ROOT" \
  skip android test \
  --android-serial emulator-5554 \
  --toolchain "$TOOLCHAIN" \
  --sdk "$SDK" \
  --testing-library testing \
  --no-bridge
```

The test process should complete. Both direct Observation controls mutate and read their state successfully.

## Android reproduction

```sh
"$LANE" \
  --cache-root /private/tmp/woody-swift-compiler-caches-633 \
  --repo "$REPRO_ROOT" \
  skip android test \
  --android-serial emulator-5554 \
  --toolchain "$TOOLCHAIN" \
  --sdk "$SDK" \
  --testing-library testing \
  --env RUN_GENERIC_KEYPATH_REPRO=sharing \
  --no-bridge
```

Use `RUN_GENERIC_KEYPATH_REPRO=manual` instead to exercise the dependency-free `GenericReference<Int>` control. It passes. On the affected Swift Android runtime, the Sharing case terminates while constructing `_PersistentReference<AppStorageKey<Int?>>` and its `\._isLoading` key path:

```text
Swift/KeyPath.swift:3377: Fatal error: could not demangle keypath type
_resolveKeyPathGenericArgReference
_swift_getKeyPath
Sharing._PersistentReference.isLoading.setter
```
