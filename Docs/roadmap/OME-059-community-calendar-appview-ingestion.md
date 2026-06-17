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

Plan AppView ingestion for public `community.lexicon.calendar.event` and `community.lexicon.calendar.rsvp` records, starting with atmo.rsvp and Smoke Signal as real integration targets.

## Why

Community calendar records give OpenMusicEvent a useful interoperability path before every event is published as an OME-native record. atmo.rsvp and Smoke Signal already exercise the shared calendar event and RSVP lexicons, so they are good first sources for proving AppView ingestion without making any one producer's behavior part of the core OME event contract.

## Phase Boundary

```gpt-5
This is not part of the Wicked Woods launch-critical org publishing slice. Wicked Woods should first prove source-managed OME records, [[OME-068-wicked-woods-local-attendee-state|local attendee favorites/personal schedule state]], and an [[OME-070-wicked-woods-appview-event-snapshot|OME event snapshot AppView surface]]. Community-calendar publishing, public RSVP/attendance semantics, atmo.rsvp, Smoke Signal, public favorites, and cross-app social behavior are intentionally later interoperability/community work.
```

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
- Smoke Signal comparison: public pages expose global activity, regional/my-location browsing concepts, event counts, and RSVP counts; its source documents support for `community.lexicon.calendar.event`, `community.lexicon.calendar.rsvp`, `community.lexicon.location`, and Smoke Signal-specific profile/acceptance records.
- Keep the base mixed browse ranking mostly chronological for upcoming events, with light boosts for followed, trusted, and nearby signals.
- Plan explicit future surfaces for Featured and What's Hot rather than making the default browse order feel opaque or algorithmic.
- Keep OME-native event rows unadorned; show a compact source tag on third-party/community-calendar rows such as atmo.rsvp, Smoke Signal, or other producers.
- Show possible duplicate events as separate rows in the first slice unless there is an explicit merge/link signal; avoid automatic matching by name/date/location alone.
- Include RSVP counts in the AppView projection so the UI can surface them later, even if the first browse row only uses a `has RSVPs` filter.
- Use `community.lexicon.calendar.rsvp` as the only attendance signal in this slice; ticketing is out of scope and should remain a future extension that does not overload RSVP records.
- Preserve atmo.rsvp public event URLs such as `/p/{actor}/e/{rkey}` as source enrichment when present, but use the AT URI as the durable event identity.
- Keep the first slice read-only: no RSVP writes, no invite/private-space support, and no organizer-authority assumptions.
- Use producer AppViews as the primary near-term hydration source for browse design and personal browsing, while keeping the OME AppView as the long-term app surface.
- Before the hosted OME AppView exists, add a local ingest path that fetches real records from producer AppViews, caches or snapshots them locally, and projects them into the same browse shape the hosted AppView will eventually serve.
- Use fixtures as a supplement for edge cases, static previews, and deterministic tests; they should not be the main design data source.
- For OME-owned publishing, prefer publishing a portable `community.lexicon.calendar.event` record for interoperability and an OME-native record only when richer OME behavior is needed; the AppView can combine them into one browse projection when there is an explicit link.
- Code pointers: `Docs/roadmap/OME-028-appview-indexing-service.md`, `Docs/roadmap/OME-042-appview-query-surface.md`, `Sources/OpenMusicEventLexicon/MusicEvent.swift`, and the AppView baseline workspace.

## Publishing and Combining

The good version of "do both" is to publish portable community records and OME-native records as separate source facts, then let the AppView combine them when the relationship is explicit.

```gpt-5
Recommended direction:

- Publish `community.lexicon.calendar.event` for public interoperability: name, description, timing, status, mode, locations, and useful URLs.
- Publish `community.lexicon.calendar.rsvp` for attendee intent against the community event record.
- Publish OME-native records for OME-specific richness: schedules, stages, site maps, images, policies, organizer authority, source editing, and white-label behavior.
- Do not require the portable community record to carry OME-specific fields.
- Do not publish duplicate-looking records and ask the AppView to guess that they are the same event.
- Give the AppView an explicit relationship to join on, such as an OME event referencing a community event strongRef, or a separate OME link/mapping record.
- The browse projection can then show one row with the community record's public reach, OME-native details when present, source tags, RSVP counts, and OME affordances.
```

This keeps `SwiftCommunityLexicon` useful outside OME while leaving OME free to model the parts that are actually OME-specific.

### Link Shape Consequences

The link shape decides who can assert sameness, how easy repairs are, and whether the AppView can collapse records without guesswork.

| Shape | Consequences |
| --- | --- |
| Field on the OME event | Simple and easy for the AppView to query. Best when OME creates both records together and knows the portable event at publish time. But it is OME-owned and write-time coupled: adding, correcting, or removing the relationship means updating the OME event record. It is weaker for retroactive imports and third-party community events because only the OME event author can add the link. |
| Separate OME link/mapping record | More flexible. It can be created after the fact, repaired without touching the event, and potentially represent links between existing OME-native and community-calendar records. But it adds another record type, another trust/authority question, and more AppView logic: whose mapping record is allowed to collapse rows? |
| Both | Most practical long term. The OME event can carry a direct canonical link for the common publish path, while a mapping record handles retroactive repair, migration, and third-party linking. The cost is precedence rules: the AppView needs to know what happens when the embedded link and mapping records disagree. |

