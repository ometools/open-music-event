---
id: OME-023
type: roadmap-card
area: packaging
kind: ios
tags:
  - ios
launch: wicked-woods
priority: medium
created: "2026-06-09"
---

# iOS App Packaging

## Summary

Keep iOS app configuration, assets, entitlements, and Fastlane metadata under the Darwin project.

## Why

The iOS app should ship from the same Swift package modules while keeping Apple-specific release setup isolated.

## Rough Shape

- Build the native app from the shared Swift package modules.
- Keep App Store metadata and signing configuration in the Darwin tree.
- Code pointers: `Darwin`, `Darwin/fastlane`, `Darwin/Assets.xcassets`.

## Open Questions

- Which release metadata should be shared with Android versus platform-specific?

## Next Step

- Keep release metadata updated as attendee-facing positioning changes.
