---
id: OME-016
type: roadmap-card
area: tangled
kind: integration
priority: high
created: "2026-06-09"
---

# Tangled Source Publishing

## Summary

Publish generated proposal patches through Tangled-facing source publishing infrastructure.

## Why

Organizer collaboration needs a way to move app edits from local state into a reviewable source proposal.

## Rough Shape

- Keep publishing tied to authenticated identity and explicit OAuth requirements.
- Publish proposal patches without making Tangled concepts dominate the native app.
- Code pointers: `Sources/OpenMusicEventSourceEditing/TangledSourcePatchPublisher.swift`, `Tests/OpenMusicEventAppTests/TangledSourcePatchPublisherTests.swift`.

## Open Questions

- What is the smallest user-facing proposal flow that is useful to organizers?

## Next Step

- Connect publishing results back into the app's source proposal UI.
