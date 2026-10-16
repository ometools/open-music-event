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
  - communication channel
  - individual announcement or content update
  - emergency alert and its current lifecycle state
  - search
  - app install / open-app handoff
- Keep editor, settings, organizer, and contributor-maintenance targets out of public QR defaults unless they are explicitly authenticated and permission-gated.
- Expand `AppRoute` only where the route can be round-tripped, tested, and resolved from durable event identifiers.
- Treat notification taps as another producer of the same canonical HTTPS route contract. Push delivery carries a URL and source identity; the application sends the URL through its existing top-level `openURL` handling instead of maintaining a notification-only router.
- Add exact channel, announcement, and emergency-alert route cases using durable event and content identity rather than display names. An ordinary announcement opens its post detail, a content update opens that same content at its current version, and every emergency lifecycle notification opens the alert it describes.
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
  - if a linked channel, announcement, or emergency alert is not local, hydrate that exact target before selecting its nested destination
  - if the event or content is unavailable, expired, deleted, private, or malformed, show a human-readable event-scoped fallback instead of dropping the tap or opening an unrelated generic screen
- Keep QR links redirectable through a stable domain or link service so printed codes can survive app bundle ID changes, white-label domains, route migrations, and launch-day fixes.
- Add route parser tests for percent encoding, invalid IDs, unsupported targets, full URL round trips, OAuth callback separation, and exact channel/announcement/emergency routes carried by notification payloads.
- Add database-backed navigation stories that start from a notification URL at cold launch and while the app is already mounted, then assert the exact event feature and nested detail state selected after any required hydration.
- Code pointers: `Sources/OpenMusicEventApp/OpenMusicEventRoute.swift`, `Sources/OpenMusicEventApp/OpenMusicEventAppRoot.swift`, `Sources/OpenMusicEventViewers/EventNavigation.swift`, `Tests/OpenMusicEventAppTests/NavigationTests.swift`, `Docs/roadmap/OME-067-appview-push-notification-delivery.md`, `Darwin/Info.plist`, `Darwin/Entitlements.plist`, `Android/app/build.gradle.kts`.
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
Write the first public route table for one real event, including exact channel, announcement, and emergency-alert targets. Choose the canonical QR domain/redirect shape and add parser plus notification-entry navigation tests before any physical QR code is printed or production push payload is shipped.
```
