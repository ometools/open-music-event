---
id: OME-010
type: roadmap-card
area: app
kind: feature
priority: medium
created: "2026-06-09"
---

# Contributor Profiles

## Summary

Show event contributors and contributor profile details from local event data.

## Why

Contributors are event-facing people and projects, distinct from organizer authority and ATProto actor identity.

## Rough Shape

- Present contributor lists and profile details inside the event viewer.
- Keep contributor profile ownership separate from organizer publishing authority.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/ContributorsViewer.swift`, `Sources/OpenMusicEventAppEventViewer/ContributorProfile.swift`.

## Open Questions

- How should contributor claims connect to ATProto identity in the first public workflow?

## Next Step

- Keep contributor identity work tied to explicit claim and policy flows.
