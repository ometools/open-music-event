# Globe tile responsiveness regression

On 2026-10-17 the deployed, unchanged AppView executable reproduced the staging
stall in three separate native Linux processes, each with a fresh empty database.
All three failed on the first burst of 16 concurrent cold tile requests.

## Exact runtime and isolation

- Source revision: `1b5dbf9e6f07522aa018595401a20c470bdbd798`.
- Release artifact: `60abe24a99c9feae91c55946661b1d55cbb03f876fa56758efb05453b4eb7232`.
- Executable SHA-256: `8671ac8ae630c1318c443a0116ce27d4999fe4dfaf18445700220eed285594ab`.
- Ubuntu 24.04, native x86-64, two online CPUs, service account `ubuntu`.
- Each run used private mount, PID, and network namespaces, with loopback enabled
  only inside that namespace. No public port, ingestion, or credentials were used.
- The executable created and migrated its own empty database. No staging data
  was copied or edited. The installed AppView process remained PID 946367 with
  zero restarts.

The subprocess harness is
[`reproduce-globe-stall.py`](../Scripts/web-release/reproduce-globe-stall.py).
Inside an isolated Linux environment with two **online** CPUs, run:

```sh
python3 Scripts/web-release/reproduce-globe-stall.py \
  --executable /path/to/verified-release/run \
  --revision 1b5dbf9e6f07522aa018595401a20c470bdbd798 \
  --output /path/to/new-disposable-report-directory
```

The harness requires a new output directory. It clears application configuration,
uses a fresh database, starts its own loopback server, and terminates only that
child process. It returns nonzero when responsiveness fails and retains JSON
evidence plus a server log. An external three-minute deadline and namespace
teardown bounded each native run.

## Observed story

1. Readiness, `/healthz`, `/`, and one tile returned HTTP 200. The first tile took
   about six milliseconds.
2. A barrier released 16 HTTP clients requesting distinct `/map/events/6/x/y.mvt`
   tiles. Both OME and Community Calendar catalogs were selected, with all dates.
3. Some tiles completed; the remaining requests exceeded five seconds.
4. A subsequent `/healthz` request also exceeded five seconds while the same
   server process remained alive.
5. Read-only stack-address samples found two workers waiting in GRDB's reader
   pool, reached from `mapTile` at `CalendarMapTiles.swift:126` and the detached
   tile task at line 102. These are symbolized executable-address candidates,
   not full debugger unwinds. They match the separately observed staging stall.
6. The diagnostic child did not terminate within five seconds of SIGTERM; the
   harness killed that disposable process and retained its report.

The owning source path, reduced from the unchanged implementation, is:

```swift
// CalendarMapTileCache.tile(_:store:), line 102
let task = Task.detached { try store.mapTile(request, generation: key.generation) }

// OpenMusicEventAppViewStore.mapTile(_:generation:), line 126
let features = try database.read { db in
    // Tile queries omitted.
}
```

This is an explanatory reduction. The executed reproducer used the complete
release binary and real HTTP routes, not replacement implementations or mocks.

## Limits and CI implications

An initial local Docker control completed 320 empty-database tile requests.
Although its CPU affinity was limited to two CPUs, it still reported ten online
CPUs and created more worker threads. That passing run does not cover the native
two-CPU failure. Record both `onlineCPUs` and `affinityCPUs`; affinity alone is
insufficient evidence of the runtime condition.

The three native failures establish a repeatable runtime regression, not a
deterministic schedule across every platform. Their JSON reports are retained
locally in `.build/globe-stall-repro/native-evidence.json` and on the diagnostic
host under `/tmp/ome-globe-stall-repro-vkxx2pln/run-{1,2,3}/result.json`.

At the time of the initial reproduction, release smoke checks fetched HTML,
scripts, styles, and one catalog page; they never requested map tiles concurrently.
That reproduction changed no production Swift code, workflow, deployment, or
live service. Its three failures are runtime evidence from the verified release
executable, independent of the subsequent repair and compilation below.


## Repair isolation and request stress

The cache actor owns entries, LRU accounting, and at most eight pending builds.
Admission and task registration have no suspension between them. A shared task
publishes its result and releases its slot on the cache actor, including failure.
Waiters never remove pending tasks. Generation changes retry lookup for every
waiter. Cancellation is checked before lookup, after lookup, and after the
shared result. Cancelling one request does not cancel work another request needs;
the cancelled waiter discards the result after the bounded shared read completes.

Tile generation, compact browse, publishers, search-map lookup and event detail use explicit
`@concurrent` async store methods and GRDB async reads. SQL and connections remain
inside GRDB's read closure. Sendable values cross back; encoding and result
assembly execute outside the cache actor. No detached task wraps a blocking read.
This covers the globe browser's API calls, not a concurrency audit of every AppView endpoint.
The eight-build limit is separate from the HTTP server's connection admission.

The PR and release build script now runs the real HTTP regression with 32 clients,
16 rounds, and --stress. It tests cold tiles alongside health/readiness, homepage,
browse, publisher, search-map and event-detail traffic; gzip/ETag integrity, conditional revalidation,
503/Retry-After recovery, abandoned clients, and graceful child shutdown.
The phase has a 180-second outer timeout and retains JSON results and server logs.
Use --require-online-cpus 2 for the original runtime condition. Affinity alone
is not sufficient. --database-fixture copies a synthetic database read-only into
a fresh private run directory. Packaged runs require --revision; debug PR runs
omit that packaging-only check. The harness never accepts a remote target URL. Its outer-deadline handler kills
and reaps only its own server process group.

The original three failed runs above precede this repair and remain separate
from subsequent compilation, Swift tests, and request stress results.


