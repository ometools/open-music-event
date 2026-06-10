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
Build the install-light attendee entry point for QR scans: an iOS App Clip and an Android Instant App or equivalent Android fallback that opens the event quickly without making people start with the full app install.
```

## Why

```gpt-5
QR onboarding only works if the first scan feels immediate. People standing at a gate, stage, poster, or merch table should get the event schedule, map, and basic context without needing to understand Open Music Event, ATProto, source repositories, account providers, or app-store installation first.

The full app can remain the durable experience for saved plans, richer media, authenticated contribution, and offline use. The lightweight entry point should be optimized for a first anonymous attendee scan on a busy cellular network.
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
- iOS App Clip work:
  - create an App Clip target under `Darwin`
  - configure Associated Domains and invocation URLs
  - decide whether the App Clip shares Swift package modules with the full app or uses a trimmed read-only shell
  - keep binary size, launch time, images, and dependencies within App Clip constraints
  - configure App Store Connect App Clip experiences for QR / NFC / Safari invocation
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
- Code pointers: `Darwin`, `Darwin/OpenMusicEvent.xcodeproj`, `Android/app/build.gradle.kts`, `Sources/OpenMusicEventApp/OpenMusicEventAppRoot.swift`, `Sources/OpenMusicEventAppEventViewer`, `Sources/OpenMusicEventDatabase`.
```

## Open Questions

```gpt-5
- Is the first App Clip tied to the generic Open Music Event app, a white-label event app, or both?
- Can the current Skip Android packaging support Play Instant, or does Android need a separate lightweight implementation path?
- Which shared SwiftUI modules are safe to include in an App Clip without pulling in too much editing, authentication, image, or source-control weight?
- What is the minimum offline behavior expected after a QR scan succeeds once?
- Should the lightweight experience offer notification opt-in, saved schedule, or favorites, or should those require the full app?
```

## Next Step

```gpt-5
Run a packaging feasibility spike: create the smallest possible iOS App Clip shell that can parse an event route, and separately verify whether Android can support an Instant App from the current Skip/Gradle shape.
```
