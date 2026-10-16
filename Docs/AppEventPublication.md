# App-originated Event publication

## Ownership

The app imports and edits canonical `Event` rows. Legacy `OME.Event` parsing stays
at the source-import boundary. Import provenance persists the publisher DID,
record key, and creation timestamp; reimport does not replace saved app edits.
Importing, local authoring, and network reading do not require an account.

`EventRecordPublishing` reviews saved workspace Events for the selected account.
`EventRecordPublication` freezes their validated, deterministically encoded
payloads and staged image bytes. After authorization, the feature checks account,
content, and image bytes again. A stale review never starts a write.

`EventRecordPublisher` uses shared XRPC requests, uploads images before writing
each referencing Event, and verifies URI, CID, and payload with PDS readback.
Upload metadata must match the reviewed content-addressed blob. Failures remain
visible, local edits survive, and retry uses the same Event URI and `createdAt`.
Verified receipts are persisted separately from authored content. This flow is
not Tangled source/proposal publication.

Browse uses the existing AppView APIs. Blob image URLs contain the publisher DID
and blob CID. A changed listing CID refreshes an anonymous reader's cached Event;
imported workspaces and concurrently edited rows are not overwritten.

## Private acceptance harness

Use dedicated test simulators/emulators, not ordinary installed app databases or
accounts. The `publication` UI automation profile selects the private service
environment but does **not** preload Events or replace the network publisher.
The bundled Testival shortcut only fills the source-import form.

- Prepare infrastructure with the existing auth-e2e harness. Reusing its private
  state requires `OME_AUTH_E2E_STATE_DIRECTORY`; never reset it to rerun publication.
- Add `Scripts/auth-e2e/publication.compose.yaml` to the private sandbox compose
  invocation. It connects Hydrant to the private PDS with signature/CID verification
  and the private CA. Use the Hydrant build that emits the caught-up marker expected
  by the existing AppView subscriber.
- When the AppView runs natively, add `publication-local-appview.compose.yaml`.
  It proxies the existing public API host to port 18080 and exposes Hydrant on 18300.
  This is a local test deployment, not a portable public deployment recipe.
- Build the app with `OME_UI_AUTOMATION_PROFILE=publication` through the compiler lane.
  The iOS test bundle is `app.openmusicevent`; Android is `fm.woody.openmusicevent`.
- Give the organizer photo library the fixture `maps/public-map.png` (A) and
  `maps/safety-map.png` (B), in that order. The photo-grid selection flows are
  specific to the dedicated iPhone Air/iOS 26.4 fixture library.
- Run `Scripts/auth-e2e/publication-ui.py --run RUN --phase PHASE` for `signup`,
  `import`, `edit`, `select-image-a`, and `publish`. These drive app UI only.
  `authorize` resumes at an OAuth password prompt if consent interrupts a run.
- Run `reader` with `--reader-platform ios|android --reader-device DEVICE`.
  It requires an independent, dedicated device, asserts signed-out state, and does
  not clear the database. Screenshots cover Testival and the minimal Event.
- For replacement, run `replace-image --description 'Testival updated from the app with image B'`,
  `select-image-b`, and `publish`, then rerun the reader with the same description.
  `image` and `replace-image-picker` are explicit recovery phases for an interrupted
  photo-picker flow; inspect the current screen before using them.

`verify-publication.py` performs **anonymous reads only**. Supply `--ca`, both
Event URIs (`--event-uri`, `--minimal-uri`), expected `--description`, `--image`,
`--alt`, and a new `--output` path. It checks exact PDS payloads, blob bytes/hash,
and AppView CID/payload convergence. For image B, supply `--previous` pointing to
image A's receipt report; Event URI/creation time must remain stable while record
and blob CIDs change. Verification reports do not claim device/UI success.

Auth automation logs are private and can contain typed credentials. Do not copy
them into handoffs; share the sanitized receipt JSON and screenshots instead.

## Evidence boundaries and remaining work

The 2026-10-05 local run is under `.build/auth-e2e/runs/20261005T170430Z`; sanitized
protocol evidence and compiler logs are under `.build/publication-e2e`.

| Layer | Observed result |
| --- | --- |
| App authoring | Imported two Events; saved description, image A/alt, then image B/alt through the organizer UI |
| Blob upload | Anonymous bytes and SHA-256 matched both original fixture PNGs |
| Record publication | Two Events verified; replacement kept URI and `2026-10-05T17:12:40Z` creation timestamp |
| Hydrant/AppView | Exact PDS record CID and payload matched the existing getEvent API for A and B |
| Signed-out iOS | Both reader flows passed, including dates/location/links/minimal Event; visually confirmed orange/red image B replaced green/purple image A without clearing the database |
| Signed-out Android | Not reached: shared-package dependency conflict before compilation |

Receipts: `.build/publication-e2e/image-a-receipts.json` and
`.build/publication-e2e/image-b-receipts.json`. Publisher:
`did:plc:a2ln7umogxgflsobz2unqfeu`. Event keys: Testival `3mx5fyp4fm7ld`,
minimal `3mx5fyp4fm73u`, collection `events.openmusic.event`.
The final Testival record CID is
`bafyreihnu5oti6uw5fqiaonyf5bjfib5cpc57r2sbbaf3dra6ezilkl64u`; image B is
`bafkreigqduggstby4idou37syxvutwlvqjqupu6pg5qnkzhwmqzdzlwzue`.
Reader screenshots are in the run's `publication-reader/20261005T173853507107Z`
directory. The reader remains on Testival's image B view.

Validation: `swift-test --build-system native --skip-update --disable-dependency-cache
--scratch-path /private/tmp/woody-swift-compiler-caches/open-music-event-app-publication-eb876f54ef07/swiftpm/fresh-build
--filter 'EventRecordPublicationTests|EventRecordPublishingTests|CanonicalEventEditingTests'`
through the compiler lane: **35 tests passed** (`publication-final-tests-3.log`).
The preceding combined run had one existing EventForm effect-teardown timing
failure; it passed unchanged on rerun. The final iOS simulator `xcodebuild` passed
(`ios-publication-final-build.log`). `python3 -m unittest discover -s Scripts/auth-e2e
-p 'test_*.py'`: **21 tests passed**; `ruby -c fastlane/Fastfile`: **Syntax OK**.

Failure-path Swift tests cover cancellation, stale content/account review, invalid
images, upload mismatch/failure, record failure after upload, and stable retries.
Those tests are not device-level fault-injection proof.

Android is blocked before compilation by the restructured `swift-atproto-sqlite`
manifest selecting standard GRDB while the Android graph selects SQLCipher.
That shared-package companion change is not included here. Android display and
replacement acceptance remain outstanding. The standalone native AppView and
local Hydrant build also remain host-specific test infrastructure.

Only Event records are imported by this new path. Schedules, contributors,
branded routes, web UI, public deployment, and image transformation/CDN work are
outside this change.
