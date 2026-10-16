# iOS Lexicon adoption — Phase 1

Current canonical record UI/form coverage is tracked in [CanonicalRecordFormCoverage.md](CanonicalRecordFormCoverage.md). The September 30 checkpoint below is historical and predates the app-side replacement.

## Contract

The new models in openmusic-event-record replace the retired domain models throughout the app, local storage, source editing, AppView and publication. No dual-write period, legacy type aliases, or runtime old-to-new model bridge. One bounded Wicked Woods conversion may read the old format. Android compilation and runtime verification are Phase 2.

Source snapshots: OME deployment integration 36ab16d5; record workspace 7318cfda; shared auth/restructure 11f6635d; Lexicon authoring 9a5c347e. The original record workspace remains untouched. Intended local destination: workspace:default. Lifecycle: isolated.

## Implementation checkpoint — September 30

The split ATProto package now owns the authoring macros, complete schema DTOs, record identity decoding and exporter. SQLite integration remains in ATProtoSQLite. OME imports the canonical Event, Stage, EventPlace, Program, Schedule, ProgramItem, Contributor and Social.Post records and their value models. OME_LEXICON=1 selects the small model/export/test graph.

This is an incremental integration checkpoint. Existing app consumers and legacy declarations remain until the next replacement slices; the acceptance contract above is not yet satisfied. No new legacy adapter was introduced. The source workspace's Event.init(id:event:) runtime adapter and its adapter-specific test were deliberately not imported; a one-time source conversion needs its own coverage. The contributor-link test now exercises the canonical Contributor instead of the retired draft.

Validation so far:
- Protocol/authoring: 206 tests in 34 suites passed, exit 0 (deduplicated).
- ATProtoSQLite: 10 tests in 3 suites passed, exit 0.
- OME model graph with the approved public extensions: 106 tests in 17 suites passed, exit 0.
- ome-export-lexicons --output Lexicons/Generated --check: exit 0, no schema drift.
- Full native consumer regression before the public-model additions: 1,060 tests in 105 suites passed, exit 0. Final iOS regression is running; private-PDS publication and field CRUD are still unverified.

The model graph uses a separate compiler cache because the initial reuse of full-app SwiftSyntax objects failed at macro linking. A clean cache compiled and tested the models. Validation-only Package.resolved narrowing was restored before the full app run.

Tangled's existing package-restructure workspace has a child change for canonical JSON accessors (source/base 521fad19, destination unset). Its source workspace is /Users/woody/Developer/ometools/worktrees/composable-atmosphere-tangled-reorg. The original record and authoring workspaces remain untouched.

## Approved public-model extensions

Woody chose to extend the public models before replacing the affected UI. This is a separate child change above the validated integration checkpoint.

- Social.Category (social.ome.category) belongs to one event repository, with name, description, media, default subscription state and required-subscription policy. Attendee choices remain per-account state.
- Event.categories is the complete ordered category list. URI validation rejects duplicate, wrong-collection and foreign-repository references; graph validation verifies category membership.
- Social.Post.delivery preserves silent, standard and emergency intent as an open string. Emergency intent requires event-organizer authorship. Publication/ingestion must call semantic validation; decoding alone does not authorize notification delivery.
- Event.siteMap embeds the map title, ordered styles with stable local IDs, images and optional defaultStyleID. Renaming/reordering preserves selection; deleting the default requires choosing another or clearing it. No separate map record is needed for this event-owned lifecycle.

The field inventory now has 155 rows. New tests cover category persistence and CRUD, contradictory subscription policy, ownership/reference failures, map selection and unknown-value preservation. UI wiring remains pending. Existing contributor presentation policies, post pinning/manual ordering and the full rich-text/embed contract still need decisions or further modeling before their legacy consumers can be removed.

