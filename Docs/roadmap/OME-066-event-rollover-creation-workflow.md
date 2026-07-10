---
id: OME-066
type: roadmap-card
area: editing
kind: feature
tags:
  - source
  - organizer
  - rollover
  - ios
launch: wicked-woods
priority: high
created: "2026-07-10"
---

# Event Rollover Creation Workflow

## Summary

Add an explicit "Start from previous event" path to event creation so organizers can create a new source-backed event by selecting which durable pieces of a previous event should seed the new one.

## Why

Annual event setup is not a clone operation. Some parts of a recurring event are durable enough to carry forward, while schedule-bound content, artist bookings, announcements, credentials, and trust state should not silently appear in a new year.

The app should make this distinction while the organizer is thinking about the new event. Organizers should go through the app, choose the previous event, select exactly which stages, map places, theme settings, venue details, and communication channels to seed, then receive a reviewable source diff plus a checklist of follow-up work.

This keeps source control as the portable/auditable representation without asking organizers to manage source files directly.

## Rough Shape

- Add a "Start from previous event" option to the existing event creation entry point alongside blank/source-backed creation.
- Collect the new event basics before rollover writes:
  - event name
  - event directory / slug
  - start date
  - end date
  - time zone
  - previous event to seed from
- Present a selectable rollover checklist instead of hidden duplication rules:
  - stages, selectable one by one
  - venue/location details
  - site map places, selectable by place and possibly by category
  - theme and branding settings
  - communication channel definitions
- Preserve stable IDs only for durable things that are intentionally the same across years:
  - same physical stage
  - same venue/location
  - same durable site-map place
  - same communication channel identity when it represents the same channel concept
- Generate new identity for date-bound or booking-bound content.
- Do not carry artist/contributor rosters in the first slice. Artist rollover generally does not make sense, and contributor identity carries trust expectations that should not be implied by a previous year's booking.
- Do not carry credentials, contributor claims, authoring permissions, team membership, approval state, or other trust state by default.
- Do not carry announcements, alerts, or sent message history. Channel definitions can carry forward, but message content should be created fresh.
- Do not carry schedule performances by default. A later planning mode can use a previous schedule as reference without treating it as new-year data.
- After generation, show the organizer a source-backed review surface:
  - reviewable source diff
  - generated setup checklist
  - clear warnings for anything omitted by design
- Use the same source-backed event creation and patch/proposal boundaries as [[OME-063-source-backed-event-creation-for-wicked-woods-2026|OME-063: Source-Backed Event Creation for Wicked Woods 2026]] instead of creating a separate source-writing path.
- Keep the first version local/reviewable. Publishing, pull requests, and merge automation should remain outside the first rollover slice.
- Code pointers: `Sources/OpenMusicEventApp/CreateEvent.swift`, `Sources/OpenMusicEventSource/FileTrees.swift`, `Sources/OpenMusicEventSource/DTOs.swift`, `Sources/OpenMusicEventSourceEditing/OpenMusicEventSourcePatchGeneration.swift`, `Sources/OpenMusicEventSourceEditing/SourceProvenance.swift`, `Docs/roadmap/OME-063-source-backed-event-creation-for-wicked-woods-2026.md`, and `Docs/roadmap/OME-062-site-map-and-wayfinding.md`.

## Checklist Shape

The generated event should include a post-creation checklist so rollover becomes a planning workflow, not just a data operation.

- Confirm event dates and time zone.
- Review carried-over stages.
- Review carried-over venue/location details.
- Review carried-over site map places and stage links.
- Review theme and branding.
- Review communication channels.
- Add lineup/artists.
- Build schedule.
- Add or refresh sponsors/supporters if that surface exists.
- Draft announcements and alerts from scratch.
- Review source diff.
- Publish or propose when ready.

## Open Questions

- Should rollover live inside `CreateEvent.State` as a creation strategy, or should it be a source-management action that opens the create flow preconfigured?
- Which fields define "same physical stage" strongly enough to preserve a stage ID across years?
- Should site-map places default to all selected, none selected, or dependency-selected from chosen stages?
- Should communication channel definitions preserve IDs across years, or should they create new IDs linked to previous channel concepts?
- Is organizer team rollover ever appropriate, and if so should it be a separate explicit authority review flow rather than part of event creation?
- Should the generated checklist be stored as editable organizer task state, or is it just a post-creation guidance surface?

## Acceptance Criteria

- Event creation offers "Start from previous event" as an explicit option.
- The organizer can choose the previous event and enter new event basics before any rollover writes occur.
- The first slice lets the organizer select specific stages and at least one other durable data group to carry forward.
- Artist/contributor rosters, credentials, authoring permissions, announcements, alerts, and schedule performances are not carried by default.
- Channel definitions can be carried forward without carrying message history or notification state.
- The generated event is source-backed and produces a reviewable source diff.
- The app shows a generated setup checklist after creation.
- Focused tests cover selected stage rollover, omitted artist roster, omitted trust state, channel-definition carryover without messages, slug collision, and source diff generation.

## Next Step

Sketch the `CreateEvent` creation-strategy model that can represent blank creation, source-backed creation, and previous-event rollover while sharing the same source writer boundary.
