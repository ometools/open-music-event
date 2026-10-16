---
id: OME-034
type: roadmap-card
area: tooling
kind: ci
priority: medium
created: "2026-06-09"
---

# CI / Tack Buildkite Pipeline

## Summary

Add the standard Tangled/tack CI shape for Swift package build and test coverage.

## Why

Roadmap work is accumulating across source, database, app, and Skip surfaces. A small CI guardrail gives the project a shared signal before changes are treated as ready.

## Rough Shape

- Add a repo-specific tack Buildkite pipeline using a Swift Docker image and a simple `swift build && swift test` command.
- Keep CI focused on package health before adding Android or deployment lanes.
- Use CI failures to catch migration, parser, and source editing regressions early.
- Code pointers: `.tangled/workflows/ci.yml`, `Package.swift`, `Tests`.

## Open Questions

- Which Swift toolchain image should be the baseline for this repo?
- Should Skip parity checks run in this pipeline or a separate Android-focused lane?

## Next Step

- Add the minimal Swift build/test CI pipeline, then expand only after it is stable.
