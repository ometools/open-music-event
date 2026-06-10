---
id: OME-041
type: roadmap-card
area: appview
kind: auth
priority: high
created: "2026-06-09"
---

# AppView Auth and Scope Model

## Summary

Define the OAuth scopes and AppView authorization requirements for OpenMusicEvent service calls.

## Why

AppView-backed features need explicit auth requirements and static metadata that matches the app manifest. Missing scopes should be caught before runtime.

## Rough Shape

- Treat app manifest metadata as the source of truth for registered requirements.
- Keep static OAuth metadata synchronized with generated manifest data.
- Split public AppView reads from authenticated actions where possible.
- Code pointers: `Sources/OpenMusicEventAuthentication`, `Sources/OpenMusicEventAuthentication/Resources/oauth-client-metadata.json`, `Sources/OpenMusicEventLexicon`.

## Open Questions

- Which AppView calls require auth in the first service slice?
- What guardrail test should catch stale OAuth metadata?

## Next Step

- Draft the first AppView auth requirement alongside the first concrete AppView query.
