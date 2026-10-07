# Attendee performance measurements

Fastlane's `run_maestro` retains `performance.json`, app timing logs, and Maestro
artifacts for each flow. There are no latency thresholds. Functional assertions
still fail normally. Reports are retained on Maestro failures too.

App markers require an iOS Debug app built with `OME_UI_AUTOMATION=YES`.
They use monotonic uptime, independently of the attendee fixture's frozen date.
Normal/release builds do not emit markers. Android currently records only runner
metrics; missing app measurements are reported as unavailable, not zero.

For a live installed event, open its viewer first, then run:

```sh
python3 Scripts/ui-performance.py --device "$SIMULATOR_ID" \
  --output /tmp/ome-warm-entry-run \
  .maestro/15-installed-event-performance.yaml \
  -e EVENT_RKEY=3mx6isyz5jy22 \
  -e EVENT_URI=at://did:plc:a2ln7umogxgflsobz2unqfeu/events.openmusic.event/3mx6isyz5jy22
```

Choose a new output directory each time. This repeats exit/reentry three times
without resetting the database. Use the publication automation profile for the
local AppView; the attendee profile uses Testival fixtures.

`entries` separates action-to-schedule-onAppear from install, graph read,
relationship validation, and search-load spans. Nested spans overlap and must not
be summed. `onAppear` is a lifecycle milestone, not a first-frame measurement.
`automation_commands` includes runner synchronization/animation overhead and must
not be presented as pure app latency. Preserve the device, build configuration,
source revisions, and dataset alongside reports when comparing runs.

Transport markers record only paths (no queries, headers, or bodies). They cover
the automation HTTP transport, not every image-loading transport. Bundle markers
also directly observe `EventRecordClient.appView`. A cached detail can still
refresh when the advertised event CID differs; Enter skips downloading when the
Event record exists, but currently rereads the entire local graph.

Validate the report parser with `python3 Scripts/test-ui-performance.py`.

## Initial installed-event investigation (2026-10-07)

iOS 26.4 iPhone Air simulator, Debug publication profile, Wicked Woods 2026
already installed. OME base `3c064207`, ATProto dependency `d93f1cf9` (schema
cache and direct JSON tree codec). Three repeated entries in one app process:

| Measurement (milliseconds) | Run 1 | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| Enter action to schedule onAppear | 2603 | 2496 | 2439 |
| Both graph reads combined | 1391 | 1309 | 1288 |
| Both relationship validations combined | 4.0 | 3.4 | 3.3 |
| Search dashboard initial load | 796 | 785 | 781 |
| Maestro tap through schedule assertion | 6278 | 5694 | 6066 |
| Bundle requests | 0 | 0 | 0 |
| Observed automation-transport HTTP requests | 0 | 0 | 0 |

The Enter action in `OpenMusicEventBrowser` calls `EventRecordClient.install`,
then posts `NavigationRequested`. `OpenMusicEventAppRoot.openRoute` calls
`install` again. Each cache hit still fetches the full `EventRecordGraph` inside
its write transaction. The graph read, not `validateRelationships`, dominates
these calls. This is not a new import or a download.

`EventDetail.State` eagerly creates `EventSearch`, whose initial query handler
synchronously reads `EventSearchDashboard` on the main thread. That dashboard
loads all performance rows before filtering in Swift, even while entering the
schedule. The runtime log shows this load on the same thread as Enter and
schedule appearance, before appearance in every run.

The two graph reads plus search load account for roughly 84–85% of the measured
app interval. The remaining interval includes navigation, feature construction,
query setup and view lifecycle work; it has not been individually attributed.
The difference from Maestro includes automation synchronization and presentation;
it is not all app execution. These measurements diagnose existing behavior;
no entry optimization is included in this instrumentation change.

Raw local evidence: `/private/tmp/ome-entry-metrics-warm-2/performance.json` and
`app-performance.log` in the same directory. The iOS build passed, report-parser
unit tests passed, and all three warm-entry UI iterations passed. Android was
not verified (temporary gate). No production latency target is established.
