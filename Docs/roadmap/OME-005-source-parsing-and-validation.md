---
id: OME-005
type: roadmap-card
area: source
kind: validation
priority: high
created: "2026-06-09"
---

# Source Parsing and Validation

## Summary

Parse source repository files into draft domain records and validate source trees.

## Why

Source data must be trusted enough for import, browsing, and edit proposals without requiring organizers to hand-edit app databases.

Validation should not become the primary organizer workflow. The app should make invalid data hard to create through constrained forms, pickers, relationship-aware edits, and source-backed creation flows. Source validation remains a boundary guard for imported files, hand-edited source, migrations, external integrations, CI, and proposal/publish preflight.

## Rough Shape

- Convert YAML and Markdown source files into OpenMusicEvent draft records.
- Validate before local insertion or use as an editable baseline.
- Keep app-authored data constraint-preserving by construction whenever possible.
- Use diagnostics for data that did not originate from trusted app flows:
  - imported source repositories
  - external spreadsheets or integration output
  - manual source edits
  - migration output
  - CI and release gates
  - proposal/publish preflight
- Report source diagnostics with enough file/path/context for an organizer or maintainer to fix the data without treating the app as a source editor.
- Code pointers: `Sources/OpenMusicEventSource/SourceValidation.swift`, `Tests/OpenMusicEventSourceTests`.

## Open Questions

- Which validation failures should be warnings instead of hard errors?
- Which invalid states can be made impossible in app authoring instead of reported after the fact?
- Which diagnostics need source-file precision, and which should be projected into app-friendly organizer language?

## Next Step

- Split the validation contract into app-authoring invariants and external/source-boundary diagnostics, then make the CLI and app surfaces report the right version for their audience.
