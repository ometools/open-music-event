---
id: OME-069
type: roadmap-card
area: publishing
kind: pipeline
tags:
  - source
  - atproto
  - organizer
launch: wicked-woods
priority: high
created: "2026-06-17"
---

# Source Release to OME Publish Pipeline

## Summary

```gpt-5
Define how an accepted source-managed event revision becomes published OME ATProto records.
```

## Why

```gpt-5
The app already has source editing and Tangled proposal publishing. Public OME record publishing needs a separate release boundary so local edits do not immediately become public network facts. Wicked Woods should prove that source review, source revision, OME record publish, readback, and AppView indexing can form one boring pipeline.
```

## Rough Shape

```gpt-5
- Treat source repositories as the collaborative authoring source of truth.
- Publish OME records only from an explicit source state: accepted proposal, selected commit, tag, release, or manual publish action.
- Record source provenance for every published record:
  - source repository
  - source event directory
  - source commit/ref/release
  - publishing actor DID
  - published AT URI
  - latest CID
  - publish status and error state
- Support republishing after source changes without losing stable AT URIs.
- Keep community-calendar projection out of this first pipeline; that belongs to the later community/interoperability phase.
- Code pointers: `Sources/OpenMusicEventSourceEditing`, `Sources/OpenMusicEventSourceClone`, `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventLexicon`.
```

## Open Questions

```gpt-5
- Is the first release boundary an accepted Tangled pull, a local source commit, a manual publish button, or a semantic version tag?
- Should the native app initiate publish directly, or should the AppView/server own publish jobs after the source revision is selected?
- What status states are needed: pending, published, failed, stale, superseded, deleted?
- How should a failed publish be retried without creating duplicate records?
```

## Next Step

```gpt-5
Sketch the `SourcePublication`/`EventPublication` model and choose the first release trigger for Wicked Woods.
```
