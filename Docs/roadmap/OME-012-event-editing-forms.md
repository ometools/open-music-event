---
id: OME-012
type: roadmap-card
area: editing
kind: feature
priority: high
created: "2026-06-09"
---

# Event Editing Forms

## Summary

Edit event details, calendars, stages, images, and policies from the native app.

## Why

Organizer-facing editing should happen in the app while still producing source-backed changes.

The app should not ask organizers to repair invalid data after they have moved on. Editing forms should preserve invariants while the organizer works: stage pickers should produce valid stage references, date controls should avoid ambiguous ranges, source slugs should be checked before write, destructive relationship changes should be explicit, and publish/proposal preflight should mostly confirm what the app already kept coherent.

## Rough Shape

- Use focused form features so edits can be tested before they become source patches.
- Prefer constrained inputs over freeform fields when the domain has a known set of valid choices.
- Keep validation local and user-correctable for form state, duplicate slugs, missing required fields, broken references, and similar edit-time issues.
- Model source output as a result of app-authored domain changes, not as something organizers are expected to hand-edit.
- Keep edit invalidation explicit when the baseline changes.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/EditEvent.swift`, `Sources/OpenMusicEventAppEventViewer/EditEventInfo.swift`, `Tests/OpenMusicEventAppTests/EditEventSourcePatchInvalidationTests.swift`.

## Open Questions

- Which edit forms are required before the first organizer review workflow feels complete?
- Which current forms still allow invalid or ambiguous intermediate state that could be prevented by better controls?
- Which fields should be pickers, segmented controls, or relationship selectors instead of text entry?

## Next Step

- Fill gaps in source-backed forms one small event surface at a time, starting with the controls that prevent invalid source output rather than just reporting it later.
