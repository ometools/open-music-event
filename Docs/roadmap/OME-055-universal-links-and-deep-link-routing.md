---
id: OME-055
type: roadmap-card
area: app
kind: deep-linking
tags:
  - ios
  - android
  - web
  - qr
  - navigation
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# Universal Links and Deep-Link Routing

## Summary

```gpt-5
Define the public URL contract that QR codes, web pages, the full app, App Clip, and Android Instant App can all depend on for opening the right event surface.
```

## Why

```gpt-5
Physical QR codes are expensive to move, reprint, and explain once they are installed at an event. The URLs behind them need to be stable, readable, redirectable, and resilient across installed-app, no-app, App Clip, Android Instant App, mobile web, and store-install paths.

The app already has an internal `AppRoute` parser and top-level `onOpenURL` handling. This card turns that early routing work into a public, documented link contract that can safely support attendee onboarding in the field.
```

## Rough Shape

```gpt-5
- Make HTTPS routes the canonical public links for event onboarding. Keep the custom `app.openmusicevent:/oauth/callback` style scoped to OAuth and internal callback behavior.
- Document a stable route table for attendee-safe targets:
  - event landing
  - schedule
  - "now / next" schedule view
  - stage list
  - individual stage
  - location / map / site map
  - posters
  - contact info
  - contributor profile
  - search
  - app install / open-app handoff
- Keep editor, settings, organizer, and contributor-maintenance targets out of public QR defaults unless they are explicitly authenticated and permission-gated.
- Expand `AppRoute` only where the route can be round-tripped, tested, and resolved from durable event identifiers.
- Add iOS Universal Link support:
  - Associated Domains entitlement in `Darwin/Entitlements.plist`
  - hosted `apple-app-site-association`
  - tested routes for full app and App Clip invocation
- Add Android App Link support:
  - verified intent filters / manifest wiring in the Android app
  - hosted `assetlinks.json`
  - behavior that can hand off to full app, Instant App, or web fallback
- Define a resolver behavior for missing local data:
  - if the event exists locally, open the target immediately
  - if the event is known remotely, import or hydrate the minimum event snapshot before opening
  - if the event is unavailable, expired, private, or malformed, show a human-readable fallback instead of dropping the tap
- Keep QR links redirectable through a stable domain or link service so printed codes can survive app bundle ID changes, white-label domains, route migrations, and launch-day fixes.
- Add route parser tests for percent encoding, invalid IDs, unsupported targets, full URL round trips, and OAuth callback separation.
- Code pointers: `Sources/OpenMusicEventApp/OpenMusicEventRoute.swift`, `Sources/OpenMusicEventApp/OpenMusicEventAppRoot.swift`, `Sources/OpenMusicEventAppEventViewer/EventNavigation.swift`, `Darwin/Info.plist`, `Darwin/Entitlements.plist`, `Android/app/build.gradle.kts`.
```

## Open Questions

```gpt-5
- What is the canonical QR domain for the first launch: `openmusicevent.app`, an event-owned domain, or a white-label domain?
- Should printed QR codes point directly at route URLs, or always at a redirect/link service that can change destinations later?
- Which event target should be the default scan destination: event landing, schedule, now/next, map, or a dedicated onboarding view?
- How should a link identify an event before the event has an AppView record, published source record, or final public slug?
- Do white-label apps share one URL scheme/link contract, or does each event app get its own route namespace?
```

## Next Step

```gpt-5
Write the first public route table for one real event, choose the canonical QR domain/redirect shape, and add parser tests before any physical QR code is printed.
```
