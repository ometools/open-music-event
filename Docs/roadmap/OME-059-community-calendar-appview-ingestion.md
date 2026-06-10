---
id: OME-059
type: roadmap-card
area: appview
kind: ingestion
priority: high
created: "2026-06-10"
---

# Community Calendar AppView Ingestion

## Summary

Plan AppView ingestion for public `community.lexicon.calendar.event` and `community.lexicon.calendar.rsvp` records, starting with atmo.rsvp as the first real integration target.

## Why

Community calendar records give OpenMusicEvent a useful interoperability path before every event is published as an OME-native record. atmo.rsvp already exercises the shared calendar event and RSVP lexicons, so it is a good first source for proving AppView ingestion without making atmo.rsvp-specific behavior part of the core OME event contract.

## Rough Shape

- Treat `community.lexicon.calendar.event` records as external source records with stable AT URIs and CIDs.
- Decode the shared event fields first: `createdAt`, `name`, `description`, `startsAt`, `endsAt`, `status`, `mode`, `locations`, and `uris`.
- Treat `community.lexicon.calendar.rsvp` records as attendance signals keyed by their `com.atproto.repo.strongRef` subject.
- Normalize ingested records into AppView discovery/search projections rather than inserting them as if they were OME-owned source repositories.
- Surface community-calendar events in the same browse universe as OME-native events; filtering and provenance should decide what appears, not a separate browse page.
- Use a mixed browse default: upcoming events are broadly visible, with prominent filters for followed, nearby, atmo.rsvp, OME-native, and has RSVPs.
- Treat nearby as an opt-in device-location filter; the default browse page should still work without location permission.
- Send geohash or equivalent coarse location buckets to the AppView for nearby queries, rather than precise coordinates.
- Expose nearby filtering as coarse user-facing scopes such as nearby, region, and anywhere; map those scopes to geohash precision internally.
- atmo.rsvp comparison: current public browsing appears to be upcoming/popular/search oriented; event creation uses manual Nominatim geocoding into address fields, not device-location nearby browsing.
- Keep the base mixed browse ranking mostly chronological for upcoming events, with light boosts for followed, trusted, and nearby signals.
- Plan explicit future surfaces for Featured and What's Hot rather than making the default browse order feel opaque or algorithmic.
- Keep OME-native event rows unadorned; show a compact source tag on third-party/community-calendar rows such as atmo.rsvp or other producers.
- Show possible duplicate events as separate rows in the first slice unless there is an explicit merge/link signal; avoid automatic matching by name/date/location alone.
- Include RSVP counts in the AppView projection so the UI can surface them later, even if the first browse row only uses a `has RSVPs` filter.
- Use `community.lexicon.calendar.rsvp` as the only attendance signal in this slice; ticketing is out of scope and should remain a future extension that does not overload RSVP records.
- Preserve atmo.rsvp public event URLs such as `/p/{actor}/e/{rkey}` as source enrichment when present, but use the AT URI as the durable event identity.
- Keep the first slice read-only: no RSVP writes, no invite/private-space support, and no organizer-authority assumptions.
- Code pointers: `Docs/roadmap/OME-028-appview-indexing-service.md`, `Docs/roadmap/OME-042-appview-query-surface.md`, `Sources/OpenMusicEventLexicon/MusicEvent.swift`, and the AppView baseline workspace.

## Open Questions

- Should the first ingestion worker subscribe directly to Jetstream by NSID, or should it backfill through a smaller known-source crawl first?
- Which signals are allowed to boost default chronological ranking, and how should the app explain that order?
- What data should eventually power Featured and What's Hot: editorial picks, follows, RSVP velocity, source trust, locality, or some mix?
- What geohash precision should each coarse nearby scope use?
- How should AppView derive location buckets from community records that provide only address fields, only geo coordinates, or H3 values?
- What fallback should the nearby filter show before location permission is granted or after it is denied?
- What exact source tags should third-party/community-calendar rows show, and should unknown producers be grouped as Community Calendar?
- What explicit merge/link signal should allow OME-native and community-calendar records to collapse into one row later?

## Next Step

- Draft a minimal ingestion contract that accepts one decoded community calendar event record and one RSVP record, then maps them into a read-only AppView projection.
