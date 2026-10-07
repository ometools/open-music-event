import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

let testOrganizerID = OMERecord.Organizer.ID("did:web:example.com")!

func eventID(_ string: String) -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: testOrganizerID,
        eventID: navigationEventLocalID(string)
    )
}

func navigationEventLocalID(_ string: String) -> OMERecord.ID<OMERecord.Event> {
    OMERecord.ID<OMERecord.Event>(rawValue: ATProto.Record.Key(rawValue: string))
}

func sourceProvenance(
    _ source: String,
    ref: String? = "HEAD"
) -> OMERecord.SourceDatabaseInsertion.SourceProvenance {
    OMERecord.SourceDatabaseInsertion.SourceProvenance(
        kind: .tangled,
        reference: "tangled.org/woody.fm/\(source)",
        ref: ref
    )
}

func navigationContributorLocalID(_ string: String) -> OMERecord.ID<OMERecord.Contributor> {
    OMERecord.ID<OMERecord.Contributor>(rawValue: ATProto.Record.Key(rawValue: string))
}

func navigationPerformanceLocalID(_ string: String) -> OMERecord.ID<OMERecord.Performance> {
    OMERecord.ID<OMERecord.Performance>(rawValue: ATProto.Record.Key(rawValue: string))
}

func navigationScheduleLocalID(_ string: String) -> OMERecord.ID<OMERecord.Schedule> {
    OMERecord.ID<OMERecord.Schedule>(rawValue: ATProto.Record.Key(rawValue: string))
}

func navigationStageLocalID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
    OMERecord.ID<OMERecord.Stage>(rawValue: ATProto.Record.Key(rawValue: string))
}

extension EventDetail.State {
    var stageDetailSpawn: Spawn<EventPlaceDetail>? {
        eventPlaceList?.state.destination?.stageDetail
    }
}

func channelLocalID(_ string: String) -> OMERecord.ID<OMERecord.Channel> {
    OMERecord.ID<OMERecord.Channel>(rawValue: ATProto.Record.Key(rawValue: string))
}

func channelRecordID(
    _ string: String,
    eventID: OMERecord.Event.ID
) -> OMERecord.Channel.ID {
    OMERecord.Channel.ID(
        organizerID: eventID.organizerID,
        eventID: eventID.eventID,
        channelID: channelLocalID(string)
    )
}

func commsPostID(
    _ string: String,
    channelID: String,
    eventID: OMERecord.Event.ID
) -> CommsPost.ID {
    CommsPost.ID(
        organizerID: eventID.organizerID,
        eventID: eventID.eventID,
        channelID: channelLocalID(channelID),
        postID: CommsPost.PostID(string)
    )
}

actor ObservationRecorder<Value: Sendable> {
    private var recordedValues: [Value] = []

    var values: [Value] {
        recordedValues
    }

    func record(_ value: Value) {
        recordedValues.append(value)
    }
}

actor BlueskyProfileRequestRecorder {
    private var recordedActors: [String] = []

    var actors: [String] {
        recordedActors
    }

    func record(_ actor: String) {
        recordedActors.append(actor)
    }
}

func observeAuthorizationRequest(
    from center: AuthorizationRequestCenter
) async -> Task<AuthorizationRequestCenter.Request?, Never> {
    let stream = await center.requests()
    return Task {
        var iterator = stream.makeAsyncIterator()
        while let yieldedRequest = await iterator.next() {
            if let request = yieldedRequest {
                return request
            }
        }
        return nil
    }
}


final class IssueRecordingReporter: @unchecked Sendable, IssueReporter {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.withLock { recordedMessages }
    }

    func reportIssue(
        _ message: @autoclosure () -> String?,
        severity: IssueSeverity,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(message() ?? "")
        }
    }

    func reportIssue(
        _ error: any Error,
        _ message: @autoclosure () -> String?,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(
                "Caught error: \(error)"
                    + (message().map { ": \($0)" } ?? "")
            )
        }
    }
}

let canonicalRouteEventID = Event.ID(
    "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
)!

func canonicalRouteRecordID(_ collection: String, _ recordKey: String) -> ATProto.URI {
    ATProto.URI("at://did:plc:organizer/\(collection)/\(recordKey)")!
}

