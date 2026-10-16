# Local globe data path

This harness creates one private Atmo-in-a-Box PDS with five accounts: one durable DID
per venue. It publishes the standard `app.bsky.actor.profile/self` record and each
venue's complete canonical OME source graph. The AppView consumes the private PDS and
the public Community Calendar network through separate Hydrant instances. Only a
relay adapter, PLC adapter, and port-443-only HTTPS proxy used by the public Hydrant
join an egress network; the PDS, local PLC, private Hydrant, and AppView remain on
Atmo-in-a-Box's internal network.

Account handles use short stable labels where Atmo-in-a-Box's local handle limit is
shorter than the venue's source slug; the account profile retains the full venue name.

The runtime state, credentials, DIDs, identity maps, image cache, receipts, Hydrant
databases, and AppView database live under `.build/globe-local` and are not source
fixtures.

```sh
python3 Scripts/globe-local/sandbox.py prepare
python3 Scripts/globe-local/sandbox.py up
python3 Scripts/globe-local/sandbox.py seed
python3 Scripts/globe-local/sandbox.py sync
```

Open `http://127.0.0.1:18081/`. `up` starts a loopback-only HTTP proxy for the globe;
the proxy verifies the sandbox's public CA itself, so browser testing does not require
host-file entries or certificate installation. Use `browser-start` and `browser-stop`
to manage that proxy separately. The known sample venues use checked-in local geocoding
overrides; set `GEOAPIFY_API_KEY` before `up` to resolve any other addresses.
`sync` temporarily runs a localhost-only CONNECT bridge
restricted to the sandbox PDS, so publication does not require host DNS or CA
installation. Re-running it preserves record URIs through the private identity maps and
verifies every PDS write by CID and payload readback.

The canonical private HTTPS endpoints remain available for protocol-level testing.
Run `hosts`, trust only the printed public CA, and use `access-start` when that behavior
is specifically needed. Port 443 must be free for both canonical HTTPS access and the
loopback HTTP proxy.

The harness never deploys remotely. `down` preserves every identity and database.

## Globe browse and search

The homepage uses two deliberately different read paths:

- Browsing requests `/map/events/{z}/{x}/{y}.mvt` with catalog and date filters.
  The AppView supplies display points and clusters; MapLibre does not cluster events.
- Text search requests `app.openmusicevent.calendar.browseEventSummaries` in pages
  of 50. Search is global unless **Search this area** captures a viewport. Panning
  does not change search results. `getSearchMapItems` clusters only those page URIs
  and returns their exact cluster membership, never the entire search match set.

Both catalogs start selected. Current/upcoming is the default date filter;
**All dates** includes historical and undated records. Ongoing events with richer
EventViewer data lead the list, followed by future events, other ongoing events,
then historical and undated records when enabled. Cursors freeze the evaluation
clock and use the event URI as the ordering tiebreaker. They are live keyset cursors,
not a frozen snapshot of records edited during pagination.

Cluster selection opens a paginated member list and zooms toward the next split.
Identical-coordinate events remain accessible at maximum zoom. Selected rows expand
inline via `getEvent`; **Enter Event** still derives from additional canonical data.
`getEvents` and `browseEvents` remain compatible. The prototype `getMapItems`
all-candidate endpoint has been removed. No authoring-record lexicon fields were added.

### Spatial projection and operating bounds

The original StructuredQueries browse/FTS tables and exact-coordinate SQLite R*Tree
remain. The additional derived tables store normalized Mercator points and sparse
quadtree cells at depths 3–21 (eight cells per tile edge). A record mutation updates
its point, 19 ancestor cells, and affected tile revisions in the same transaction.
The server reads a bounded cell neighborhood rather than decoding every candidate.
Coordinates beyond Web Mercator's ±85.051129° remain searchable but are not plotted.

Tiles use MVT 2.1, gzip, representation-specific ETags, and ten-second HTTP freshness.
The process cache is limited to 32 MiB / 2,048 entries, coalesces identical misses,
and permits at most eight distinct cold builds (excess work gets retryable 503).
Revisions are scoped to the requested tile and its buffered neighbors. An expiration
worker runs every five seconds; the visible browser refreshes tiles every ten seconds.
These intervals target ≤30-second freshness under normal load, not an overload SLA.

Rebuilds page through source-derived browse rows into a separate generation while
ingestion dual-writes the active/building generations. Row-count validation and the
generation switch are transactional. Progress is persisted after each batch; restart
resumes a partial build. Old generation points, cells, and tile-revision metadata
are reclaimed in bounded batches using a durable retirement cursor.
Startup completes any initial/unfinished rebuild before the listener becomes available.

MapLibre 5.7.1 and its license are bundled locally, with precompressed immutable
assets. Cluster labels explicitly use the base map's Noto Sans font: its glyph server
does not supply MapLibre's default Open Sans font, which previously prevented cluster
tiles from loading. The custom rim now owns a vertex array instead of altering the
renderer’s current vertex array. Event layers initialize at `style.load`, allowing
event tiles to load in parallel with basemap tiles instead of waiting for map `load`.

