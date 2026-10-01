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

extension NavigationTests {
    @Test
    func openingAnEventPresentsItsViewerAndDismissingReturnsToTheBrowser() async throws {
        let eventID = canonicalRouteEventID
        let database = try makePreparedDatabase()
        let graph = try canonicalNavigationGraph(id: eventID)
        @Bindable var store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.eventRecords = EventRecordClient { _ in graph }
        } operation: {
            Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }

        await store.send(.handleNavigationRequest(.event(eventID, nil)))?.value
        await waitUntil { store.destination?.eventViewer?.id == eventID }

        // The production root view scopes through the installed canonical viewer.
        _ = OpenMusicEventAppRootView(
            store: store,
            serviceEnvironment: .production,
            isServiceEnvironmentSelectionEnabled: false,
            isServiceEnvironmentSwitching: false,
            serviceEnvironmentSelected: { _ in }
        ).body

        let presentation = $store.scope(\.destination).eventViewer
        let eventViewerStore = try #require(presentation.wrappedValue)
        #expect(eventViewerStore.state.id == eventID)

        presentation.wrappedValue = nil

        #expect(store.destination == nil)
    }

    @Test
    func appLaunchCarriesSelectedEventLookupFailureIntoRootRestoration() throws {
        let database = try makePreparedDatabase()
        try database.close()

        let restoration = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            OpenMusicEventApplicationRootView.selectedEventRestoration(
                for: .generic
            )
        }

        #expect(restoration.eventID == nil)
        let error = try #require(restoration.error)
        #expect(String(reflecting: error).contains("closed"))

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            OpenMusicEventAppRoot.State(
                workspaceRestorationErrorAtLaunch: error
            )
        }
        #expect(state.destination == nil)
        #expect(state.workspaceRestorationError != nil)
    }

    @Test
    func eventViewerDismissClearsSelectedEvent() async throws {
        let eventID = canonicalRouteEventID
        let database = try makePreparedDatabase()
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
            try AppState.update {
                $0.selectedEventURI = #bind(eventID)
            }
            .execute(db)
        }

        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph },
            selectedEventIDAtLaunch: eventID
        )
        #expect(store.state.root.destination?.eventViewer?.eventID == eventID)

        await store.send(
            .root(.destination(.eventViewer(.closeButtonTapped)))
        )?.value

        #expect(store.state.root.destination?.eventViewer == nil)
        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == nil)
    }

    @Test
    func editContributorLoadedDraftAcceptsAddLinkAction() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        _ = try await insertCanonicalContributor(into: database, name: "[IVY]")

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: EditContributor.State(
                    contributorID: contributorID,
                    eventID: eventID
                )
            ) {
                EditContributor()
            }
        }

        await store.send(.onAppear)?.value
        #expect(store.hasLoadedDraft)
        #expect(store.form.value.name == "[IVY]")
        #expect(store.form.value.links.isEmpty)

        await store.send(.addLinkButtonTapped)?.value

        #expect(store.form.value.links.count == 1)
    }

    @Test
    func normalEventViewerNavigationPersistsSelectedEvent() async throws {
        let eventID = canonicalRouteEventID
        let database = try makePreparedDatabase()
        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )

        await store.send(.root(.handleNavigationRequest(.event(eventID, nil))))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.id == eventID
        }

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == eventID)
    }

    @Test
    func normalEventViewerDismissClearsSelectedEvent() async throws {
        let eventID = canonicalRouteEventID
        let database = try makePreparedDatabase()
        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )

        await store.send(.root(.handleNavigationRequest(.event(eventID, nil))))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.id == eventID
        }

        await store.send(
            .root(.destination(.eventViewer(.closeButtonTapped)))
        )?.value

        #expect(store.state.root.destination?.eventViewer == nil)
        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == nil)
    }

}
