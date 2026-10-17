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

Existing release smoke checks fetch HTML, scripts, styles, and one catalog page;
they never request map tiles concurrently. This reproduction is not yet wired
into CI. No production Swift code, workflow, deployment, or live service was
changed. No compiler or Swift unit-test suite was run: this is runtime evidence
from the verified release executable.
