---
id: OME-038
type: roadmap-card
area: identity
kind: workflow
priority: high
created: "2026-06-09"
---

# Contributor Claim Flow

## Summary

Define how event contributors connect their event-facing profiles to ATProto actor identity.

## Why

Contributor profile, organizer authority, and ATProto actor identity are distinct concepts. The app needs a clear claim flow before contributor profile ownership can become user-facing.

## Rough Shape

- Keep `Contributor` as the event-facing noun and ATProto actor as identity.
- Model claims so contributor profiles can be associated with actors without giving them organizer authority.
- Keep policy checks explicit for events that require contributor profile providers.
- Code pointers: `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventAppEventViewer/ContributorProfile.swift`, `Sources/OpenMusicEventAppEventViewer/EditEventPolicies.swift`.

## Open Questions

- What proof should be required for a contributor claim?
- Does the first claim flow need organizer approval, actor self-claim, or both?

## Next Step

- Draft the smallest contributor claim state model that can be displayed in the contributor profile UI.
