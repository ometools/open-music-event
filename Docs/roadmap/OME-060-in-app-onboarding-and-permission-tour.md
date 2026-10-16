---
id: OME-060
type: roadmap-card
area: app
kind: onboarding
tags:
  - attendee
  - permissions
  - settings
  - app-clip
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# In-App Onboarding and Permission Tour

## Summary

```gpt-5
Add a minimal in-app onboarding path that keeps first launch lightweight, preserves App Clip and QR entry without prior setup, and offers a fuller opt-in tour from Settings or help surfaces.
```

## Why

```gpt-5
OpenMusicEvent should be understandable when someone opens it from a QR code, App Clip, Android Instant entry, deep link, or fresh install. Onboarding can explain the product and permission choices, but it should not become a required gate before viewing an event, reading a schedule, or finding basic venue context.

Permission prompts also need to be contextual and recoverable. Attendees should be able to understand why notifications, nearby/location, or calendar handoff might help, and they should have a clear path back to system settings after denial without the app pretending it can show the same OS prompt again.
```

## Rough Shape

```gpt-5
- Keep first-run minimal:
  - at most one lightweight welcome / continue screen
  - no required multi-step setup before the app shell
  - allow App Clip, QR, and deep-link entry to bypass first-run entirely
- Make primary event surfaces stand alone:
  - event landing
  - schedule
  - stages / location / site map
  - notifications and contact information
  - basic settings and support
- Put the fuller tour behind explicit user intent:
  - Settings entry
  - About / help entry
  - optional post-install "show me around" affordance
  - relaunchable after the user dismisses it
- Limit the first attendee permission scope to:
  - notifications for event updates
  - location / nearby filtering
  - calendar handoff for saving events
- Define permission retriggering as state-aware recovery:
  - ask only when the OS state is not determined
  - explain contextual value before asking
  - show a denied-state explanation when the user has already denied access
  - deep-link to system settings where the platform allows it
  - never block schedule browsing or event viewing on a permission
- Model iOS and Android permission states separately enough to avoid false parity assumptions.
- Do not add a third-party SwiftUI onboarding library for v1. Prefer native SwiftUI and existing TCA-style feature modeling unless a later spike proves a real need.
- Keep account/provider onboarding in [[OME-040-pds-account-provider-onboarding|OME-040: PDS / Account Provider Onboarding]], organizer/source permissions in [[OME-039-organizer-authority-and-review-permissions|OME-039: Organizer Authority and Review Permissions]], and physical QR operations in [[OME-057-on-site-qr-onboarding-system|OME-057: On-Site QR Onboarding System]].
- Code pointers: `Sources/OpenMusicEventApp/OpenMusicEventAppRoot.swift`, `Sources/OpenMusicEventApp/OpenMusicEventBrowser.swift`, `Sources/OpenMusicEventApp/Settings.swift`, `Sources/OpenMusicEventApp/OpenMusicEventRoute.swift`, `Sources/OpenMusicEventAppEventViewer`.
```

## Open Questions

```gpt-5
- Should the first install show a one-screen welcome, or should the app open directly to the selected event / browser until the user asks for the tour?
- Should the tour be global OME content, event-branded content, or a mixed global shell with event-specific panels when an event is loaded?
- Which permission affordance should prove the first slice: notifications, nearby/location, or calendar handoff?
- Where should denied-permission recovery live: Settings only, contextual surfaces, or both?
- What should App Clip and Android Instant surfaces omit so they remain understandable without persisted onboarding state?
```

## Acceptance Checks

```gpt-5
- Fresh install can reach browse, event, and schedule surfaces without completing onboarding.
- QR, App Clip, Android Instant, and deep-link entry open a comprehensible event screen without first-run state.
- Settings can relaunch the tour after it has been dismissed.
- Denied permissions show explanation and settings handoff rather than another impossible OS prompt.
- Notification, location, and calendar affordances remain optional and contextual.
- Android and iOS permission states are modeled separately enough to avoid false parity assumptions.
```

## Next Step

```gpt-5
Sketch the smallest native SwiftUI/TCA onboarding state model that can represent dismissed first-run state, relaunchable tour state, and per-platform attendee permission states without blocking event browsing.
```
