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

```gpt-5
- Treat app manifest metadata as the source of truth for registered requirements.
- Keep static OAuth metadata synchronized with generated manifest data.
- Split public AppView reads from authenticated actions where possible.
- For the Wicked Woods slice, keep hosted event snapshot reads public/cacheable unless a specific authenticated action is required.
- Add OME repo-write requirements only when the first org-owned publish target is chosen.
- Do not include community RSVP, public favorite, or public attendance scopes in the launch-critical Wicked Woods path.
- Code pointers: `Sources/OpenMusicEventAuthentication`, `Sources/OpenMusicEventAuthentication/Resources/oauth-client-metadata.json`, `Sources/OpenMusicEventLexicon`.
```

## Open Questions

- Which AppView calls require auth in the first service slice?
- What guardrail test should catch stale OAuth metadata?
- Which OME record-write permissions are needed for `app.openmusicevent.event`, `app.openmusicevent.performance`, and `app.openmusicevent.stage`?
- Does publish auth live in the native app, the AppView server, or both for the first source-managed release?

## Next Step

- Draft auth requirements alongside the first org-owned OME publish target and the public Wicked Woods event snapshot query.
