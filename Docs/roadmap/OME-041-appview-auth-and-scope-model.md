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
- Do not require an ATProto account for attendee push notifications. Register and update a device installation through an unauthenticated XRPC procedure using an opaque installation-scoped capability.
- Keep any later DID association optional and additive. Account OAuth may synchronize notification state across installations, but it must not become the identity required to receive event notifications.
- Apply abuse controls such as request limits, capability rotation, and optional platform attestation at the installation boundary rather than treating account login as the only protection.
- Do not add anonymous notification registration to the OAuth app manifest's required permissions.
- Code pointers: `Sources/OpenMusicEventAuthentication`, `Sources/OpenMusicEventAuthentication/Resources/oauth-client-metadata.json`, `Sources/OpenMusicEventLexicon`, and `Docs/roadmap/OME-067-appview-push-notification-delivery.md`.
```

## Open Questions

- Which AppView calls require auth in the first service slice?
- What guardrail test should catch stale OAuth metadata?
- Which OME record-write permissions are needed for `app.openmusicevent.event`, `app.openmusicevent.performance`, and `app.openmusicevent.stage`?
- Does publish auth live in the native app, the AppView server, or both for the first source-managed release?
- How should an installation capability be issued, stored, rotated, and revoked without requiring an account?
- Which registration abuse controls belong in the first public service deployment?

## Next Step

- Draft auth requirements alongside the first org-owned OME publish target and the public Wicked Woods event snapshot query.
- Draft a per-XRPC authorization table alongside the first AppView endpoints, including public reads, anonymous installation registration, and authenticated account operations.