These choices use record references for independently owned categories and embedded objects for event-owned map values, consistent with the [ATProto Lexicon type model](https://atproto.com/specs/lexicon). They are OME design choices, not protocol-mandated record boundaries.

## Field inventory

LexiconFieldCoverage.csv inventories each property in the checked generated schema definitions, plus record identity/CID metadata. It is a checklist, not a claim of working UI. Existing UI candidates still use legacy models. External referenced schemas (rich-text facets and embed variants) require a separate consumer audit; this inventory is not full transitive CRUD proof.

Each user-authored field requires a discoverable form control, creation/update, optional clearing, save/reopen and publication readback proof. Array rows require visible Edit and Remove/Delete menus and ordering controls when order is meaningful. No ordinary editing operation may require Technical Details, CLI or raw source changes. Operation-managed fields require an identified owning action and observable outcome instead of an arbitrary text field. Preserve unknown union data during unrelated edits.

## Confirmed gaps from source inspection

| Surface | Evidence | Required migration work |
| --- | --- | --- |
| Event form | EditEventInfo uses OMERecord.Event.Draft | Bind to the new Event; preserve optional dates and event-local time semantics |
| Event places | EditStage conflates event placement and Stage identity | Edit EventPlace independently; persistent Stage linkage is optional |
| Ordering | EditStageLoadedForm hides sortIndex under showsTechnicalDetails | Use ordinary reordering for Program.eventPlaces; remove legacy sort-index authority |
| Program | No new Program editor | Create/edit title, description, icon and ordered places without adding a new top-level navigation destination |
| Program items | EditPerformance requires stage and complete start/end | Support optional time/place and ordered credits; review sparse-item presentation before implementation |
| Contributor links | EditableContributorLinkSection only edits URL and platform and removes rows | Cover title, description, role payload, optional clearing and order using visible row menus |
| Media | Existing picker edits legacy local image wrappers | Cover all new media/source/role variants; keep caching metadata separate from public payload |
| Posts | Social.Category now defines the previously missing category record | Replace the legacy channel/post consumers and validate delivery authorization at publication/ingestion |
| Publication | Record workspace has Event publication/readback only | Extend to the complete approved graph and prove zero writes to retired collections |

Source evidence: Sources/OpenMusicEventAppEventViewer/EditEventInfo.swift; StagesViewer.swift (EditStageLoadedForm); Schedule/EditPerformance.swift; Contributors/ContributorsViewer.swift (EditableContributorLinkSection); ImageAssetPicker.swift. New contracts live in the record workspace's Sources/OpenMusicEventLexicon and Sources/OpenMusicEventLexiconExport/main.swift.

## Wicked Woods coverage still to resolve

The 2026 source contains 198 contributor files, six stage files, four schedule files, five channels, 16 communication files and one map file, plus event metadata. These are file counts, not decoded entity counts. Audit contents and referenced assets before claiming data preservation.

- Emergency phone numbers and incident-reporting links need correct semantic link roles and equivalent UI actions.
- Map image and geographic map features are distinct; retaining an image does not prove map-feature preservation.
- Channels/categories, notification subscriptions and post authority need explicit mappings to the new model set.
- Branding, source provenance and asset materialization remain separate from public record payloads.
- Preserve attendee state through the one-time identity mapping; do not build a general legacy-version framework.

## Concrete 2026 source mapping

Paths below are relative to /Users/woody/Developer/ometools/org-source/wicked-woods/wicked-woods-ome. These classifications establish representability from source inspection; they do not prove a converter or UI path.

| Source path / field | New owner | Classification and remaining work |
| --- | --- | --- |
| events/2026/event.yml: name, startDate, endDate, timeZone | Event.name, start/end day variants, timeZone | Representable; retain date-only precision and event-local time zone |
| event.yml: status=planned, mode | Event.status/mode | Representable; normalize the legacy short status to its defined identifier |
| event.yml: locations.address, coordinates, directions | Event.locations: name, address/geo locators, description | Partial; source address is unstructured, so retain the exact text and do not guess structured address components |
| event.yml: contactNumbers | Event.links with contact role | Representable; preserve title/description and explicitly classify the on-site emergency number |
| event.yml: reportingLinks | Event.links with reporting role | Representable; do not classify the REES incident form as emergency dispatch merely because it is safety-related |
| event.yml and stages/*.yml: images.source, role, focalPoint | Media.image and Image role/source/focalPoint | Representable; URL/blob readiness and image publication need independent proof |
| images: renderKind=fullImage/transparent | Image.renderingMode plus image content | Partial; transparency does not imply template tinting. Preserve original colors unless the source explicitly intends a template |
| images: assetKey, materializationPolicy | Local asset/cache bookkeeping | Intentionally outside the public payload; preserve offline behavior without legacy ImageAsset as domain authority |
| stages/the-hallow.yml: name, color, images | EventPlace common fields and kind.stage.color | Representable; creating a persistent Stage is optional, not an automatic conversion requirement |
| stages/relaxation-ridge.yml: category=workshop, sortIndex | Program membership and ordered eventPlaces | Partial; define the program grouping and ordering from source, then expose ordinary reorder controls |
| schedules/friday.yml: date, scheduleItems by place | Schedule plus ProgramItem records | Representable; convert local clock times with the selected festival day and time zone, retaining cross-midnight behavior |
| scheduleItems: contributors[].id/role | Ordered ProgramItem.credits and event Contributor records | Representable; resolve source identities once and preserve explicit per-occurrence roles |
| contributors/N2N.md: frontmatter name/images/links and body | Contributor name/media/links/description | Partial; this file contains placeholder URL values of “-”. Report and omit invalid placeholders during the bounded conversion, not as a runtime fallback |
| maps/main.yml: title, styles[].title/image | Ordered site-map images with titles | Partial; images/titles are representable, but defaultStyleID and stable style identifiers have no equivalent in the checked records |
| channels/*.yml and communications/*/channel-info.yaml | Post category and notification policy | Blocker; category has no exported record model. Required/default subscriptions, icon and category order need an explicit owner; do not drop them |
| communications/safety-info/no-additional-parking-passes-available.md: title, timestamp, body | Social.Post.title/createdAt/text | Representable as content; source Markdown versus facets requires composer/rendering decisions |
| communication frontmatter: delivery=emergency | Notification/delivery policy | Blocker; it is not a Social.Post field and must retain an explicit delivery owner |
| Existing Event.Policies and categoryConfigs | Product presentation/profile policy | Blocker for full consumer removal; the checked public Event has no policy fields. Do not silently remove existing controls |

The post facet and embed wrappers currently preserve raw JSON objects and external references; they do not establish complete field-level validation for the referenced Bluesky schemas. Rich-text byte offsets are composer-managed values, and embedded payloads need the relevant editor and schema tests. “Post roundtrip passed” must not be presented as full rich-text/embed CRUD proof.

Private sandbox image fixtures must be served inside the sandbox. Successfully loading Wicked Woods images from production resource hosts would not prove the requested self-contained end-to-end setup.

## Decisions presented before UI implementation

- Recommended: show untimed/unplaced items in an Unscheduled section within the existing program screen. User response pending.
- Recommended: explicit app Publish uses the organizer's session to write approved records; AppView indexes readback. User response pending.
- Approved: extend public category, notification and map models before replacing those UI features. Do not remove still-unmapped controls.

## Execution and acceptance

1. Port authoring/macros/schema tests into ATProtoTypes and database integration into ATProtoSQLite, without a database dependency in the protocol core.
2. Integrate the record workspace after the shared foundation compiles; update EventModel.xcworkspace and its model test scheme.
3. Complete the field and source coverage audit, resolve the identified UI/model decisions, then replace storage and consumers in reviewable slices.
4. Replace fixture models, queries, navigation identifiers and authoring drafts. Remove retired model definitions and runtime adapters once consumers use new models.
5. Implement complete publication, stable identities, explicit source revision/draft selection, retry/readback and AppView ingestion.
6. Prove rich Wicked Woods, minimal Event, progressively enriched Event, absent time/place/credits/media, cross-midnight and partial-cache cases on iOS.
7. Private sandbox gates: account creation/login/logout/relaunch and refresh, UI CRUD for every authored field, save/cancel, delete/reference integrity, publication and a fresh reader observing the result. Block retired collection writes.
8. Run native/model/server and iOS suites and inspect UI/screenshot changes. CI must exercise real private PDS/AppView, DNS and HTTPS trust without production OME dependencies. Current server-only CI does not yet constitute this gate.
