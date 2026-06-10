---
id: OME-039
type: roadmap-card
area: collaboration
kind: permissions
priority: high
created: "2026-06-09"
---

# Organizer Authority and Review Permissions

## Summary

Define who can publish, accept proposals, reject proposals, and represent organizer authority.

## Why

Source-backed collaboration depends on an authority boundary. Without it, proposal review, ATProto publishing, and source ownership can blur together.

## Rough Shape

- Keep organizer authority separate from contributor identity.
- Tie proposal review permissions to source ownership or explicit organizer delegation.
- Avoid baking temporary local assumptions into the future AppView authorization model.
- Code pointers: `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventSourceEditing`, `Sources/OpenMusicEventAppEventViewer/SourceProposalFlow.swift`.

## Open Questions

- Is organizer authority derived from source repository ownership, ATProto records, local configuration, or a staged combination?
- What can a contributor do without organizer authority?

## Next Step

- Define the first review permission rule for accepting a source patch.
