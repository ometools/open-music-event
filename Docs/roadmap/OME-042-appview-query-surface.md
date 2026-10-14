---
id: OME-042
type: roadmap-card
area: appview
kind: api
priority: high
created: "2026-06-09"
---

# AppView Query Surface

## Summary

Define the first concrete OpenMusicEvent AppView queries for app-friendly event loading.

## Why

The broad AppView service card needs a narrow query surface before implementation can start without overfitting the local database. The first query should serve Wicked Woods event data, not community discovery.

The query surface is also where "write once, display everywhere" becomes real. The same event graph should be able to power the native app, public web pages, schedule/list embeds, QR/App Clip routes, and third-party renderers without copying content into separate CMS shapes.

## Rough Shape

### Canonical AppView domain rule

The AppView persists domain data using OME lexicon types and semantics. External
records project into that model, retaining original source identity and local
provenance. Raw ingestion payloads and rebuildable query indexes are supporting
infrastructure, not alternate domain models. Views may select or omit information
but must not invent meaning or erase semantic distinctions. See
`Sources/OpenMusicEventAppViewServer/AGENTS.md` for implementation requirements.

The approved canonical-domain migration replaces the prelaunch flattened calendar
responses in place. Native record endpoints remain publication-faithful and must
not serialize imported domain rows as published OME records. Migration completion
requires isolated full-dataset preservation, adapter diagnostics, semantic API
tests, and local browser/runtime verification; recording this rule is not that proof.

```gpt-5
- Start with one [[OME-070-wicked-woods-appview-event-snapshot|event snapshot query]] for a known source-managed event.
- Include event identity, stages, performances, schedule rows, poster/site-map references, and source/publish provenance needed by the app.
- Keep local favorites and personal schedule state out of the hosted response in the first slice.
- Defer organizer calendar browsing, event search, contributor profile lookup, community discovery, and ranking policy until the event snapshot is proven.
- Code pointers: `Sources/OpenMusicEventDatabase`, `Sources/OpenMusicEventSource`, `Sources/OpenMusicEventLexicon`, `Sources/OpenMusicEventAppEventViewer`.
```

## Open Questions

- Which query is the smallest useful AppView endpoint?
- Which response shapes should be app-specific versus lexicon record-shaped?
- Should the first endpoint identify an event by source reference, OME AT URI, public slug, or a generated snapshot ID?
- Which parts of the response should be record-shaped, and which should be hydrated app projection?

## Next Step

- Complete the approved canonical-domain migration: optional domain fields and
  explicit adapter validation, raw-record backfill with diagnostics, canonical
  query indexes, typed calendar responses, and browser consumer cutover.
- Keep the local sandbox on the existing contract until the isolated full-data
  migration and replacement consumers pass acceptance. No remote deployment is
  authorized by this work.

## Canonical migration baseline — 2026-10-14

This is a pre-migration checkpoint, not a completion report.

- Workspace: `open-music-event-venue-did-globe`; base `270f1b0a`;
  change `tlsqnnqz`; local landing destination unset.
- Intended local runtime: `ome-globe-ome-globe-appview-1`, image
  `sha256:ede905ad76d4532da22290a489dbb282827d85cbd61d572cd50e3777ed520b5c`,
  database volume `ome-globe_ome-globe-appview-data`, public loopback port 18081.
- Consistent backup: `.build/globe-map-validation/pre-canonical-domain-3bdaf0c0-e6bb-42af-a3dc-61e3488d214c.sqlite`;
  SQLite `quick_check`: `ok`.
- Present raw events: 88,815 Community Calendar and 108 OME.
- Existing browse rows: 88,778; rows with latitude: 66,825.
- All 145 raw-event/browse-row differences are Community Calendar records.
  Samples include absent or non-string `createdAt`. Every difference still needs
  an explicit adapter disposition; do not presume all are equivalent failures.
- Raw store: 92,480 rows, including 199 deletion tombstones.
- SHA-256 of `quote(uri)`, `quote(cid)`, `quote(hex(value))`, and `isDeleted`
  for every raw indexed record, ordered by URI and delimited by tabs/newlines:
  `8d36d1c6380c79870a404c9072fcc7ba55a34c8b60a74258fa2bb88e66ec246b`.
  This was read from the consistent backup with SQLite `immutable=1`.
- Native-record API boundary and route tests: 15 passed. They now use production
  ingestion fixtures, preserve original payload/CID (including unknown fields),
  and reject external identities from native reads, bundles, and the viewer.
  The additional HTTP rejection assertions passed in the 15-test rerun.
- Separate database graph: both `EventRecordGraphTests` passed, including the
  prior-schema provenance upgrade and serialization-exclusion test. Commands:
  `OME_DATABASE=1 swift test --skip-update --filter EventRecordGraphTests` and
  `OME_APPVIEW=1 swift test --skip-update --filter 'CanonicalDomainBoundaryTests|AppViewRouteTests'`,
  both through the compiler lane with the local Atmosphere dependency override.
- Pre-migration loopback HTTP search baseline: `browseEventSummaries`, both
  catalogs, `dates=all`, `query=Wicked Woods`, `limit=50`, curl `--compressed`:
  three 200 responses, 4,104 downloaded bytes each, total times 197/120/115 ms.
  These are HTTP measurements, not database-only or browser-rendering evidence.
- Full canonical backfill, calendar response replacement, browser verification,
  and live cutover remain pending.
