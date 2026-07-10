---
id: OME-063
type: roadmap-card
area: editing
kind: feature
tags:
  - source
  - organizer
  - ios
launch: wicked-woods
priority: high
created: "2026-06-11"
---

# Source-Backed Event Creation for Wicked Woods 2026

## Summary

```gpt-5
Make the native "New Event" workflow create a real source-backed event for an existing organizer source, starting with Wicked Woods 2026. The result should be an editable event in the app and a reviewable `events/2026/event.yml` source change, not just a local database row.
```

## Why

```gpt-5
Wicked Woods needs to start building 2026 content through the real OpenMusicEvent workflow. The current `CreateEvent` feature can create a local event, but local-only events are not enough for handoff because they do not create source files, do not carry source provenance, and cannot immediately use the source-backed patch/proposal path.

The useful handoff bar is: an organizer can start from an imported/downloaded Wicked Woods source, create the 2026 event in the app, validate the source output, and continue filling in event info, stages, schedule, contributors, communications, posters, and map data against a source-backed baseline.

The user-facing model should remain app-first. Organizers should create and manage the event through the native workflow; source files are the portable/auditable output that enables collaboration, review, and display everywhere.
```

## Rough Shape

```gpt-5
- Add a source-backed creation mode to the existing `CreateEvent` feature instead of creating a parallel event wizard.
- Launch this mode from an imported/downloaded source context, such as a Wicked Woods source detail or organizer source view.
- Collect the minimum event fields needed to create the source event:
  - event name
  - event directory / slug, with Wicked Woods 2026 using `2026`
  - start date
  - end date
  - time zone
  - optional first-pass venue/location values if the current form can support them cleanly
- Reject event slugs that would collide with existing source event directories.
- Make invalid creation states hard to reach through constrained controls rather than relying on post-hoc source validation.
- Use the source file-tree writer to produce a minimal `events/<slug>/event.yml`.
- Insert the new event into the app database with `EventSourceProvenanceRecord` pointing to the selected source baseline and event directory.
- After creation, open the new event viewer and show it as source-backed so source patch generation and later edit surfaces work normally.
- Keep the first version local/reviewable: write to a local source checkout or generate a source patch/diff, then rely on normal review/publish mechanics outside this slice.
- Do not make Tangled publishing, in-app pull requests, or native schedule/contributor creation prerequisites for the first usable workflow.
- Treat [[OME-066-event-rollover-creation-workflow|OME-066: Event Rollover Creation Workflow]] as a follow-on creation strategy that shares the same source writer boundary.
- Code pointers: `Sources/OpenMusicEventApp/CreateEvent.swift`, `Sources/OpenMusicEventApp/MyEvents.swift`, `Sources/OpenMusicEventApp/OpenMusicEventBrowser.swift`, `Sources/OpenMusicEventSource/FileTrees.swift`, `Sources/OpenMusicEventSource/SourceModels.swift`, `Sources/OpenMusicEventSourceEditing/OpenMusicEventSourcePatchGeneration.swift`, `Sources/OpenMusicEventSourceEditing/SourceProvenance.swift`, `Tests/OpenMusicEventAppTests/CreateEventTests.swift`, and `Tests/OpenMusicEventAppTests/OpenMusicEventSourcePatchGenerationTests.swift`.
```

## Implementation Sketch

```gpt-5
Possible model shape:

    CreateEvent.State(
      mode: .local(...)
    )

    CreateEvent.State(
      mode: .sourceBacked(
        sourceBaselineID: SourceBaselineRecord.ID,
        organizerID: OMERecord.Organizer.ID,
        sourceReference: String,
        existingEventDirectories: Set<String>
      )
    )

The local mode can preserve the existing behavior. The source-backed mode should derive the event ID from the source directory or an explicit source ID policy rather than the current random UUID path, because Wicked Woods needs stable source-facing identity for `events/2026`.

The first writer boundary can be a small dependency that takes a source baseline, source event directory, and `OMERecord.Event.Draft`, then returns either a source patch or writes the new source event into a controlled local checkout. Keep this dependency testable without requiring Tangled or network access.

This boundary should be shared by blank source-backed creation and rollover creation. The creation mode should decide how the draft is seeded; the writer should not need to know whether the event came from a blank form, a previous event, or a later template/import path.
```

## Acceptance Criteria

```gpt-5
- From a Wicked Woods source context, "Add Event" opens the source-backed creation flow.
- Creating "Wicked Woods 2026" with slug `2026` creates or proposes `events/2026/event.yml`.
- The created event imports or appears in the app as source-backed, with provenance pointing at the Wicked Woods source baseline and `sourceEventDirectory == "2026"`.
- Attempting to create an event with an existing event directory shows a clear validation error before writing.
- The generated source can be validated with the current `ome source validate <source> --organizer-id <did> --verbose` path.
- The existing local-only create event path still works for non-source-backed experimentation.
- Focused tests cover local mode, source-backed mode, slug collision, provenance creation, and minimal source file output.
- The UI does not expose source-file management as the primary organizer workflow.
```

## Open Questions

```gpt-5
- Should source-backed creation write directly into the selected local source checkout, or should it generate a source patch first and let the user apply/review it?
- For v1, should the event ID be inferred from the source directory (`2026`) or written explicitly in `event.yml`?
- Which screen is the right launch point for Wicked Woods: downloaded source detail, organizer detail, or a dedicated "Manage Source" surface?
- Should venue/location be included in the first creation form, or added immediately after event creation through the existing event info editor?
```

## Next Step

```gpt-5
Prepare the implementation slice by choosing the first writer boundary: direct local source checkout write versus generated source patch. Then implement source-backed `CreateEvent` mode with tests before expanding the form beyond event basics.
```
