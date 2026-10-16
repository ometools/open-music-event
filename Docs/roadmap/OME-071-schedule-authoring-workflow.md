---
id: OME-071
type: roadmap-card
area: editing
kind: feature
tags:
  - schedule
  - organizer
  - source
priority: high
created: "2026-06-17"
---

# Schedule Authoring Workflow

## Summary

```gpt-5
Make schedule entry fast enough for real organizer data entry: create sets first, infer lightweight artist/profile presence from those sets, keep invalid time input impossible, and make both form-based and direct schedule editing feel natural.
```

## Why

```gpt-5
When entering real schedules like Shambhala, many musicians and DJs have one set at one time. The app should not force a complete source-backed contributor profile before the set can exist. Entering the performance should be the primary workflow, and the profile/listing should appear from that performance data until it is enriched or matched later.
```

## Rough Shape

```gpt-5
- New Performance should launch with schedule-aware defaults:
  - selected schedule/day
  - selected/current stage
  - start time from the end of the latest performance on that stage/day
  - end time from last-used duration or a sensible default
  - previous form values only where they do not fight OME schedule semantics
- `ComposableForms` can own generic previous-value seeding, while OME owns selected stage/day and latest-performance defaults.
- Start/end controls should be constraint-driven:
  - picking a start clamps or advances the end
  - picking an end clamps or backs up the start
  - invalid date/time pairs should not be selectable
- Cross-midnight sets are first-class:
  - manual forms must support ending on the next event day
  - drag/drop must use the same underlying start/end datetime model
- Performance menus must expose edit/delete from the schedule surface itself.
- Direct manipulation is the target interaction model:
  - drag/drop performance placement
  - start/end time drag handles
  - hold/long-press to enter move/edit behavior
- Schedule takeovers should group multiple same-stage sets under a visible wrapper label while preserving individual editable performances.
- Source-backed publishing should make entered schedule data reviewable as schedule YAML changes.
```

## Acceptance Criteria

```gpt-5
- A performance can be created by entering artist/title, stage, and time without first creating a source-backed contributor profile.
- A lightweight/inferred artist/profile row appears from set data and can later be enriched or matched.
- New Performance launched from the schedule defaults to the selected stage/day and the end of the last set on that stage when possible.
- The date/time form prevents invalid ranges instead of surfacing post-hoc validation errors.
- Cross-midnight performances can be entered and displayed clearly.
- Performance edit/delete actions are reachable directly from schedule cards.
- A takeover group can wrap multiple performances on one stage with a label above the grouped sets.
- Entered performances appear in source edit summaries and can become reviewable source changes.
```

## Open Questions

```gpt-5
- Should inferred artist/profile records be persisted as contributors immediately, or projected from performance contributor rows until enriched?
- What should happen when the last performance for an inferred artist is deleted?
- Should takeovers be explicit source data, derived display metadata, or both?
- What is the first direct-manipulation slice: drag to move, resize handles, or long-press selection mode?
```

## Next Step

```gpt-5
Start with the form-based authoring slice: schedule-aware New Performance defaults plus constraint-driven start/end selection, then verify source-edit tracking for added performances before expanding into drag/drop.
```
