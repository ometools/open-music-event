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
Workspace owns reference preparation and the durable proposal state machine.
The Event Viewer owns only editing and presentation.

There is exactly one writable application database: `defaultDatabase`. While a
workspace is prepared, its `SourceWorkspaceDatabase` exposes that same writer as
`main` with `source_baseline` already attached read-only. Descendants receive the
exact prepared database resource from Workspace and issue ordinary live queries
against it. They must never reopen the workspace, install another writer, attach
another comparison baseline, or maintain a reload token to make edits visible.

The first publication freezes the current database difference, creates and
pushes a proposal branch, records the Tangled proposal, and advances the attached
workspace baseline to that proposal commit. Edits made after capture remain in
the writable database and therefore remain visible as unpublished changes. A
later publication adds another commit to the same open proposal branch. Remote
target movement enters the explicit reconciliation path; preparation never
silently fetches or advances an existing baseline.

Durable publication progress lives in `workspacePublications`, keyed by the
workspace ID. Clients are stateless database and network adapters. Losing an
authoring grant interrupts work that is in flight, but a settled prepared
workspace and its open proposal survive grant loss and re-entry. Proposal review
diffs compare the remote target branch with the immutable proposal branch rather
than the workspace's already-advanced baseline.

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