### Verification and performance measurements

Run the AppView tests through the compiler lane using the local AppView dependency
configuration:

```sh
OME_APPVIEW=1 OME_COMPOSABLE_ATMOSPHERE_PATH=/path/to/swift-composable-atmosphere \
  ~/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh \
  --wait --priority normal exec swift test --filter OpenMusicEventAppViewServerTests
```

`browser-check.cjs` exercises real AppView responses in desktop Chrome and a Pixel 7
Chrome emulation: visible map items, default selections, global search, zoom without
re-querying the list, cluster click/zoom/member lists, paging, inline hydration,
keyboard movement, Jump to now, area search, stale-response rejection, and empty state.
It writes screenshots and JSON results under `.build/globe-map-validation`.
It also holds basemap raster requests open and verifies markers render independently.
Set `PLAYWRIGHT_MODULE` if Playwright is not installed in the default Node module path;
set `OME_GLOBE_URL` to test a different local listener.

```sh
OME_GLOBE_URL=http://127.0.0.1:18081 node Scripts/globe-local/browser-check.cjs
OME_GLOBE_URL=http://127.0.0.1:18081 node Scripts/globe-local/http-check.cjs
```

`http-check.cjs` verifies both catalogs, invalid-request status codes, the retired
all-candidate endpoint, compressed tiles and ETag revalidation, and records twenty
HTTP samples for list/search/tile requests. These are not browser timings.

`window.OME_GLOBE_METRICS` reports tile counts, compressed bytes, server timings,
transfer durations, render readiness, and first visible markers since navigation.
Worker resource timings are collected through MapLibre; unavailable sizes/timings
are not presented as measured zero. The first-frame metric rejects points on the
far side of the globe. This is separate from total basemap/network idle time.

The opt-in `CalendarMapCapacityTests` accepts `OME_GLOBE_BENCHMARK_COUNT` up to
10,000,000. It creates a separate temporary SQLite database, measures projection and
rebuild duration, database size, global tile query time/size, and 50-row list time,
then retains a `results.json` alongside that database. Its distribution is 75% repeated
venues and 25% deterministic global coordinates. It does not measure ATProto ingestion,
arbitrary high-cardinality distributions, or browser/device performance.

```sh
OME_GLOBE_BENCHMARK_COUNT=1000000 OME_APPVIEW=1 \
  OME_COMPOSABLE_ATMOSPHERE_PATH=/path/to/swift-composable-atmosphere \
  ~/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh \
  --wait --priority background exec swift test --filter CalendarMapCapacityTests
```

Do not treat mobile emulation as physical-device proof or a synthetic database test
as a browser benchmark. H3, semantic place identity, vector-tile hosting infrastructure,
and alternative databases remain deferred pending actual workload measurements.

### Local migration evidence (2026-10-11)

The existing `ome-globe-ome-globe-appview-1` service was updated without recreating
its PDS/accounts or database volume. The pre-migration SQLite backup is retained in
`.build/globe-map-validation/appview.sqlite`; the independently migrated validation
copy is `appview-snapshot.sqlite` in the same directory.

The live migrated database passed `PRAGMA quick_check` and retained 87,728 browse
records: 87,620 Community Calendar and 108 OME. Its map projection contains 65,866
located records: 65,758 Community Calendar and 108 OME. Source records were not
rewritten by the migration. These counts supersede the earlier 20,019/5,102 estimate.

Validation artifacts are local and intentionally untracked. Browser results include
desktop Chrome and Pixel 7 emulation; physical mobile hardware and ten-million-event
capacity have not been verified. No remote deployment was performed.

The one-million-event synthetic test passed in a macOS debug build, with 75% repeated
venues and 25% deterministic global coordinates. All fixture dates were the same future
date; this is not a representative temporal distribution. Twenty query samples produced:

| Measurement | Result |
| --- | --- |
| Uncached global tile database work | 26.72 ms median; 31.87 ms p95; 61.58 ms max |
| 50-row list query | 129.96 ms median; 136.17 ms p95; 1,690.47 ms max (first sample) |
| Global tile | 64 features; 1,184 gzip bytes |
| Sparse cell rows | 3,180,254 |
| Synthetic database | 2,980,233,216 bytes |
| Initial scalar fixture population | 14.11 seconds |
| Full derived map rebuild | 1,781.87 seconds (29.70 minutes) |

These results establish bounded tile delivery, not cheap rebuilds or uniformly fast
cold list queries. Rebuild duration, write amplification, storage growth, and the cold
list outlier remain important capacity limits before a larger rollout. The retained
report is `results.json` in the `ome-map-capacity-72DDD906-4813-40EF-A411-B53E175E68C9`
temporary directory printed by the benchmark. No ten-million-event result is claimed.

Final acceptance against the release Linux container through `127.0.0.1:18081`, after
the capacity workload had finished:

