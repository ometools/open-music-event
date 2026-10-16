---
id: OME-040
type: roadmap-card
area: identity
kind: onboarding
priority: medium
created: "2026-06-09"
---

# PDS / Account Provider Onboarding

## Summary

Shape the OpenMusicEvent account-provider onboarding flow around app-side provider choices and custom PDS entry.

## Why

OpenMusicEvent needs practical account onboarding without turning shared auth into a provider registry. Provider metadata should stay app-side unless that boundary is deliberately reopened.

## Rough Shape

- Present OME, Bluesky, Eurosky, and custom server choices from app-owned configuration.
- Keep community/provider metadata as enrichment, not a required runtime registry dependency.
- Preserve the future path for branded handles and OME-hosted accounts.
- Code pointers: `Sources/OpenMusicEventAuthentication/OpenMusicEventOAuth.swift`, `Sources/OpenMusicEventAuthentication`, `Tests/OpenMusicEventAuthenticationTests`.

## Open Questions

- When should the OME-hosted account option move from coming soon to available?
- Which provider details should be static versus fetched?

## Next Step

- Review the sign-up provider UI against the current app-layer OAuth configuration.