@MainActor
@Suite(
    .dependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.uuid = .incrementing
    },
    .tcaExhaustivity(.off)
)
struct NavigationTests {
    @Test(arguments: [
        AppRoute.event(canonicalRouteEventID, nil),
        AppRoute.event(canonicalRouteEventID, .schedule),
        AppRoute.event(canonicalRouteEventID, .contributors),
        AppRoute.event(canonicalRouteEventID, .contributor(canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj"))),
        AppRoute.event(canonicalRouteEventID, .stages),
        AppRoute.event(canonicalRouteEventID, .stage(canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak"))),
        AppRoute.event(canonicalRouteEventID, .performance(canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam"))),
        AppRoute.event(canonicalRouteEventID, .workspace),
        AppRoute.event(canonicalRouteEventID, .settings),
        AppRoute.event(canonicalRouteEventID, .channel(canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan"))),
        AppRoute.event(
            canonicalRouteEventID,
            .post(
                channelID: canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan"),
                postID: canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
            )
        ),
    ])
    func appRouteRoundTrips(expected: AppRoute) throws {
        let path = expected.path
        let url = try #require(URL(string: "https://openmusicevent.app\(path)"))
        let route = try #require(AppRoute(url: url))

        #expect(route == expected)
        #expect(route.path == url.path(percentEncoded: true))
        #expect(route.notificationRoute == url.path(percentEncoded: true))
        #expect(AppRoute(notificationRoute: route.notificationRoute) == expected)
    }

    @Test
    func canonicalEventRouteHasAnExplicitRecordPath() {
        #expect(
            AppRoute.event(canonicalRouteEventID, nil).path
                == "/records/did%3Aplc%3Aorganizer/3mrdbziccpcah"
        )
    }

    @Test(arguments: [
        ("https://festival.example/events/2026", AppRoute.event(canonicalRouteEventID, nil)),
        ("https://festival.example/events/2026/schedule", AppRoute.event(canonicalRouteEventID, .schedule)),
        ("https://festival.example:443/events/2026", AppRoute.event(canonicalRouteEventID, nil)),
    ])
    func brandedEventRouteClaimsResolveIntoDurableRoutes(
        urlString: String,
        expected: AppRoute
    ) throws {
        let claim = BrandedEventRouteClaim(
            host: "festival.example",
            eventClaim: "2026",
            eventID: canonicalRouteEventID
        )
        let url = try #require(URL(string: urlString))
        let route = try #require(AppRoute(url: url, brandedClaims: [claim]))

        expectNoDifference(route, expected)
        #expect(route.path == expected.path)
        #expect(AppRoute(url: url) == nil)
    }

    @Test(arguments: [
        "https://somewhere-else.example/events/2026",
        "https://festival.example/events/2025",
        "http://festival.example/events/2026",
        "https://festival.example:8443/events/2026",
    ])
    func brandedEventRouteClaimsRequireTheExactSecureOrigin(urlString: String) throws {
        let claim = BrandedEventRouteClaim(
            host: "festival.example",
            eventClaim: "2026",
            eventID: canonicalRouteEventID
        )
        let url = try #require(URL(string: urlString))

        #expect(AppRoute(url: url, brandedClaims: [claim]) == nil)
    }

    @Test(arguments: [
        "https://example.com/records/did%3Aplc%3Aorganizer/3mrdbziccpcah",
        "records/did%3Aplc%3Aorganizer/3mrdbziccpcah",
        "//example.com/records/did%3Aplc%3Aorganizer/3mrdbziccpcah",
    ])
    func appRouteRejectsNotificationValuesThatAreNotAppPaths(value: String) {
        #expect(AppRoute(notificationRoute: value) == nil)
    }

    @Test
    func appRouteAcceptsEditEventPathAsWorkspace() throws {
        let url = try #require(URL(
            string: "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/edit"
        ))
        #expect(AppRoute(url: url) == AppRoute.event(canonicalRouteEventID, .workspace))
    }

    @Test(arguments: [
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/people",
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/participants/3mrdbziccpcaj",
    ])
    func appRouteRejectsOldContributorURLs(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(AppRoute(url: url) == nil)
    }

    @Test(arguments: [
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/performances",
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/performances/3mrdbziccpcam/extra",
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/performance/3mrdbziccpcam",
    ])
    func appRouteRejectsIncompleteOrUnsupportedPerformanceURLs(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(AppRoute(url: url) == nil)
    }

    @Test(arguments: [
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/communications/general/posts",
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/communications/general/post/welcome",
        "https://openmusicevent.app/records/did%3Aplc%3Aorganizer/3mrdbziccpcah/communications/general/posts/welcome/extra",
    ])
    func appRouteRejectsIncompleteOrUnsupportedCommunicationURLs(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(AppRoute(url: url) == nil)
    }

    @Test
    func siteMapMetadataIsAvailableWhenViewerStateIsCreated() async throws {
        let database = try makePreparedDatabase()
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let siteMapURL = URL(string: "https://example.com/site-map.png")!
        try await database.write { db in
            let event = try Event(
                id: eventID, name: "Event 1", createdAt: "2026-09-01T12:00:00Z",
                timeZone: .gmt,
                siteMap: .init(title: "Site Map", styles: [
                    .init(id: "public", title: "Public", image: .init(
                        source: .known(.url(siteMapURL)), role: .known(.siteMap)
                    ))
                ])
            )
            try Event.insert { event }.execute(db)
        }

        // The installed event already tells the viewer that a site map exists.
        let state = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            SiteMapViewer.State(eventID: eventID)
        }

        expectNoDifference(
            state.selectedAsset?.url,
            siteMapURL
        )
        expectNoDifference(state.selectedAsset?.recordID, eventID)
        #expect(state.featureTitle == "Site Map")
    }

    @Test
    func siteMapViewerStartsWithTheSourceDefaultAndSwitchesStyles() async throws {
        let database = try makePreparedDatabase()
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let festivalStyleID = "festival"
        let campingStyleID = "camping"
        let festivalURL = URL(string: "https://example.com/maps/festival.png")!
        let campingURL = URL(string: "https://example.com/maps/camping.png")!
        try await database.write { db in
            let event = try Event(
                id: eventID, name: "Event 1", createdAt: "2026-09-01T12:00:00Z",
                timeZone: .gmt,
                siteMap: .init(
                    title: "Festival Map",
                    styles: [
                        .init(id: festivalStyleID, title: "Festival", image: .init(
                            source: .known(.url(festivalURL)), role: .known(.siteMap)
                        )),
                        .init(id: campingStyleID, title: "Camping", image: .init(
                            source: .known(.url(campingURL)), role: .known(.siteMap)
                        )),
                    ],
                    defaultStyleID: festivalStyleID
                )
            )
            try Event.insert { event }.execute(db)
        }
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SiteMapViewer.State(eventID: eventID)) {
                SiteMapViewer()
            }
        }

        // The map opens on its source-defined style and exposes the layer switcher.
        #expect(store.state.selectedStyle?.title == "Festival")
        #expect(store.state.selectedAsset?.url == festivalURL)
        #expect(store.state.showsStyleSwitcher)
        #expect(store.state.featureTitle == "Site Maps")

        // The attendee switches to Camping for this viewer session.
        store.send(.styleButtonTapped(campingStyleID)) {
            $0.selectedStyleID = campingStyleID
        }
        #expect(store.state.selectedStyle?.title == "Camping")
        #expect(store.state.selectedAsset?.url == campingURL)
    }

    @Test
    func navigationRequestInstallsCanonicalEventAndMountsViewer() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let graph = try canonicalNavigationGraph(id: eventID)
        let downloads = TestMutex<[Event.ID]>([])
        let client = EventRecordClient { requestedID in
            downloads.withLock { $0.append(requestedID) }
            return graph
        }
        let store = makeCanonicalRootHarnessStore(database: database, client: client)

        let navigationTask = store.send(
            .root(.handleNavigationRequest(.event(eventID, nil)))
        )
        await navigationTask?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.eventID == eventID
        }

        #expect(downloads.withLock { $0 } == [eventID])
        #expect(store.state.root.destination?.eventViewer?.pendingScheduleLaunchAction == nil)
        let saved = try await database.read { db in
            (
                selection: try AppState.find(1).fetchOne(db)?.selectedEventID,
                installations: try InstalledEvent.all.fetchAll(db)
            )
        }
        #expect(saved.selection == eventID)
        #expect(saved.installations == [InstalledEvent(id: eventID)])
    }

