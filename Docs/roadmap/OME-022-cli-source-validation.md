---
id: OME-022
type: roadmap-card
area: tooling
kind: cli
priority: medium
created: "2026-06-09"
---

# CLI Source Validation

## Summary

Expose source repository validation and import workflows through the `ome` command-line tool.

## Why

The source format needs a toolable workflow outside the app for developers and organizers managing repositories.

## Rough Shape

- Support local source roots and supported Tangled repository references.
- Keep CLI validation aligned with app import behavior.
- Code pointers: `Sources/OpenMusicEventCLI`, `Tests/OpenMusicEventCLITests`.

## Open Questions

- Which validation output should be optimized for humans versus scripts?

## Next Step

- Keep CLI source validation tied to the same parser and insertion paths as the app.
