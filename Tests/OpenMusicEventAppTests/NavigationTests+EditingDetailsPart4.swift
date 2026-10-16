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
    func communicationsViewerOwnerSessionReachesChannelDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpdba"
        ))
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: channelID, eventID: eventID, name: "General")
        }
        let ownerID = try #require(DID("did:plc:organizer"))
        let baseline = try CanonicalWorkspaceBaseline.openOrCapture(
            at: FileManager.default.temporaryDirectory
                .appending(path: "OME-CommsOwner-\(UUID()).sqlite").path,
            from: database
        )
        let session = EventWorkspaceSession(
            eventID: eventID, actorID: ownerID, baseline: baseline
        )
        let oauth = canonicalWorkspaceTestOAuthSession(actorID: ownerID)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getOptionalDefaultSession = { oauth }
        } operation: {
            Shared<EventWorkspaceSession?>(.defaultEventWorkspaceSession)
                .withLock { $0 = session }
            return Store(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        // The organizer can manage channels from the Comms list.
        #expect(store.canManageChannels)

        // They open a channel through the same action sent by the channel row.
        store.send(.channelButtonTapped(channelID))

        #expect(store.destination?.channelDetail?.channelID == channelID)
        #expect(store.destination?.channelDetail?.eventID == eventID)
        #expect(store.destination?.channelDetail?.canEditChannel == true)
    }

}
