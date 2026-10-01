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
    func communicationsViewerAuthoringGrantReachesChannelDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: channelID, eventID: eventID, name: "General")
        }
        let workspace = SourceWorkspace(
            organizerID: testOrganizerID,
            repository: "tangled.org/example/events",
            branch: "main"
        )
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID("did:plc:organizer"))
            ),
            role: .owner,
            workspaceID: workspace.id
        )
        let authoringGrant = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Shared<AuthoringGrant?>(.defaultAuthoringGrant)
        }
        let initialState = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            authoringGrant.withLock { $0 = grant }
            return OpenMusicEventAuthoringWorkspace<EventViewer>.state(
                workspace: workspace,
                grant: authoringGrant
            ) {
                EventViewer.State(eventID: eventID)
            }
        }

        let workspaceStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: initialState) {
                OpenMusicEventWorkspace()
            }
        }
        await waitForObservation {
            workspaceStore.authoring.phase == .inactive(.unavailable)
        }
        authoringGrant.withLock { $0 = grant }
        let authoringStore = workspaceStore
            .scope(\.authoring)
        let workspaceContentStore = authoringStore
            .scope(\.content)
        let eventViewerStore = workspaceContentStore
            .scope(\.content)
        let store = try #require(
            eventViewerStore.scope(\.communicationsViewer)
        )

        // The organizer can manage channels from the Comms list.
        #expect(store.canManageChannels)

        // They open a channel through the same action sent by the channel row.
        store.send(.channelButtonTapped(channelID))

        #expect(store.destination?.channelDetail?.channelID == channelID)
        #expect(store.destination?.channelDetail?.eventID == eventID)
        #expect(store.destination?.channelDetail?.canEditChannel == true)
    }

}
