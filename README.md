# OpenMusicEvent

OpenMusicEvent is a native iOS and Android app for music-event calendars.
It gives organizers and attendees a structured view of events, stages, schedules,
performances, contributors, locations, images, and event-specific details.

The app is built from one Swift codebase. The SwiftUI surface runs natively on
iOS and is translated to Android with Skip. Event data is modeled in Swift,
persisted locally, and can be imported from organizer-owned source repositories.

> [!WARNING]
> OpenMusicEvent is under active development. The app is already useful for
> modeling events, browsing schedules, validating source repositories, and
> experimenting with source-backed editing, but the source format and app
> workflows are still settling.

## Current Capabilities

- Browse calendars and event rows with event artwork.
- Open an event into dedicated views for info, schedules, stages, contributors,
  posters, location, communications, notifications, and settings.
- Edit event details, stages, calendars, policies, images, and source-backed
  proposals from inside the app.
- Import and validate OpenMusicEvent source repositories, including Tangled
  repository references.
- Authenticate with ATProto OAuth and use ATProto/Tangled infrastructure where
  it belongs: identity, source ownership, source download, and source publishing.

## Repo Layout

- `Sources/OpenMusicEventApp` contains the app root, routing, settings, source
  download flow, and shared app dependency setup.
- `Sources/OpenMusicEventAppEventViewer` contains the event viewer feature:
  event info, schedules, stages, contributors, editing flows, and source proposal
  UI.
- `Sources/OpenMusicEventLexicon` defines the core domain records:
  `Organizer`, `Calendar`, `Event`, `Stage`, `Schedule`, `Performance`,
  `Contributor`, posters, channels, images, policies, and supporting value types.
- `Sources/OpenMusicEventSource` parses and validates source repository files
  into the domain model.
- `Sources/OpenMusicEventDatabase` owns the local database layer, image storage,
  source provenance, and import insertion.
- `Sources/SourceEditing` contains database comparison and patch primitives.
- `Sources/OpenMusicEventSourceEditing` adapts those primitives to the generic
  `ComposableWorkspace` lifecycle and Tangled publication boundary.
- `Sources/OpenMusicEventAuthentication` wires ATProto OAuth into the app.
- `Sources/OpenMusicEventCLI` exposes the `ome` command-line tools.

Smaller modules such as `ScheduleComponents`, `OpenMusicEventImages`,
`OpenMusicEventTimeZones`, `SwiftUITabFeatures`, and `BlueskyActorCache` keep
shared UI and infrastructure code out of the main app target.

## Authoring and Workspace Contract

OME composes OAuth authorization, authoring policy, and one generic editable
workspace around the Event Viewer. OAuth owns the signed-in session and network
authorization. Authoring owns whether OME policy grants an editing capability.
Workspace owns availability and one coherent mounted editing session. The Event
Viewer owns editing, proposal-form progress, and presentation.

There is exactly one writable application database: `defaultDatabase`. While a
workspace is prepared, its `SourceWorkspaceResource` exposes that same writer as
`main` and a stable, read-only reference database separately. Only Workspace
descendants receive that coherent resource. They must never reopen the workspace,
install another writer, or reconstruct a comparison reference independently.

Browsing and authoring have a strict source-storage boundary. Browsing downloads
a temporary source artifact, imports only the selected event into the persistent
`defaultDatabase`, persists the event's organization source provenance, and then
deletes the artifact. The provenance comes from the OME event projection; it is
not an authoring resource manufactured by the browser. Browsing must not clone,
open, fetch, or persist a Git repository, and it must not create a reference
database. The current artifact happens to be a Tangled archive; a future AppView
artifact replaces that transport without changing the lifecycle.

Explicit authoring entry is the first Git boundary. After authentication and
authorization succeed, Workspace takes ownership of the organization source. On
first entry it clones the repository, resolves the exact checked-out Git commit,
installs the complete organization source into `defaultDatabase`, replaces only
rows owned by that exact source, builds the reference database from the same
commit, and opens it as the stable comparison reader. The selected event remains
viewer focus; it does not narrow or widen Workspace's organization-source ownership.

Durable re-entry is deliberately different from first entry. While authoring
state remains installed, a new application mount opens the existing repository
and validates that its checked-out commit, installed revision, selected branch,
reference revision and exact editing context agree. The durable core model is
availability plus a ready session containing the resource and one
`WorkspaceEditingContext`: exact Published revision, unassociated branch revision,
or exact proposal record URI and mounted proposal revision. Refreshing and
selecting are tasks, not additional states; failure preserves the prior coherent
session.

Publication freezes the current database difference and formats a Git patch from
a temporary local commit. OME uploads any required blobs and creates the Tangled
proposal record directly; it does not create or push a proposal branch. Successful
PDS record creation is the publication commit point. Before that point, failure
stays in the proposal form and local editing remains available. After that point,
OME dismisses the form and opens Proposals even if the AppView projection has not
caught up.

At the commit point OME atomically saves a proposal receipt and reference-repair
journal. Installing the proposal snapshot updates the writable installation
revision, selected revision, and exact context together. If installation cannot
finish, the existing session remains usable and preparation retries the journal;
the published record never becomes a global "publication stopped" state. Receipts
render pending proposals until the server-owned projection observes the exact
record URI, then they are acknowledged independently of repair completion.

Losing an authoring grant cancels in-flight work but does not invalidate an
already coherent ready session. After an application remount, Workspace
reconstructs the resource through the durable validation path above.
Proposal review diffs independently load the review's target repository and
branch and its source repository and branch. They never substitute the selected
workspace branch or its already-advanced reference database for either side.

## Running

Open the workspace:

```sh
open /Users/woody/Developer/ometools/new/open-music-event/Project.xcworkspace
```

Run the `OpenMusicEvent App` target from Xcode.

For Android, have Android Studio installed and an emulator or device running.
The Skip build phases translate and deploy the Android app from the shared Swift
sources. iOS logs appear in Xcode; Android logs are available in Android Studio
or with `adb logcat`.

## CLI and Source Validation

The package builds an `ome` executable for source repository workflows:

```sh
swift run ome source validate <source> --organizer-id <did> --verbose
```

`<source>` can be a local OpenMusicEvent source repository root or a supported
Tangled repository reference. The validator parses the source tree, checks its
event files, imports valid records into the default local database, and prints a
summary.

## Testing

Run the package test suite with:

```sh
swift test
```

For narrower compile checks while working on a module, build a specific target:

```sh
swift build --target OpenMusicEventSource
swift build --target OpenMusicEventAppEventViewer
swift build --target SwiftUITabFeaturesTests
```

Skip parity checks can be run with:

```sh
skip test
```

## Development Notes

The app favors direct Swift domain modeling, small feature modules, and explicit
dependencies. Point-Free libraries are used where they carry their weight:
ComposableArchitecture2 for feature state and actions, Dependencies for
environment control, Sharing for shared state, SQLiteData/GRDB for persistence,
and CustomDump for focused assertions.

The first frame is the native app. ATProto, Tangled, source repositories, and
Skip are supporting infrastructure for identity, distribution, editing, and
cross-platform delivery.
