---
id: OME-029
type: roadmap-card
area: collaboration
kind: workflow
priority: high
created: "2026-06-09"
---

# Organizer Collaboration Workflows

## Summary

Make source-backed proposals easier for organizers to review, accept, reject, and publish.

## Why

The source-backed editing model is only useful if organizers can confidently move proposed changes into their event source.

## Rough Shape

- Keep collaboration workflows tied to source provenance and authenticated identity.
- Build on the existing source proposal flow rather than inventing a separate review model.
- Code pointers: `Sources/OpenMusicEventAppEventViewer/SourceProposalFlow.swift`, `Sources/OpenMusicEventSourceEditing`.

## Open Questions

- What should the organizer see before accepting a patch?
- Should review happen primarily in app, Tangled, or both?

## Next Step

- Design the smallest review flow around one generated source patch.
