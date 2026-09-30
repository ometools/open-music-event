# Atmosphere restructure integration

The source is `atmosphere-package-reorg` at `93113031a702`.
The auth integration is `atmosphere-reorg-auth-integration`, under
`/Users/woody/Developer/swift-packages/swift-composable-atmosphere-reorg-auth`.
It ports the auth changes through `251dc6e502f5` into the split packages.

This OME workspace combines the landed auth slice `7ba256c87c3d` with the last
clean migration snapshot `124c99f76e6d`. The later conflicted migration workspace
is preserved. The split comprises ATProto, OAuth, SQLite, server, Bluesky, and
Composable Atmosphere. Sharing and Android integration remain optional traits.

## Validation on September 30

Commands run through the compiler lane with Xcode 27 beta 5.

| Command | Result |
| --- | --- |
| OAuth: `swift-test --build-system native --traits Sharing` | 122 tests in 20 suites passed |
| OAuth: `swift-test --build-system native --skip-update` | 121 tests in 20 suites passed |
| Atmosphere: `swift-test --build-system native --traits BlueskyProfiles` | 79 tests in 9 suites passed |
| OME: `swift-test --build-system native --skip-update --skip XCSkipTests` | 982 tests in 95 suites passed on the final manifest |
| iOS: `xcodebuild -workspace Project.xcworkspace -scheme OpenMusicEventAppTests -destination platform=iOS\ Simulator,id=894BD251-02F3-49EB-B25D-58010DEF72F8 -skipPackagePluginValidation -skipMacroValidation -parallel-testing-enabled NO -only-testing:OpenMusicEventAppTests test` | 357 tests in 30 suites passed; TEST SUCCEEDED, exit 0 |
| Harness: `python3 -B Scripts/auth-e2e/test_harness.py` | 21 tests passed |

OME evidence: `/private/tmp/ome-reorg-native-final-manifest.log`.
The preceding confirmation is retained at `/private/tmp/ome-reorg-native-hydration.log`.
The restoration fixture now returns a DID document that reciprocally identifies
the requested handle. Sign-in and sign-up tests await the recorded hydration
operation instead of treating the cleared progress flag as hydration completion.
Earlier stalled and failed runs are retained in `/private/tmp/ome-reorg-*.log`.

The first iOS test attempt stopped at package linking: HeroImageList's Android
Skip trait exposed SkipSwiftUI twice. OME now enables that trait only for the
Android build graph. The iOS rerun passed. Evidence:
`/private/tmp/ome-reorg-ios-hero-trait.log`. After the test process exited,
Xcode waited several minutes for simulator diagnostics. Stack samples identified
the diagnostics-only simctl child; terminating that child let xcodebuild finalize
with TEST SUCCEEDED and exit 0. The test process and compiler owner were not
terminated. Samples: `/private/tmp/ome-reorg-ios-xcodebuild-sample.txt` and
`/private/tmp/ome-reorg-ios-simctl-sample.txt`.

Swift 6.4.0 and its matching Android SDK are installed, with the SDK configured
against NDK 30.0.16248370. The system default compiler remains unchanged.
An isolated TCA workspace at
`/Users/woody/Developer/ometools/worktrees/TCA26-atmosphere-deployment`
is based on the same `a20aed5e` revision as native validation and adds the
existing SkipFuseUI manifest dependency. Its local landing destination is unset.
A direct cross-compile did not complete: Skip's generated BundleAccess and
UserDefaultsAccess bridge types were missing. Use the complete Skip prebuild
harness before treating that result as a library compatibility failure.

## Remaining gates

1. Give companion manifests one configurable package-family location.
   Their old absolute paths produce warnings; the resolved graph does select
   the integrated OAuth package.
2. Validate Android on Swift 6.4. Previous Android proof used 6.3.3 and
   an explicit networking overlay; that overlay must not be reused on 6.4.
3. Update the AppView container toolchain and package build context. Its
   existing Swift 6.3.3 image does not validate the new graph.
4. Repeat private auth, recovery, UI, and image gates before landing.
5. Complete owning-package publication before replacing development paths.
   The restructure's `Documentation/Publishing.md` retains the release gates.

Intended destinations: OME `workspace:default` and Atmosphere
`workspace:swift-composable-atmosphere-default`. Both remain unchanged.
No push, deployment, or cleanup has occurred. Lifecycle: isolated.