    @Test
    func deepLinkKeepsLoadingUntilCanonicalRecordsAreInstalled() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let graph = try canonicalNavigationGraph(id: eventID)
        let continuation = TestMutex<CheckedContinuation<EventRecordGraph, Never>?>(nil)
        let client = EventRecordClient { _ in
            await withCheckedContinuation { pending in
                continuation.withLock { $0 = pending }
            }
        }
        let store = makeCanonicalRootHarnessStore(database: database, client: client)
        let route = AppRoute.event(eventID, .communications)

        let navigationTask = store.send(.root(.openRoute(route)))
        await waitUntil(timeout: .seconds(90)) { continuation.withLock { $0 != nil } }
        #expect(store.state.root.eventEntry?.route == route)
        #expect(store.state.root.eventEntry?.phase == .loading)
        #expect(store.state.root.destination?.eventViewer == nil)

        continuation.withLock { $0 }?.resume(returning: graph)
        await navigationTask?.value
        await waitUntil { store.state.root.destination?.eventViewer?.eventID == eventID }
        #expect(store.state.root.eventEntry == nil)
        #expect(store.state.root.destination?.eventViewer?.selectedFeature == .communications)
    }

    @Test
    func supersededDeepLinkCannotReplaceTheNewerCanonicalEvent() async throws {
        let database = try makePreparedDatabase()
        let firstEventID = canonicalRouteEventID
        let secondEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcai")
        let firstGraph = try canonicalNavigationGraph(id: firstEventID)
        let secondGraph = try canonicalNavigationGraph(id: secondEventID)
        let continuations = TestMutex<
            [Event.ID: CheckedContinuation<EventRecordGraph, Never>]
        >([:])
        let client = EventRecordClient { eventID in
            await withCheckedContinuation { pending in
                continuations.withLock { $0[eventID] = pending }
            }
        }
        let store = makeCanonicalRootHarnessStore(database: database, client: client)

        let firstTask = store.send(.root(.openRoute(.event(firstEventID, .schedule))))
        await waitUntil(timeout: .seconds(90)) { continuations.withLock { $0[firstEventID] != nil } }
        let secondTask = store.send(.root(.openRoute(.event(secondEventID, .communications))))
        await waitUntil(timeout: .seconds(90)) { continuations.withLock { $0[secondEventID] != nil } }

        continuations.withLock { $0[secondEventID] }?.resume(returning: secondGraph)
        await secondTask?.value
        await waitUntil { store.state.root.destination?.eventViewer?.eventID == secondEventID }

        continuations.withLock { $0[firstEventID] }?.resume(returning: firstGraph)
        await firstTask?.value
        #expect(store.state.root.destination?.eventViewer?.eventID == secondEventID)
        #expect(store.state.root.destination?.eventViewer?.selectedFeature == .communications)
        let selection = try await database.read { db in
            try AppState.find(1).fetchOne(db)?.selectedEventID
        }
        #expect(selection == secondEventID)
    }

    #if !os(Android)
    @Test
    func contentNotificationOpensItsTypedApplicationRoute() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(eventID, .communications)
        let json = """
        {
          "aps": {"alert": {"title": "Event One", "body": "A new announcement is available"}},
          "kind": "content",
          "source": "\(eventID)",
          "version": "a1b2c3d4",
          "route": "\(route.notificationRoute)"
        }
        """

        await store.send(
            .notification(
                NotificationEvent(
                    json: json,
                    delivery: .userInteraction(actionIdentifier: "open")
                )
            )
        )?.value

        #expect(store.state.root.destination?.eventViewer?.selectedFeature == .communications)
        #expect(store.state.root.destination?.eventViewer?.eventID == eventID)
    }

    @Test
    func `tapping a notification loads its post while the record arrives`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcae")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcae")
        let graph = try canonicalNavigationGraph(id: eventID)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General"
            )
        }
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(
            eventID, .post(channelID: channelID, postID: postID)
        )
        let json = """
        {
          "aps": {"alert": {"title": "Gates are open", "body": "Welcome to Wicked Woods."}},
          "kind": "content",
          "source": "\(eventID)",
          "version": "notification-post-1",
          "route": "\(route.notificationRoute)"
        }
        """

        await store.send(
            .notification(
                NotificationEvent(
                    json: json,
                    delivery: .userInteraction(actionIdentifier: "open")
                )
            )
        )?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?
                .communicationsViewer?.destination?.channelDetail?
                .destination?.postDetail?.postID == postID
        }
        expectNoDifference(
            store.state.root.destination?.eventViewer?
                .communicationsViewer?.destination?.channelDetail?
                .destination?.postDetail?.loadState,
            .loading
        )

        try await database.write { db in
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: channelID,
                title: "Gates are open", text: "Welcome to Wicked Woods."
            )
        }
        await waitUntil {
            store.state.root.destination?.eventViewer?
                .communicationsViewer?.destination?.channelDetail?
                .destination?.postDetail?.post?.title == "Gates are open"
        }
        let loadedPost = try #require(
            store.state.root.destination?.eventViewer?
                .communicationsViewer?.destination?.channelDetail?
                .destination?.postDetail?.post
        )
        expectNoDifference(loadedPost.id, postID)
        expectNoDifference(loadedPost.text, "Welcome to Wicked Woods.")
    }

    @Test
    func contentNotificationSelectsCommunicationsFromAnOpenSchedule() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let graph = try canonicalNavigationGraph(id: eventID)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Wicked Woods")
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
            try EventDetailState.insert {
                EventDetailState(id: eventID, didInitializeUserSchedules: true)
            }.execute(db)
        }
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph },
            selectedEventIDAtLaunch: eventID
        )
        let route = AppRoute.event(eventID, .communications)
        let json = """
        {
          "aps": {"alert": {"title": "Wicked Woods", "body": "A new announcement is available"}},
          "kind": "content",
          "source": "\(eventID)",
          "version": "manual-content-1",
          "route": "\(route.notificationRoute)"
        }
        """

        #expect(
            store.state.root.destination?.eventViewer?.selectedFeature
                == .schedule(.schedule)
        )

        await store.send(
            .notification(
                NotificationEvent(
                    json: json,
                    delivery: .userInteraction(
                        actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"
                    )
                )
            )
        )?.value

        #expect(store.state.root.destination?.eventViewer?.selectedFeature == .communications)
        #expect(store.state.root.destination?.eventViewer?.eventID == eventID)
    }

    @Test
    func secondDeepLinkReplacesMountedEventViewer() async throws {
        let database = try makePreparedDatabase()
        let firstEventID = canonicalRouteEventID
        let secondEventID = canonicalRouteRecordID(
            "events.openmusic.event", "3mrdbziccpcai"
        )
        let firstGraph = try canonicalNavigationGraph(id: firstEventID)
        let secondGraph = try canonicalNavigationGraph(id: secondEventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { eventID in
                eventID == firstEventID ? firstGraph : secondGraph
            }
        )
        let firstURL = try #require(URL(
            string: "https://openmusicevent.app" + AppRoute.event(firstEventID, nil).path
        ))
        let secondURL = try #require(URL(
            string: "https://openmusicevent.app" + AppRoute.event(secondEventID, nil).path
        ))

        await store.send(.root(.openURL(firstURL)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.eventID == firstEventID
        }

        await store.send(.root(.openURL(secondURL)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.eventID == secondEventID
        }

        try await waitForSelectedEventID(secondEventID, in: database)
    }

    @Test
    func brandedEventURLInstallsAndMountsTheDurableEvent() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let graph = try canonicalNavigationGraph(id: eventID)
        let claim = BrandedEventRouteClaim(
            host: "wickedwoods.openmusicevent.app",
            eventClaim: "2026",
            eventID: eventID
        )
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph },
            brandedEventRouteClaims: [claim]
        )
        let url = try #require(URL(
            string: "https://wickedwoods.openmusicevent.app/events/2026"
        ))

        await store.send(.root(.openURL(url)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.eventID == eventID
        }

        #expect(store.state.root.destination?.eventViewer?.eventID == eventID)
        try await waitForSelectedEventID(eventID, in: database)
    }
    #endif

    @Test
    func contributorDeepLinkSelectsContributorDestination() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcae"
        )
        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(eventID, .contributor(contributorID))
        let url = try #require(URL(string: "https://openmusicevent.app" + route.path))

        await store.send(.root(.openURL(url)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.contributorsViewer?
                .state.destination?.contributorDetail?.state.contributorID == contributorID
        }

        #expect(store.state.root.destination?.eventViewer?.selectedFeature == .contributors)
        #expect(
            store.state.root.destination?.eventViewer?.contributorsViewer?
                .state.destination?.contributorDetail?.state.contributorID == contributorID
        )
    }

    @Test
    func stageDeepLinkSelectsStageDestination() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcae"
        )
        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(eventID, .stage(stageID))
        let url = try #require(URL(string: "https://openmusicevent.app" + route.path))

        await store.send(.root(.openURL(url)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.eventPlaceList?
                .state.destination?.stageDetail?.state.eventPlaceID == stageID
        }

        #expect(store.state.root.destination?.eventViewer?.selectedFeature == .stages)
        #expect(
            store.state.root.destination?.eventViewer?.eventPlaceList?
                .state.destination?.stageDetail?.state.eventPlaceID == stageID
        )
    }

    @Test
    func performanceDeepLinkPresentsPerformanceDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let performanceID = canonicalRouteRecordID(
            "events.openmusic.programItem", "3mrdbziccpcae"
        )
        let scheduleID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcae"
        )
        let stageID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcae"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcae"
        )
        let date = try #require(LocalDate("2026-08-07"))
        let graph = try canonicalNavigationGraph(id: eventID)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalSchedule(
                db, id: scheduleID, eventID: eventID, date: date
            )
            try Self.insertCanonicalStage(
                db, id: stageID, eventID: eventID, name: "Meadow"
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: eventID, eventPlaces: [stageID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: performanceID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: stageID, title: "Opening",
                startsAt: Date(timeIntervalSince1970: 0),
                endsAt: Date(timeIntervalSince1970: 3_600)
            )
            // This deep link opens a previously installed event, not a browse-only record.
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
        }

        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(eventID, .performance(performanceID))
        let url = try #require(URL(string: "https://openmusicevent.app" + route.path))
        await store.send(.root(.openURL(url)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.scheduleViewers
                .contains { $0.state.destination?.performanceDetail?.performanceID == performanceID }
                == true
        }

        #expect(
            store.state.root.destination?.eventViewer?.selectedFeature.description
                == "schedule:\(programID)"
        )
        let scheduleViewer = try #require(
            store.state.root.destination?.eventViewer?.scheduleViewers.first {
                $0.state.scheduleDivision.programID == programID
            }
        )
        let performanceDetail = try #require(scheduleViewer.state.destination?.performanceDetail)
        #expect(performanceDetail.performanceID == performanceID)
        #expect(performanceDetail.performance?.title == "Opening")
    }

    func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    func makeFileBackedPreparedDatabase(
        at databaseURL: URL
    ) throws -> any DatabaseWriter {
        let database = try DatabasePool(path: databaseURL.path)
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }


    func makeCoreDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }


    func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ome-navigation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }


    nonisolated static func insertOrganizer(
        _ db: Database,
        id organizerID: OMERecord.Organizer.ID
    ) throws {
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(db)
    }


    nonisolated static func insertEvent(
        _ db: Database,
        id eventID: OMERecord.Event.ID,
        name: String,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        timeZone: TimeZone = .current
    ) throws {
        try OMERecord.Event.insert {
            testEventDraft(
                id: eventID,
                name: name,
                startDate: startDate,
                endDate: endDate,
                timeZone: timeZone
            )
        }
        .execute(db)
    }

    nonisolated static func insertContributor(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        contributorID: String,
        name: String,
        did: DID? = nil,
        bio: String? = nil,
        imageURL: URL? = nil,
        logoURL: URL? = nil,
        links: [ExternalPlatform.Link]? = nil
    ) throws {
        try OMERecord.Contributor.insert {
            OMERecord.Contributor.Draft(
                id: OMERecord.Contributor.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    contributorID: navigationContributorLocalID(contributorID)
                ),
                name: name,
                did: did,
                bio: bio,
                imageURL: imageURL,
                logoURL: logoURL,
                links: links
            )
        }
        .execute(db)
    }

    nonisolated static func insertPerformance(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        performanceID: String,
        stageID: String,
        scheduleID: String,
        startTime: Date,
        endTime: Date,
        title: String,
        description: String? = nil,
        recordings: [ExternalPlatform.Asset] = []
    ) throws {
        try OMERecord.Performance.insert {
            OMERecord.Performance.Draft(
                id: OMERecord.Performance.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: navigationPerformanceLocalID(performanceID)
                ),
                stageID: navigationStageLocalID(stageID),
                scheduleID: navigationScheduleLocalID(scheduleID),
                startTime: startTime,
                endTime: endTime,
                title: title,
                description: description,
                recordings: recordings
            )
        }
        .execute(db)
    }

    nonisolated static func insertPerformanceContributor(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        performanceID: String,
        contributorID: String,
        contributorActor: OMERecord.Contributor.Actor? = nil,
        billing: OMERecord.Performance.Contributors.Billing = .primary,
        role: OMERecord.Performance.Contributors.Role? = nil,
        sortIndex: Int = 0
    ) throws {
        try OMERecord.Performance.Contributors.insert {
            OMERecord.Performance.Contributors.Draft(
                performanceID: OMERecord.Performance.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: navigationPerformanceLocalID(performanceID)
                ),
                contributorID: navigationContributorLocalID(contributorID),
                anonymousName: nil,
                contributorActor: contributorActor,
                billing: billing,
                role: role,
                sortIndex: sortIndex
            )
        }
        .execute(db)
    }

    nonisolated static func insertSchedule(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        scheduleID: String,
        date: LocalDate,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        customTitle: String? = nil
    ) throws {
        try OMERecord.Schedule.insert {
            OMERecord.Schedule.Draft(
                id: OMERecord.Schedule.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    scheduleID: navigationScheduleLocalID(scheduleID)
                ),
                date: date,
                startsAt: startsAt,
                endsAt: endsAt,
                customTitle: customTitle
            )
        }
        .execute(db)
    }

    nonisolated static func insertStage(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        stageID: String,
        name: String,
        color: OMEColor = 0x336699,
        category: OMERecord.Stage.Category? = nil,
        sortIndex: Int? = nil,
        iconImageURL: URL? = nil,
        systemIconName: String? = nil,
        iconShortCode: String? = nil,
        imageURL: URL? = nil,
        posterImageURL: URL? = nil,
        lineup: [OMERecord.ID<OMERecord.Contributor>]? = nil
    ) throws {
        try OMERecord.Stage.insert {
            OMERecord.Stage.Draft(
                id: OMERecord.Stage.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    stageID: navigationStageLocalID(stageID)
                ),
                name: name,
                color: color,
                category: category,
                sortIndex: sortIndex,
                iconImageURL: iconImageURL,
                systemIconName: systemIconName,
                iconShortCode: iconShortCode,
                imageURL: imageURL,
                posterImageURL: posterImageURL,
                lineup: lineup
            )
        }
        .execute(db)
    }

    nonisolated static func insertChannel(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        channelID: String,
        name: String,
        description: String? = nil,
        sortIndex: Int? = nil,
        defaultNotificationState: OMERecord.Channel.NotificationState = .unsubscribed,
        notificationsRequired: Bool = false
    ) throws {
        try OMERecord.Channel.insert {
            OMERecord.Channel.Draft(
                id: channelRecordID(channelID, eventID: eventID),
                name: name,
                description: description ?? "Updates from \(name).",
                iconImageURL: nil,
                headerImageURL: nil,
                sortIndex: sortIndex,
                defaultNotificationState: defaultNotificationState,
                notificationsRequired: notificationsRequired
            )
        }
        .execute(db)
    }

    nonisolated static func insertCommsPost(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        channelID: String,
        postID: String,
        title: String,
        contents: String,
        headerImageURL: URL? = nil,
        timestamp: Date? = nil,
        isPinned: Bool = false,
        sortIndex: Int
    ) throws {
        try CommsPost.insert {
            CommsPost(
                id: commsPostID(postID, channelID: channelID, eventID: eventID),
                title: title,
                contents: contents,
                headerImageURL: headerImageURL,
                timestamp: timestamp,
                isPinned: isPinned,
                sortIndex: sortIndex
            )
        }
        .execute(db)
    }

    func waitForBlueskyProfile(
        in store: StoreOf<ContributorDetail>
    ) async throws {
        for _ in 0..<100 {
            if store.profile?.handle != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.profile?.handle != nil)
    }

    func waitForContributorListBlueskyProfile(
        in store: StoreOf<ContributorList>,
        contributorID: Contributor.ID
    ) async throws {
        for _ in 0..<100 {
            if store.contributorRows.first(where: { $0.contributorID == contributorID })?
                .handle != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(
            store.contributorRows.first(where: { $0.contributorID == contributorID })?
                .handle != nil
        )
    }

    func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: @escaping @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await clock.sleep(for: .milliseconds(5))
        }
        Issue.record(
            "Condition was not satisfied within \(timeout)",
            sourceLocation: sourceLocation
        )
    }


    func waitForObservation(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        while !condition() {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = condition()
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    func waitForSelectedEventID(
        _ expectedEventID: Event.ID?,
        in database: any DatabaseWriter,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            let selectedEventID = try await database.read { db in
                try AppState.fetchOne(db)?.selectedEventID
            }
            if selectedEventID == expectedEventID { return }
            try await clock.sleep(for: .milliseconds(1))
        }

        let selectedEventID = try await database.read { db in
            try AppState.fetchOne(db)?.selectedEventID
        }
        Issue.record(
            "Expected selected event \(String(describing: expectedEventID)), got \(String(describing: selectedEventID))",
            sourceLocation: sourceLocation
        )
    }

    func canonicalNavigationGraph(id: Event.ID) throws -> EventRecordGraph {
        try EventRecordGraph(
            event: Event(
                id: id,
                name: "Wicked Woods",
                createdAt: "2026-09-01T12:00:00Z",
                timeZone: .gmt
            )
        )
    }

    nonisolated static func insertCanonicalEvent(
        _ db: Database,
        id: Event.ID,
        name: String,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        timeZone: TimeZone = .gmt
    ) throws {
        var event = try Event(
            id: id,
            name: name,
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        event.start = startDate.map { .known(.day(Event.Day(value: $0))) }
        event.end = endDate.map { .known(.day(Event.Day(value: $0))) }
        try Event.insert { event }.execute(db)
    }

    nonisolated static func insertCanonicalStage(
        _ db: Database,
        id: EventPlace.ID,
        eventID: Event.ID,
        name: String,
        category: String? = nil,
        lineup: [Contributor.ID]? = nil,
        sortIndex: Int? = nil
    ) throws {
        var place = try EventPlace(
            id: id,
            event: eventID,
            name: name,
            createdAt: "2026-09-01T12:00:00Z"
        )
        var stageUse = EventPlace.Kind.Stage()
        stageUse.category = category
        stageUse.lineup = lineup
        stageUse.sortIndex = sortIndex
        place.kind = .known(.stage(stageUse))
        try EventPlace.insert { place }.execute(db)
    }

    nonisolated static func insertCanonicalCategory(
        _ db: Database,
        id: Social.Category.ID,
        eventID: Event.ID,
        name: String,
        description: String? = nil,
        defaultNotificationState: Social.Category.NotificationState = .subscribed,
        notificationsRequired: Bool = false
    ) throws {
        var category = try Social.Category(
            id: id,
            event: eventID,
            name: name,
            createdAt: "2026-09-01T12:00:00Z"
        )
        category.description = description
        category.defaultNotificationState = .known(
            notificationsRequired ? .subscribed : defaultNotificationState
        )
        category.notificationsRequired = notificationsRequired
        try Social.Category.insert { category }.execute(db)
        var event = try #require(try Event.find(eventID).fetchOne(db))
        event.categories = (event.categories ?? []) + [id]
        try Event.upsert { event }.execute(db)
    }

    nonisolated static func insertCanonicalPost(
        _ db: Database,
        id: Social.Post.ID,
        eventID: Event.ID,
        categoryID: Social.Category.ID,
        title: String,
        text: String,
        pinned: Bool = false
    ) throws {
        var post = try Social.Post(
            id: id,
            text: text,
            event: eventID,
            category: categoryID,
            createdAt: "2026-09-01T12:00:00Z"
        )
        post.title = title
        try Social.Post.insert { post }.execute(db)
        if pinned {
            var category = try #require(try Social.Category.find(categoryID).fetchOne(db))
            category.pinnedPosts = (category.pinnedPosts ?? []) + [id]
            try Social.Category.upsert { category }.execute(db)
        }
    }

    nonisolated static func insertCanonicalSchedule(
        _ db: Database,
        id: Schedule.ID,
        eventID: Event.ID,
        date: LocalDate,
        title: String? = nil
    ) throws {
        var schedule = try Schedule(
            id: id,
            event: eventID,
            date: date,
            createdAt: "2026-09-01T12:00:00Z"
        )
        schedule.title = title
        try Schedule.insert { schedule }.execute(db)
        var event = try #require(try Event.find(eventID).fetchOne(db))
        event.schedules = (event.schedules ?? []) + [id]
        try Event.upsert { event }.execute(db)
    }

    nonisolated static func insertCanonicalProgram(
        _ db: Database,
        id: Program.ID,
        eventID: Event.ID,
        eventPlaces: [EventPlace.ID],
        title: String = "Main Schedule"
    ) throws {
        let program = try Program(
            id: id,
            event: eventID,
            title: title,
            createdAt: "2026-09-01T12:00:00Z",
            eventPlaces: eventPlaces
        )
        try Program.insert { program }.execute(db)
        var event = try #require(try Event.find(eventID).fetchOne(db))
        event.programs = (event.programs ?? []) + [id]
        try Event.upsert { event }.execute(db)
    }

    nonisolated static func insertCanonicalProgramItem(
        _ db: Database,
        id: ProgramItem.ID,
        eventID: Event.ID,
        programID: Program.ID,
        scheduleID: Schedule.ID,
        placeID: EventPlace.ID,
        title: String,
        startsAt: Date,
        endsAt: Date,
        credits: [ProgramItem.Credit]? = nil
    ) throws {
        var item = try ProgramItem(
            id: id,
            event: eventID,
            program: programID,
            title: title,
            createdAt: "2026-09-01T12:00:00Z"
        )
        item.schedule = scheduleID
        item.eventPlace = placeID
        item.startsAt = ATProto.DateTime(
            rawValue: ISO8601DateFormatter().string(from: startsAt)
        )
        item.endsAt = ATProto.DateTime(
            rawValue: ISO8601DateFormatter().string(from: endsAt)
        )
        item.credits = credits
        try ProgramItem.insert { item }.execute(db)
    }

    func insertCanonicalContributor(
        into database: any DatabaseWriter,
        name: String,
        subject: DID? = nil,
        description: String? = nil,
        links: [OME.Link]? = nil
    ) async throws -> Contributor {
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        let createdAt = ATProto.DateTime(rawValue: "2026-08-01T12:00:00Z")
        let event = try Event(
            id: eventID,
            name: "Event One",
            createdAt: createdAt,
            timeZone: .gmt
        )
        var contributor = try Contributor(
            id: contributorID,
            event: eventID,
            name: name,
            createdAt: createdAt,
            subject: subject
        )
        contributor.description = description
        contributor.links = links
        let record = contributor
        try await database.write { db in
            try Event.insert { event }.execute(db)
            try Contributor.insert { record }.execute(db)
        }
        return record
    }

    func makeCanonicalRootHarnessStore(
        database: any DatabaseWriter,
        client: EventRecordClient,
        selectedEventIDAtLaunch: Event.ID? = nil,
        brandedEventRouteClaims: [BrandedEventRouteClaim] = []
    ) -> TestStore<RootHarness> {
        withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.eventRecords = client
            $0.brandedEventRouteClaims = brandedEventRouteClaims
        } operation: {
            var state = RootHarness.State()
            state.root = OpenMusicEventAppRoot.State(
                selectedEventIDAtLaunch: selectedEventIDAtLaunch
            )
            return TestStore(initialState: state) {
                RootHarness()
            }
        }
    }


    func makeEventViewerHarnessStore(
        eventID: Event.ID = canonicalRouteEventID,
        database: (any DatabaseWriter)? = nil
    ) throws -> TestStore<EventDetailHarness> {
        let database = try database ?? makePreparedDatabase()
        return withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventDetailHarness.State(eventID: eventID)) {
                EventDetailHarness()
            }
        }
    }
}

