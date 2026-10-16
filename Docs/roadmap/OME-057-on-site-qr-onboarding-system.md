---
id: OME-057
type: roadmap-card
area: operations
kind: onboarding
tags:
  - qr
  - nfc
  - launch
  - web
  - analytics
  - signage
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# On-Site QR Onboarding System

## Summary

```gpt-5
Plan the physical and operational QR/NFC system for events: what each scan or tap point opens, where it is installed, how it falls back, how it is tested, and how staff know whether onboarding is working.
```

## Why

```gpt-5
Installing QR codes and NFC tap points at an event turns app onboarding into physical infrastructure. A broken link, unclear sign, poor cellular path, dead NFC tag, or app-store dead end can fail in front of attendees and staff. The QR/NFC rollout needs to be treated like launch operations, not just a design asset.

The strongest version is place-specific: a person standing at a stage entrance, installation, gate, or info point should get useful context for that place quickly, with a clear path into the full app when they want the rest of the weekend experience.

This card connects [[OME-054-public-surface-and-qr-lockups|Public Surface and QR Lockups]], [[OME-055-universal-links-and-deep-link-routing|Universal Links and Deep-Link Routing]], and [[OME-056-app-clip-and-android-instant-app-entry|App Clip and Android Instant App Entry]] into a field-ready onboarding plan.
```

## Rough Shape

```gpt-5
- Inventory QR/NFC placements for the first event:
  - gate / box office
  - schedule boards
  - stages
  - site map locations
  - posters
  - merch / info booth
  - camping / lodging areas
  - volunteer or staff-only locations
- Treat physical scan/tap points as reusable info-point objects:
  - each object has a stable code, number, or name
  - event source data associates the object with its installed location and route target
  - the same physical object can be reused at another event by changing source data, not reprinting identity into the object itself
  - route targets can be generic event onboarding, a stage, an installation, a map place, schedule now/next, contact, safety, feedback, or app install/open
  - NFC tags and QR codes can share the same route/target model even when one physical placement only supports one medium
- Define scan/tap target classes instead of one generic code:
  - event onboarding
  - schedule now/next
  - full schedule
  - stage-specific schedule
  - map / site map
  - contact and safety info
  - feedback / support
  - install/open full app
- Prototype place-specific entry flows:
  - map-first with the relevant place selected and zoomed
  - info-first with a compact place sheet and an obvious map affordance
  - full-app handoff that preserves the selected event/place after install or open
- Use stable short links or redirect links behind printed QR codes:
  - platform-aware routing
  - campaign/source identifiers
  - event/version identifiers
  - emergency destination changes
  - disabled/expired event behavior
  - white-label domain support
- Pair every QR code and NFC placement with human-readable fallback text:
  - short URL
  - event/app name
  - one-line destination label
  - no critical safety information that exists only behind a QR code
- Pre-event QA:
  - scan from iPhone and Android
  - scan with and without full app installed
  - scan after deleting app data
  - scan from lock screen where supported
  - scan in low light
  - scan from expected distance
  - test damaged/creased print
  - test weak cellular and captive Wi-Fi
  - test App Clip / Instant / web fallback
- On-site operations:
  - keep a placement map of all installed QR codes
  - track which placements also have NFC tags and how they are mounted/protected
  - assign an owner for installing, inspecting, and replacing signs
  - give staff a short script for "scan this to see the schedule"
  - keep spare printed signs and tape/hardware available
  - monitor scan/open failures during the event
  - maintain an emergency redirect path if a code target breaks
- Measurement:
  - count scans by QR placement and day
  - separate scan, web open, App Clip/Instant open, full app open, and install handoff
  - avoid attendee-identifying analytics unless there is an explicit privacy decision
  - review post-event conversion and failure patterns before printing the next batch
- Dependencies: [[OME-054-public-surface-and-qr-lockups|Public Surface and QR Lockups]], [[OME-055-universal-links-and-deep-link-routing|Universal Links and Deep-Link Routing]], [[OME-056-app-clip-and-android-instant-app-entry|App Clip and Android Instant App Entry]], [[OME-044-testflight-trusted-tester-rollout|TestFlight / Trusted Tester Rollout]], [[OME-045-store-metadata-and-screenshots|Store Metadata and Screenshots]].
```

## Open Questions

```gpt-5
- Which physical placements are required for the first event, and which are nice-to-have?
- Which placements should be QR-only, NFC-only, or both?
- Do reusable physical objects need permanent IDs distinct from route targets and map place IDs?
- Who owns printing, installation, inspection, and replacement during the event?
- What analytics are acceptable for attendee onboarding, and what should be intentionally avoided?
- What is the backup plan if App Clip review, Android Instant packaging, or app-store approval is not ready before signs must be printed?
- Should QR destinations be event-owned infrastructure, OME-owned infrastructure, or white-label infrastructure per organizer?
```

## Next Step

```gpt-5
Create a first-event QR/NFC placement map and route matrix, including reusable info-point IDs, then generate a test batch of QR codes and NFC URLs that point at redirectable non-final targets before anything is permanently printed, encoded, or installed.
```