The opt-in `OME_GLOBE_HTTP_FIXTURE_COUNT` Swift test creates synthetic raw records,
projects them through the canonical rebuild, and verifies normal store startup
preserves the expected browse count. This is distinct from the older scalar-only
capacity benchmark. The HTTP harness checks raw, canonical and browse counts
before startup, after startup and after requests, and requires populated tiles.
Stress coordinates spread across the world at the selected zoom; cache hits and
eviction are included when a longer run revisits coordinates.


The browser uses MapLibre's `addProtocol` for OME vector tiles only. Each tile
request owns its abort controller and ten-second deadline. Only HTTP 503 with an
integer `Retry-After` is retried, at most six attempts; panning cancellation aborts
the fetch or pending delay. Other HTTP errors retain their status. Successful
responses preserve bytes and cache metadata. No global fetch override is installed
in the application, and basemap requests retain MapLibre's loader.

`node --test Scripts/web-release/test-event-tiles.mjs` exercises the exact browser
module against real local HTTP responses, including bounded retries and cancellation.
It is a required tooling step in PR and staging workflows. The native stress harness
also accepts `--browser-tiles` (Node 20+) to import the module served by its own
application process and run 16/32/64 concurrent tile loads, then abandon 32 requests
while 32 survivors complete. These are real HTTP client tests, not WebGL rendering
or an ingestion load benchmark.

## Verified repair results — 2026-10-17

Tested source: `00671707332b3b9b6e7ec9bdb7ab54eb85eb2689`. All 1,002 tracked source files were hash-verified in the isolated test root. The final site resources also matched that snapshot byte for byte. Swift source was unchanged from the full server-test run; the final resource changes received focused tests.

Release archive SHA-256: `a8c5c2cf6740810b3ef747e37e3af6233fcfdf2ee6f6e662be49123c34ab9e86`. Executable SHA-256: `b7c0059446cd92d81861cc0df20bf7d981012c4ebb59c31a44a791a5bd10c4f5`. This package was built and tested privately; it was not published or deployed.

Runtime: native x86-64 Ubuntu 24.04, Swift 6.3.3, two online CPUs, private mount/PID/network namespaces, loopback only, cleared application environment, no ingestion or notification credentials. The populated fixture contained 10,000 synthetic events projected through normal canonical/store initialization.

| Tile clients | Events | Burst requests | Initial 503s, all recovered | Successful tile p95 | Worst health/readiness | Peak sampled RSS | Result |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 16 | 0 | 1,024 | 32 | 42 ms | 43 ms | 85.2 MiB | passed |
| 32 | 10,000 | 4,096 | 860 | 88 ms | 87 ms | 126.3 MiB | passed |
| 64 | 10,000 | 8,192 | 3,004 | 138 ms | 147 ms | 138.3 MiB | passed |

Successful-tile latency excludes immediate admission responses; it is not an end-to-end retry metric. The production JavaScript loader completed another 2,784 tile loads across its 16/32/64-client subtests, recovered from 928 wire-level 503 responses, and cancelled 96 abandoned requests. Across those runs, end-to-end p95 including retries was at most 1.291 seconds and the maximum was 2.255 seconds.

All three profiles preserved HTTP responsiveness, valid tile bytes/gzip/ETags, conditional 304 responses, mixed browse/publisher/search/detail traffic, and clean process exit (status 0). The three final profiles took 329.419 seconds combined. Post-run read-only SQLite checks returned `ok`; both populated copies retained exactly 10,000 raw, canonical, and browse records after the JavaScript load tests. The installed staging service remained PID 946367, active/running, with zero restarts. Its database was not used by these tests.

Verification commands and outcomes:

```sh
# Native toolchain, primary-owned compiler lane:
swift test --scratch-path .build/schema-tests --jobs 2 --force-resolved-versions --no-parallel --filter OpenMusicEventAppViewServerTests
# 161 tests in 26 suites passed.
swift test --scratch-path .build/schema-tests --jobs 2 --force-resolved-versions --no-parallel --filter "StaticSiteFilesTests|EventBrowsePageTests"
# 7 focused resource tests passed after the final browser changes.
swift build --scratch-path .build/schema-tests --jobs 2 --force-resolved-versions -c release --product OpenMusicEventAppView
# Optimized build passed.
node --test Scripts/web-release/test-event-tiles.mjs
# 9 real HTTP client tests passed on macOS and native Linux.
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Scripts/web-release -p "test_*.py" -q
# 57 tooling tests passed.
```

Each optimized profile ran the following command against its own fresh process and database (16 clients/64 rounds without a fixture; 32 and 64 clients/128 rounds with the fixture):

```sh
python3 Scripts/web-release/reproduce-globe-stall.py \
  --executable /output/release/appview/run \
  --revision 00671707332b3b9b6e7ec9bdb7ab54eb85eb2689 \
  --output /output/stress-64-populated --workers 64 --rounds 128 \
  --stress --browser-tiles --zoom 6 --require-online-cpus 2 \
  --database-fixture /output/synthetic-10000.sqlite
```

Additional regression evidence: the original 16-client/20-round pattern passed in three separate repaired native debug processes (960 burst requests total); the added CI profile passed another 512 burst requests. The unchanged deployed executable had failed in all three corresponding original native control runs.

Local raw reports, source verification, manifest, test logs, and aggregate `summary.json` are retained under `.build/globe-stall-repro/repair/evidence/`. These are server/request and browser-loader results, not a WebGL rendering test, production traffic capacity guarantee, or ingestion-load benchmark. The CI gate changes are local and have not yet run on GitHub. Local integration destination remains unset; lifecycle: **isolated**.

The custom loader follows the [pinned MapLibre 5.7.1 request/protocol contract](https://github.com/maplibre/maplibre-gl-js/blob/v5.7.1/src/util/ajax.ts).
