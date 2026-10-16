---
id: OME-047
type: roadmap-card
area: identity
kind: infrastructure
tags: []
launch:
priority: low
created: "2026-06-10"
---

# ome.social PDS Service

## Summary

Explore joining or using a PDS service so OpenMusicEvent can offer an `ome.social` PDS.

## Why

OpenMusicEvent needs a credible path to OME-hosted accounts and handles without prematurely committing to running all PDS infrastructure directly. A managed or joined PDS service could cover operations, account lifecycle, backups, migration, admin, and reliability while the product shape is still settling.

## Rough Shape

- Identify PDS service options that can support the `ome.social` domain.
- Decide whether `ome.social` is the PDS host, the handle namespace, or both.
- Document DNS, DID, account ownership, admin, moderation, backup, and migration requirements.
- Keep this distinct from app-side provider choice UI in [[OME-040-pds-account-provider-onboarding|OME-040: PDS / Account Provider Onboarding]].

## Open Questions

- Should `ome.social` use a managed/shared PDS service, a dedicated hosted PDS, or self-hosted infrastructure?
- What handle shape do we want for users: `@name.ome.social`, another subdomain, or something else?
- Who owns the operational responsibilities for accounts, support, moderation, and data export?

## Next Step

- Draft selection criteria for a PDS service that can support `ome.social`.
