---
id: OME-037
type: roadmap-card
area: source
kind: testing
launch: wicked-woods
priority: medium
created: "2026-06-09"
---

# Live Event Source Smoke Tests

## Summary

Validate real event source repositories as smoke fixtures or periodic checks.

## Why

Synthetic fixtures are useful, but real event repositories reveal source drift, contributor terminology changes, image edge cases, and import assumptions faster.

## Rough Shape

- Pick a small set of real source repositories such as Shambhala, Wicked Woods, and Atmosphere Conf.
- Run parser/validator/import checks against known refs or controlled local clones.
- Keep live-source checks separate from fast unit tests if they require network or large data.
- Code pointers: `Sources/OpenMusicEventCLI`, `Tests/OpenMusicEventSourceTests`, `Tests/OpenMusicEventDatabaseTests`.

## Open Questions

- Which real sources are stable enough to use as smoke inputs?
- Should these checks run manually, in CI, or as a separate scheduled validation?

## Next Step

- Choose one real event source and document the exact validation command and expected summary.
