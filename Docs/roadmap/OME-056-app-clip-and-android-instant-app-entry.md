---
id: OME-056
type: roadmap-card
area: packaging
kind: onboarding
tags:
  - ios
  - android
  - app-clip
  - instant-app
  - qr
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# App Clip and Android Instant App Entry

## Summary

```gpt-5
Build the install-light attendee entry points for QR scans: `OpenMusicEventAppClip`, `OpenMusicEventWhiteLabelAppClip`, and an Android Instant App or equivalent Android fallback that opens the event quickly without making people start with the full app install.
```

## Why

```gpt-5
QR onboarding only works if the first scan feels immediate. People standing at a gate, stage, poster, or merch table should get the event schedule, map, and basic context without needing to understand Open Music Event, ATProto, source repositories, account providers, or app-store installation first.

The full app can remain the durable experience for saved plans, richer media, authenticated contribution, and offline use. The lightweight entry point should be optimized for a first anonymous attendee scan on a busy cellular network.

The App Clip is also a packaging budget, not just a smaller launch screen. CI needs to validate size and linked dependencies early because it will be easy for the full editor, authentication, source-control, image-import, or publishing stack to creep back in through shared viewer code.
```

## Rough Shape

```gpt-5
- Define the minimum attendee experience:
  - event identity and dates
  - current / upcoming performances
  - schedule browsing
  - stage and location context
  - site map
  - contact / safety info
  - open full app / install full app handoff
- Exclude heavy or account-oriented workflows from the first lightweight surface:
  - editing
  - source publishing
  - ATProto sign-in
  - contributor claiming
  - organizer settings
  - broad media import
- Target split:
  - `OpenMusicEventAppClip` is the generic Open Music Event App Clip.
  - `OpenMusicEventWhiteLabelAppClip` is the shared white-label App Clip entry point.
  - `OpenMusicEventWhiteLabelApp` is the full white-label app entry point name; keep `OpenMusicEventWhiteLabel` as the reusable library/module name.
  - App Clip roots depend on a small read-only event entry surface, not on the full `OpenMusicEventApp` root.
- Compile-time event-viewer gating:
  - extract an attendee-safe read-only viewer/core boundary before creating real App Clip targets
  - keep schedule, stages, contributors, communications, contact info, location, site map, posters, search, and about available only when their dependencies stay light
  - keep `edit`, `settings`, source proposal, source refresh, authentication, source-control, broad image import, and publishing flows out of the App Clip target graph
  - split or parameterize surfaces that currently spawn edit destinations from viewer screens, including schedule, location, contact info, posters, and performance detail
  - make `/edit` and `/settings` links reject or degrade to an install/open-full-app handoff in App Clip builds
- iOS App Clip work:
  - create App Clip targets under `Darwin` for `OpenMusicEventAppClip` and `OpenMusicEventWhiteLabelAppClip`
  - configure Associated Domains and invocation URLs
  - decide whether the App Clip shares a trimmed Swift package module with the full app or uses a dedicated read-only shell target
  - keep binary size, launch time, images, and dependencies within App Clip constraints
  - configure App Store Connect App Clip experiences for QR / NFC / Safari invocation
- CI packaging gates:
  - archive/export Release App Clip builds for `OpenMusicEventAppClip` and `OpenMusicEventWhiteLabelAppClip`
  - measure compressed and uncompressed App Clip size, publish the size report as a CI artifact, and fail when either target crosses the configured budget
  - add a banned-dependency check so App Clip targets cannot link/import the editor, auth, source-control, source-publishing, or broad image-import stacks
  - track size deltas per change so regressions are visible before App Store review
- Android Instant App work:
  - investigate whether the current Skip Android app can support Play Instant directly
  - if Skip cannot produce the right module shape, decide between a small native Android/Compose instant module, a web fallback, or deferring Android Instant until packaging catches up
  - configure Android App Links so the same QR URL can open installed app, Instant App, or mobile web fallback
- Shared data strategy:
  - fetch a compact event snapshot from the AppView/link service/source export
  - cache just enough data for the session
  - avoid large image and database migrations on first launch
  - support poor-network behavior with a clear retry and fallback path
- Handoff strategy:
  - preserve the route when the attendee opens or installs the full app
  - avoid asking the user to find the event again after install
  - make "continue in app" work from App Clip, Instant App, and web fallback
- Testing matrix:
  - no app installed
  - full app installed
  - App Clip previously used
  - Android Instant available
  - Android Instant unavailable
  - low bandwidth / captive Wi-Fi
  - expired event
  - wrong event QR
  - event app vs generic OME app
- Code pointers: `Darwin`, `Darwin/OpenMusicEvent.xcodeproj`, `Android/app/build.gradle.kts`, `Sources/OpenMusicEventApp/OpenMusicEventAppRoot.swift`, `Sources/OpenMusicEventApp/OpenMusicEventRoute.swift`, `Sources/OpenMusicEventAppEventViewer/EventViewer.swift`, `Sources/OpenMusicEventAppEventViewer/EventNavigation.swift`, `Sources/OpenMusicEventDatabase`, and the future read-only event viewer/App Clip entry modules.
```

## Acceptance Criteria

```gpt-5
- `OpenMusicEventAppClip` and `OpenMusicEventWhiteLabelAppClip` are explicit iOS App Clip targets/schemes.
- The App Clip roots can open an attendee-safe event route without compiling the full app root, authentication coordinator, editing flows, source publishing, source-control checkout/import, or broad image import.
- App Clip builds reject or hand off unsupported `/edit` and `/settings` routes instead of silently presenting missing screens.
- CI archives both App Clip targets in Release, reports compressed and uncompressed size, and fails when the configured size budget is exceeded.
- CI fails if banned full-app dependencies appear in the App Clip target graph.
- The white-label App Clip can use a branded configuration without forking the attendee-safe viewer core.
```

## Open Questions

```gpt-5
- Do `OpenMusicEventAppClip` and `OpenMusicEventWhiteLabelAppClip` ship together, or does one prove the target graph first?
- Is `OpenMusicEventWhiteLabelAppClip` one reusable configurable target, or does each organizer eventually get a generated concrete App Clip wrapper?
- Can the current Skip Android packaging support Play Instant, or does Android need a separate lightweight implementation path?
- Which shared SwiftUI modules are safe to include in an App Clip after the read-only viewer/core split?
- What initial CI size budget should fail the App Clip build, and should it leave margin below the platform limit?
- What is the minimum offline behavior expected after a QR scan succeeds once?
- Should the lightweight experience offer notification opt-in, saved schedule, or favorites, or should those require the full app?
```

## Next Step

```gpt-5
Run a packaging feasibility spike: sketch the read-only event viewer/App Clip target graph, add a first CI size/dependency report for the empty App Clip shells, then create the smallest possible iOS App Clip shell that can parse an event route. Separately verify whether Android can support an Instant App from the current Skip/Gradle shape.
```
