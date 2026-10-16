---
id: OME-048
type: roadmap-card
area: calendar-feeds
kind: feature
tags:
  - calendar
  - attendee
  - unsynced
launch:
priority: high
created: "2026-06-10"
---

# Add Events Directly to User Calendar

## Summary

```gpt-5
Let users add an OpenMusicEvent event directly to their personal calendar as a one-time, unsynced calendar item.
```

## Why

```gpt-5
This is the simpler first step before subscribed calendar feeds. It gives attendees an immediate way to save an event without requiring OME-hosted feeds, CalDAV, AppView infrastructure, or ongoing sync semantics.
```

## Rough Shape

```gpt-5
- Start with event-level calendar export rather than full schedule subscription.
- Use the current `OME.Calendar -> CalendarEntry -> Event` model to find the event date block.
- On iOS, prefer the native add-to-calendar flow when available.
- On Android, prefer the platform calendar insert intent or equivalent Skip-compatible handoff.
- Fall back to generating/opening a one-off `.ics` file if direct native insertion is not available.
- Make the UX clear that this is unsynced: future OME schedule/event edits will not update the user's personal calendar item.
```

## Open Questions

```gpt-5
- Should v1 add only the event date block, or also offer individual performance items later?
- Do we need explicit calendar permission handling, or can we rely on platform-provided insertion screens?
- Where should the action live first: event info, schedule, or the event row menu?
```

## Next Step

```gpt-5
Spike the smallest cross-platform path for adding one event date block to the user's calendar, starting with the current event model and no sync/update behavior.
```