For the merge identity, prefer a stable AT URI as the long-lived event link and preserve CID as provenance/last-seen content, not as the only durable join key. A strict `strongRef` is useful when the exact version matters, but event records are expected to edit over time and their CID will change.

## Local Ingest Slice

The local ingest slice is a development/design bridge, not a replacement for the real OME AppView. It should pull real records from existing producer AppViews for the main browsing and personal-discovery design work, then preserve the same projection boundary the hosted OME AppView will eventually serve.

```gpt-5
Suggested shape:

- Keep the app pointed at an AppView-shaped browse client from the start.
- Implement a local adapter for that client that can fetch from producer AppViews such as atmo.rsvp and, once verified, Smoke Signal.
- Cache or snapshot producer responses locally so design work does not depend on every preview or simulator run making network calls.
- Decode community calendar event and RSVP records into source-record structs.
- Project those source records into browse rows with source tags, coarse location buckets, timing, mode, and RSVP counts.
- Keep local ingest read-only. It may use live records for the main design path, but should also support deterministic snapshots for repeatable previews and focused UI tests.
- Add fixture-only records for states that are hard to get from live producer data: duplicate candidates, missing location, denied location permission, high RSVP counts, cancelled/postponed events, unknown producer tags, and empty results.
- Avoid teaching browse UI about atmo.rsvp or Smoke Signal response shapes directly; source-specific parsing belongs before the projection boundary.
```

Possible Swift sketch for the planning boundary:

```swift
struct CommunityCalendarEventSourceRecord: Equatable, Identifiable {
  var id: ATURI
  var cid: CID?
  var producer: CommunityCalendarProducer?
  var record: CommunityCalendarEventRecord
  var sourceURL: URL?
}

struct CommunityCalendarRSVPSourceRecord: Equatable, Identifiable {
  var id: ATURI
  var cid: CID?
  var subject: StrongRef
  var status: CommunityCalendarRSVPStatus
  var actorDID: DID
}

struct BrowseEventProjection: Equatable, Identifiable {
  var id: BrowseEventIdentity
  var source: BrowseEventSource
  var title: String
  var startsAt: Date?
  var endsAt: Date?
  var mode: EventMode?
  var locationSummary: String?
  var locationBucket: Geohash?
  var rsvpCounts: RSVPCounts
  var sourceURL: URL?
}

enum BrowseEventSource: Equatable {
  case omeNative
  case communityCalendar(CommunityCalendarProducer?)
}

struct BrowseEventsQuery: Equatable {
  var dateRange: Range<Date>?
  var filters: Set<BrowseEventFilter>
  var locationScope: BrowseLocationScope?
}
```

The local adapter can support three data modes:

- Live producer pull: the main design mode for real event records and personal browsing.
- Cached producer snapshot: a refreshed local copy of real producer records for stable simulator work.
- Fixture overlay: hand-authored records for edge cases, static previews, and deterministic tests.

Acceptance criteria for this slice:

- The browse screen can render OME-native and community-calendar rows through one AppView-shaped client.
- Third-party rows carry source tags while OME-native rows remain unadorned.
- The main design dataset comes from real producer AppView records, not hand-authored fixtures.
- The local ingest path can refresh and cache/snapshot producer AppView responses.
- Fixture overlays cover upcoming, nearby, followed, source, has-RSVPs, duplicate, missing-location, cancelled/postponed, unknown-producer, and empty-state cases.
- RSVP counts are present in the projection even if the first UI only exposes `has RSVPs`.
- Local ingest does not create records, write RSVPs, crawl the firehose, or require a hosted OME AppView.
- Replacing the local adapter with the real AppView client should not require redesigning browse row state.

## Open Questions

- Should the first ingestion worker subscribe directly to Jetstream by NSID, or should it backfill through a smaller known-source crawl first?
- Which producer AppView calls should the first local ingest adapter use for atmo.rsvp and Smoke Signal?
- Should local ingest fetch only public browse records first, or include personal browsing inputs such as actor, following, or RSVP context immediately?
- Should the browse screen depend on an AppView-shaped client immediately, even while the first implementation is producer-AppView-backed?
- Should local ingest cache raw producer responses, normalized source records, or final browse projections?
- How often should the local producer snapshot refresh, and should refresh be manual, app-launched, or command-line only?
- How much fixture-overlay diversity is enough for edge cases: number of events, sources, locations, RSVP states, and duplicate cases?
- Which signals are allowed to boost default chronological ranking, and how should the app explain that order?
- What data should eventually power Featured and What's Hot: editorial picks, follows, RSVP velocity, source trust, locality, or some mix?
- What geohash precision should each coarse nearby scope use?
- How should AppView derive location buckets from community records that provide only address fields, only geo coordinates, or H3 values?
- What fallback should the nearby filter show before location permission is granted or after it is denied?
- What exact source tags should third-party/community-calendar rows show, and should unknown producers be grouped as Community Calendar?
- Should the first known-source backfill seed both atmo.rsvp and Smoke Signal, or should source tagging arrive only through generic NSID ingestion?
- What is the explicit link shape between an OME-native event and a portable community calendar event: field on the OME event, separate mapping record, or both?
- What explicit merge/link signal should allow OME-native and community-calendar records to collapse into one row later?

## Next Step

- Draft the producer-backed local ingest contract: one AppView-shaped browse client, one atmo.rsvp-backed adapter, one local cache/snapshot format, and fixture overlays only for edge cases and previews.