@Feature
struct RootHarness {
    struct State {
        @DebugSnapshotIgnored
        var root = OpenMusicEventAppRoot.State()
    }

    enum Action {
        case notification(NotificationEvent)
        case root(OpenMusicEventAppRoot.Action)
    }

    var body: some Feature {
        Features {
            Update { _, action in
                switch action {
                case let .notification(event):
                    store.addTask {
                        let reaction = try store.state.root.notificationEvent(event)
                        await reaction?.value
                    }

                case .root:
                    break
                }
            }
            Scope(\.root) {
                OpenMusicEventAppRoot()
            }
        }
        .onTrigger(store.root.notificationSignal) { _, _ in }
    }
}

@Feature
struct MyEventsEventHarness {
    struct State {
        var lastRequest: NavigationRequest?
        var myEvents = MyEvents.State()
    }

    enum Action {
        case myEvents(MyEvents.Action)
    }

    var body: some Feature {
        Scope(\.myEvents) {
            MyEvents()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
struct EventDetailHarness {
    struct State {
        init(eventID: Event.ID = canonicalRouteEventID) {
            self.eventViewer = EventDetail.State.route(
                eventID: eventID,
                target: nil
            )
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var eventViewer: EventDetail.State

        var eventInfoViewer: Spawn<EventInfoViewer> {
            get { eventViewer.eventInfoViewer! }
            set { eventViewer.eventInfoViewer = newValue }
        }

    }

    enum Action {
        case eventViewer(EventDetail.Action)
    }

    var body: some Feature {
        Scope(\.eventViewer) {
            EventDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}
