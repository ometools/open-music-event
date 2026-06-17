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

# Wicked Woods Local Attendee State

## Summary

```gpt-5
Implement attendee-facing saved/favorited event state locally first for Wicked Woods, without making public ATProto social records part of the launch-critical path.
```

## Why

```gpt-5
Wicked Woods needs practical attendee behavior such as saving performances and building a personal schedule before the broader community/social publishing model is ready. Public favorites, public attendance, and cross-app social semantics should not block the first event-ready app.
```

## Rough Shape

```gpt-5
- Let attendees favorite/save performances locally.
- Use stable local IDs that can later map to AT URIs when performances become public OME records.
- Keep the state device-local or private-sync oriented in the first slice.
- Make the UI feel event-ready: saved performance state should be visible in schedule rows, performance details, and any "my schedule" surface.
- Do not publish `app.openmusicevent.performanceFavorite`, attendance, RSVP, or public interest records in this slice.
- Leave the future public action semantics explicit: favorite, interest, planned attendance, and actual attendance are separate concepts.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/Schedule`, `Sources/OpenMusicEventAppEventViewer/EventViewerState.swift`, `Sources/OpenMusicEventLexicon/MusicEvent.swift`.
```

## Open Questions

```gpt-5
- Should local saved performances live in the main event database, a user-state table, or a separate private sync bundle?
- Should saved state be per event, per performance, or both?
- Does "favorite" mean visual bookmarking, personal schedule planning, or recommendation signal in the Wicked Woods app?
- How should local saved state migrate when a performance gains a public AT URI later?
```

## Next Step

```gpt-5
Define the local saved-performance table/model and wire it through the schedule row and performance detail surfaces before adding any public ATProto action records.
```
