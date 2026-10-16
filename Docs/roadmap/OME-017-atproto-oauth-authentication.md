---
id: OME-017
type: roadmap-card
area: identity
kind: integration
priority: high
created: "2026-06-09"
---

# ATProto OAuth Authentication

## Summary

Wire ATProto OAuth into the app for identity and authenticated infrastructure actions.

## Why

Identity should come from ATProto while the app remains focused on event workflows.

## Rough Shape

- Keep OpenMusicEvent-specific account choices in the app layer.
- Use the shared auth package for the protocol flow.
- Code pointers: `Sources/OpenMusicEventAuthentication`, `Sources/OpenMusicEventAuthentication/Resources/oauth-client-metadata.json`, `Tests/OpenMusicEventAuthenticationTests`.

## Open Questions

- Which additional OAuth requirements are needed before source publishing is user-ready?

## Next Step

- Keep app OAuth metadata in sync with the manifest-generated requirements.