| Measurement | Result |
| --- | --- |
| First visible markers, desktop Chrome | 920.7 ms from navigation |
| First visible markers, Pixel 7 emulation | 591.7 ms from navigation |
| List HTTP, 20 samples | 10.81 ms median; 11.55 ms p95 |
| Search HTTP, 20 samples | 42.99 ms median; 49.80 ms p95 |
| Warm global tile HTTP, 20 samples | 5.37 ms median; 10.40 ms p95 |
| Global current tile | 13 features; 661 gzip bytes |

Browser figures are single fresh-context headless Chrome runs on the development
Mac, without network/CPU throttling, not device percentiles or an SLA. The earlier
sequential basemap initialization took 1.6–2.7 seconds through this proxy. The final
test also proved markers render with all 16 initial basemap raster requests held
open. API measurements ran after the browser tests and include the loopback HTTPS
proxy, with warm server caches. Raw reports and screenshots are under
`.build/globe-map-validation/local-sandbox/`.

Both the macOS AppView build and Linux release build passed. The final focused command
`swift test --filter OpenMusicEventAppViewServerTests`, run with `OME_APPVIEW=1` and the
compiler-lane command above, passed 122 tests in 18 suites. The opt-in million-event
test passed separately; it is disabled in the normal suite. Final smoke checks confirmed
both catalogs, inline details, cluster member lists, paging, Jump to now, stale-request
handling, invalid-request HTTP 400 responses, and tile ETag HTTP 304 responses.

## Community Calendar publisher lens

The Sources picker scopes Community Calendar by the publishing repository, not by
event category or organizer. Both catalogs remain enabled; the initial Community
Calendar selection excludes `did:plc:k6owgpe2rkkchoiivxhzp2t4` (Laugh Town). The
`OME_CALENDAR_EXCLUDED_PUBLISHERS` environment setting accepts a JSON array of DIDs;
`[]` makes the default include all publishers. This is display policy, not an
ingestion restriction. Existing explicit visitor selections override the default.

`getPublishers` returns paginated publisher identities and the default lens.
`browseEventSummaries` and map tile URLs accept `publisherMode=allExcept|only` and
repeated positive-integer `publishers` parameters (up to 1024). Publisher IDs are
local to this AppView database, persist through rebuilds, and are never reused.
The homepage stores the lens locally and shares it in its URL; incoming links do
not overwrite saved preferences. The `getEvents` compatibility route is unchanged.

The migration preserves source records and stages a new map generation. Existing
catalog summaries are retained; publisher summaries are incrementally maintained
in the same SQLite transactions. Exclusion subtracts publisher summaries, while
only-selected sums those summaries. Tile cache keys and list cursor fingerprints
include the normalized lens. No per-visitor cluster index is created.

Focused checks:

```sh
OME_APPVIEW=1 OME_COMPOSABLE_ATMOSPHERE_PATH=/path/to/compatible/atmosphere \
  ~/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh \
  --wait --priority normal swift-test --filter OpenMusicEventAppViewServerTests
PLAYWRIGHT_MODULE=/path/to/playwright node Scripts/globe-local/publisher-browser-check.cjs
```

The browser source-picker stories use intercepted fixture responses, not a live
AppView. Set `OME_PUBLISHER_SNAPSHOT` to an existing database snapshot to enable
the migration/performance test. It uses SQLite backup into a new temporary
database, leaves the input untouched, prints filtered tile measurements, and
retains the isolated database for further smoke testing.

Publisher-lens validation on 2026-10-11: 127 AppView tests in 19 suites passed;
Linux release image compilation and fixture-backed browser source-selection stories
passed. The isolated migration retained 87,728 browse rows and passed SQLite
`quick_check`; initial backfill/retirement took 284.59 seconds. Ten uncached debug
global-tile samples measured median/max 20.06/26.58 ms for the default exclusion,
4.15/7.02 ms for Laugh Town only, and 25.41/27.16 ms for 212 selected publishers.
Corresponding gzip payloads were 639, 193, and 492 bytes. These are database
measurements, not end-to-end browser latency.

The existing globe-rim failure at zoom 12 was fixed by checking the projection
transition before compiling the globe-only shader. The browser check now crosses
to zoom 12 and back to the globe and asserts no shader errors.

The local sandbox at `http://127.0.0.1:18081/` was updated after a consistent SQLite
backup to `.build/globe-map-validation/pre-publisher-live-P0xkUW/appview.sqlite`.
The live migration preserved all 87,620 Community Calendar and 108 OME browse
records; `quick_check` passed and generation 2 completed with no pending rebuild
or retirement. Only the AppView container was recreated; no remote deployment.

Live desktop and Pixel 7 Chrome-emulated browser stories passed with no page
errors or failed event tiles. First visible markers measured 912.7 ms and 717.3 ms
respectively; this is local-loopback evidence, not physical-mobile or production
latency proof. Markers also rendered with basemap requests deliberately blocked.
Real source-checkbox inclusion/reset and Laugh Town-only API filtering passed.
Reports and screenshots are in `.build/globe-map-validation/publisher-live/`.
