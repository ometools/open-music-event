---
id: OME-054
type: roadmap-card
area: release
kind: identity
tags:
  - web
  - qr
  - docs
  - identity
launch: wicked-woods
priority: medium
created: "2026-06-10"
---

# Public Surface and QR Lockups

## Summary

```gpt-5
Define how OME appears outside the app: beside QR codes, on event pages, in embeds, in docs, in store screenshots, on posters, and in "powered by Open Music Event" placements.
```

## Why

```gpt-5
OME needs to stand on its own as a symbol, but it also needs to sit comfortably beside practical event infrastructure. QR codes, web embeds, posters, and physical signage should look intentional without making OME compete with the event's own identity.

Public surfaces should prove the open-data promise. Event data should be managed once through the app/source-backed workflow, then rendered in the native app, public web, QR/App Clip entry, schedule embeds, and third-party experiences without forcing the first-party app to become infinitely customizable.
```

## Rough Shape

```gpt-5
- Define mark-only, wordmark, horizontal, stacked, and small-size lockups after final art delivery.
- Create placement rules for QR-adjacent use, event pages, source repository docs, App Store screenshots, and printed or physical signage.
- Define "powered by" and embed attribution rules that can sit beside event branding without taking over the page.
- Treat public event pages and simple web embeds as first-class display surfaces for the same event graph:
  - event landing page
  - schedule embed
  - stage list embed
  - map/site-map preview
  - communication channel page
- Coordinate QR visual rules with [[OME-057-on-site-qr-onboarding-system|On-Site QR Onboarding System]] so printed codes, destination labels, fallback URLs, and event signage work as one field-ready package.
- Keep public copy native app-first, with ATProto and source infrastructure as supporting context.
- Keep the first-party app focused. If someone wants a heavily customized external presentation, public ATProto/AppView data should make that possible outside the app.
- Include contrast, minimum size, margin, and dark/light background guidance.
- Coordinate with store metadata and screenshot work.
- Code pointers: future documentation/release asset exports, `Darwin/fastlane/metadata`, `Android/fastlane/metadata`.
```

## Open Questions

```gpt-5
- Which public surfaces are needed before Wicked Woods launch?
- Should "Open Music Event" remain the default public label, or should event-specific variants be supported immediately?
- What minimum lockup set should be requested from the designer versus produced locally from delivered source assets?
- Which public display surface should prove write-once/display-everywhere first: event page, schedule embed, QR fallback, or App Clip card?
```

## Next Step

```gpt-5
List the first launch-facing public placements and decide which lockups and public display surfaces must exist before screenshots and QR flows are finalized.
```
