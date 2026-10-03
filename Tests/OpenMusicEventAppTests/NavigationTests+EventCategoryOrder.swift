import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

extension NavigationTests {
    @Test
    func `an owner can set the event channel order from Comms`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let generalID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let safetyID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcao")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: generalID, eventID: eventID, name: "General")
            try Self.insertCanonicalCategory(db, id: safetyID, eventID: eventID, name: "Safety")
            var event = try #require(try Event.find(eventID).fetchOne(db))
            event.categories = nil
            try Event.upsert { event }.execute(db)
        }

        let ownerID = try #require(DID("did:plc:organizer"))
        let baseline = try CanonicalWorkspaceBaseline.openOrCapture(
            at: FileManager.default.temporaryDirectory
                .appending(path: "OME-CategoryOrder-\(UUID()).sqlite").path,
            from: database
        )
        let session = EventWorkspaceSession(
            eventID: eventID, actorID: ownerID, baseline: baseline
        )
        let oauth = canonicalWorkspaceTestOAuthSession(actorID: ownerID)
        let selectedSession = TestMutex(Optional(oauth))
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getOptionalDefaultSession = { selectedSession.withLock { $0 } }
        } operation: {
            Shared<EventWorkspaceSession?>(.defaultEventWorkspaceSession)
                .withLock { $0 = session }
            return TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        // An event without an explicit channel order still shows its existing categories.
        #expect(store.state.canManageChannels)
        expectNoDifference(store.state.channelRows.map(\.id), [generalID, safetyID])

        // Moving Safety writes the public Event.categories order, then the observed list follows it.
        await store.send(.moveChannelButtonTapped(safetyID, -1))?.value
        let savedOrder = try await database.read {
            try Event.find(eventID).fetchOne($0)?.categories
        }
        expectNoDifference(savedOrder, [safetyID, generalID])
        try await store.state.$event.load()
        expectNoDifference(store.state.channelRows.map(\.id), [safetyID, generalID])

        // Losing the owning account cannot reorder the published category list.
        selectedSession.withLock { $0 = nil }
        #expect(!store.state.canManageChannels)
        await store.send(.moveChannelButtonTapped(safetyID, 1))?.value
        let unchangedOrder = try await database.read {
            try Event.find(eventID).fetchOne($0)?.categories
        }
        expectNoDifference(unchangedOrder, [safetyID, generalID])
    }
}
