---
id: OME-068
type: roadmap-card
area: attendee
kind: feature
tags:
  - wicked-woods
  - local-first
  - ios
  - android
launch: wicked-woods
priority: high
created: "2026-06-17"
---

# Personal Schedules Within the Schedule Feature

## Summary

```gpt-5
Add local, attendee-created `UserSchedule` overlays to the published Schedule feature. Keep Event Schedule as the default complete timeline and let attendees create, rename, select, and delete personal schedules without adding a new event feature or tab.
```

## Why

```gpt-5
Wicked Woods attendees need to plan performances while retaining the event's complete published schedule. Personal schedules are private app-database state, independent of organizer publishing and public social records.
```

## Rough Shape

```gpt-5
- Add local `UserSchedule` and `UserSchedule.Performance` models. A schedule captures the currently selected account DID when it is created, or `nil` when no account is selected; login remains optional.
- Create `My Schedule` exactly once on the first Schedule mount while leaving Event Schedule selected. It remains an ordinary renamable and deletable schedule.
- Add a Schedule toolbar menu for Event Schedule, personal schedules, and a Schedules list. Do not add an `EventFeature`, tab, serialized feature value, or public route.
- Preserve the complete timeline in every layout. When a personal schedule is selected, dim non-members while keeping them tappable and show membership with both a visible indicator and accessibility text.
- Support schedule CRUD and membership actions from schedule cards and performance detail, including atomic "Add to a new schedule."
- Preserve unavailable membership references through source refresh and allow explicit local removal.
- Keep these tables out of source snapshots, patches, organizer publishing, AppView snapshots, and ATProto records.
- Sharing, importing, cloud sync, collaboration, reminders, artist following, and public publishing are outside this slice.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/Schedule`, `Sources/OpenMusicEventAppEventViewer/EventViewerState.swift`, `Sources/OpenMusicEventApp/Schema.swift`.
```

## Persistence Rules

```gpt-5
- Schedule titles are trimmed, 1–80 characters, and case-insensitively unique per event.
- A performance may belong to multiple personal schedules but only once per schedule.
- `EventViewerState.selectedUserScheduleID == nil` means Event Schedule; selection persists and falls back to Event Schedule when invalid.
- `didInitializeUserSchedules` distinguishes first use from intentionally deleting every personal schedule.
- A schedule keeps the DID captured at creation when it is renamed or its memberships change.
- Memberships cascade only with their `UserSchedule`. They do not foreign-key to source-owned event, performance, or contributor rows.
```

## Next Step

```gpt-5
Validate the forward migration, persistence invariants, Schedule story flows, full-timeline overlay behavior, and the `OpenMusicEventApp` target. Android runtime remains a temporary gate unless requested.
```
