---
id: OME-027
type: roadmap-card
area: atproto
kind: publishing
priority: high
created: "2026-06-09"
---

# Org-Owned OME Record Publishing

## Summary

Publish canonical OpenMusicEvent records to ATProto for organizer-owned, source-managed events.

## Why

ATProto should become the durable public network layer for OME event facts, but the first slice should support Wicked Woods and source-managed organizer publishing before community/social interoperability.

## Rough Shape

```gpt-5
- Start with OME-native records for source-managed events, not public user actions.
- Treat `app.openmusicevent.event` as the canonical OME event record.
- Prefer first-class `app.openmusicevent.performance` records when performances need stable public references.
- Treat `app.openmusicevent.stage` as a stable event-scoped target record when performances, maps, filters, or alerts need to point at it.
- Keep schedules under discussion; they may be source structure, display projection, release artifact, or a later public record.
- Do not make `community.lexicon.calendar.event`, public favorites, public attendance, atmo.rsvp, or Smoke Signal prerequisites for the Wicked Woods publishing slice.
- Source-managed publishing should happen from an explicit source/release boundary, not from every local edit.
- Store published AT URIs and latest CIDs as provenance for readback, AppView indexing, repair, and later community links.
- Coordinate with [[OME-069-source-release-to-ome-publish-pipeline|Source Release to OME Publish Pipeline]] and [[OME-070-wicked-woods-appview-event-snapshot|Wicked Woods AppView Event Snapshot]].
- Code pointers: `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventSourceEditing`, `Sources/OpenMusicEventAppEventViewer/SourceProposalFlow.swift`, `Sources/OpenMusicEventSourceEditing/TangledSourcePatchPublisher.swift`.
```

## Open Questions

- Which OME record is the first publish target for Wicked Woods: event only, or event plus performances?
- Does a source-managed publish happen from an accepted Tangled proposal, a manual publish action, a source tag/release, or an AppView-side job?
- Does the organizer DID publish directly, or does the first version publish from the authenticated editor while preserving source/organizer provenance?
- What rkey policy should OME use for event, performance, and stage records so source IDs remain stable?
- Which source fields must be encoded differently for ATProto record constraints before publish?

## Next Step

- Define the first Wicked Woods publish plan: source event to `app.openmusicevent.event`, optional performances, readback, and stored provenance.
