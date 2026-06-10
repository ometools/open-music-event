---
id: OME-036
type: roadmap-card
area: source
kind: provenance
priority: high
created: "2026-06-09"
---

# Source Provenance and Clone Freshness

## Summary

Make it clear which source repository, clone, ref, and import produced local event data.

## Why

Stale clones and unclear provenance can look like parser bugs or missing source data. The app and CLI should surface the exact source baseline before users debug the wrong thing.

## Rough Shape

- Track source clone location, source ref, organizer ID, event ID, and import time where the app needs it.
- Surface stale clone or mismatched provenance signals in source download, validation, and editing flows.
- Keep source provenance tied to the local database and editing session baseline.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventSourceClone`, `Sources/OpenMusicEventSourceEditing`.

## Open Questions

- Which provenance fields should be visible in the app versus only CLI/debug output?
- Should the app warn before editing against a stale clone?

## Next Step

- Add a narrow provenance display or diagnostic path for one imported Tangled source.
