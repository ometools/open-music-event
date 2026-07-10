---
id: OME-043
type: roadmap-card
area: operations
kind: release
tags:
  - ios
  - android
launch: wicked-woods
priority: medium
created: "2026-06-09"
---

# White-Label App Operations

## Summary

```gpt-5
Track the operational setup needed for organizer-owned white-label event apps, using `OpenMusicEventWhiteLabelApp` as the full app entry point name instead of a generic `WhiteLabel` target name.
```

## Why

```gpt-5
Festival apps need accounts, source repository ownership, app-store ownership, tester access, and handoff practices that are not purely code problems.

The naming also needs to stay clear as the project adds App Clips. `OpenMusicEventWhiteLabel` can remain the reusable library/module, while `OpenMusicEventWhiteLabelApp` and `OpenMusicEventWhiteLabelAppClip` describe the concrete app entry points that have bundle IDs, signing, App Store Connect records, Associated Domains, and CI packaging gates.
```

## Rough Shape

```gpt-5
- Document required accounts for source hosting, Apple App Store, and Google Play.
- Keep organizer-owned accounts separate from developer-owned temporary setup.
- Connect white-label app setup to release, source ownership, and tester workflows.
- Reserve `OpenMusicEventWhiteLabel` for shared reusable white-label domain and UI infrastructure.
- Use `OpenMusicEventWhiteLabelApp` for the full white-label app entry point/scheme.
- Use `OpenMusicEventWhiteLabelAppClip` for the shared white-label App Clip entry point/scheme.
- Let branded organizer configuration, such as Wicked Woods, supply identity, source, assets, domains, and display copy without renaming the shared OME target family.
- Keep white-label customization focused and precise. Organizer configuration should supply brand identity, source ownership, domains, release metadata, feature availability, and safe event chrome, not arbitrary screen layouts or page-builder behavior.
- Add app-store operations for App Clip experiences:
  - bundle ID and entitlement ownership
  - Associated Domains and white-label domains
  - App Store Connect App Clip cards/experiences
  - QR/NFC route ownership and fallback URLs
- Add CI operations for white-label App Clip size validation and banned dependency checks alongside the generic App Clip.
- Wiki pointers: `White-Label-Apps.md`, `open-music-event-notes-hub.md`.
```

## Open Questions

```gpt-5
- Which operational tasks should become reusable checklists?
- Who owns each account and credential for the first white-label app?
- Is `OpenMusicEventWhiteLabelAppClip` a single configurable App Clip target, or does each organizer get a thin concrete wrapper target that depends on shared white-label App Clip code?
- What bundle ID/domain pattern keeps organizer ownership clear while preserving shared OME infrastructure?
- Which App Clip and full-app CI artifacts should be archived for organizer handoff?
- Which customization requests belong in white-label configuration, and which should be pushed to public AppView/ATProto rendering outside the first-party app?
```

## Next Step

```gpt-5
Convert the existing white-label notes into a concrete organizer handoff checklist that includes `OpenMusicEventWhiteLabelApp`, `OpenMusicEventWhiteLabelAppClip`, bundle/domain ownership, App Clip experience setup, and CI size/dependency artifacts.
```
