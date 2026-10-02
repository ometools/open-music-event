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
    func createContributorRequiresValidComposableForm() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditContributor.State(eventID: eventID)) {
                EditContributor()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented)
        #expect(
            store.state.form.validation[AnyHashable(\EditContributor.FormValue.name)]?.errors.map(\.message)
                == ["Enter a name."]
        )

        let contributors = try await database.read { db in
            try Contributor.where { $0.event.eq(eventID) }.fetchAll(db)
        }
        #expect(contributors.isEmpty)
    }

    @Test
    func stageDetailEditButtonEmitsEventStageEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageDetail.State(stageID: stageID, eventID: eventID)) {
                StageDetail()
            }
        }

        let editTask = store.send(.editButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.editStage(eventID: eventID, stageID: stageID)),
            timeout: .seconds(1)
        )
        await editTask?.value
    }

    @Test
    func editStageSavesCanonicalEventPlaceChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let lineupID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let posterURL = try #require(URL(string: "https://example.com/poster.png"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            var place = try EventPlace(
                id: stageID,
                event: eventID,
                name: "Old Meadow",
                createdAt: "2026-09-01T12:00:00Z"
            )
            var stageUse = EventPlace.Kind.Stage()
            stageUse.lineup = [lineupID]
            place.kind = .known(.stage(stageUse))
            place.media = [.known(.image(OME.Image(
                source: .known(.url(posterURL)),
                role: .known(.poster)
            )))]
            try EventPlace.insert { place }.execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditStage.State(stageID: stageID, eventID: eventID)) {
                EditStage()
            }
        }

        #expect(store.state.hasLoadedDraft)
        #expect(store.state.form.value.name == "Old Meadow")
        store.modify {
            $0.form.value.name = " New Meadow "
            $0.category = " workshop "
            $0.sortIndex = " 7 "
            $0.colorHex = " #AABBCC "
            $0.iconName = "sparkles"
            $0.shortLabel = " MD "
            $0.logoURL = "https://example.com/logo.png"
            $0.heroImageURL = "https://example.com/hero.png"
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let stage = try await database.read { db in
            try #require(
                try StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(stage.name == "New Meadow")
        #expect(stage.stageUse?.category == "workshop")
        #expect(stage.stageUse?.sortIndex == 7)
        #expect(stage.stageUse?.color?.rawValue == 0xAABBCC)
        #expect(stage.stageUse?.icon?.rawValue == "sparkles")
        #expect(stage.stageUse?.shortLabel == "MD")
        #expect(stage.stageUse?.lineup == [lineupID])
        #expect(stage.media?.count == 3)
        #expect(stage.media?.compactMap { medium -> String? in
            guard case let .known(.image(image)) = medium else { return nil }
            return image.displayImageAsset(recordID: eventID)?.url?.absoluteString
        }.sorted() == [
            "https://example.com/hero.png",
            "https://example.com/logo.png",
            "https://example.com/poster.png",
        ])
    }

    @Test
    func stagesViewerAddButtonEmitsCreateStageEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StagesViewer.State(eventID: eventID)) {
                StagesViewer()
            }
        }

        let addTask = store.send(.addButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.createStage(eventID)),
            timeout: .seconds(1)
        )
        await addTask?.value
    }

    @Test
    func communicationsViewerChannelQueryFiltersAndSortsEventChannels() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcai")
        let announcementsID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let generalID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcao")
        let lateNewsID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcap")
        let otherID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcar")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertCanonicalCategory(db, id: announcementsID, eventID: selectedEventID, name: "Announcements")
            try Self.insertCanonicalCategory(db, id: generalID, eventID: selectedEventID, name: "General")
            try Self.insertCanonicalCategory(db, id: lateNewsID, eventID: selectedEventID, name: "Late News")
            try Self.insertCanonicalCategory(db, id: otherID, eventID: otherEventID, name: "Other")
        }

        let channels = try await database.read { db in
            try CommunicationsViewer.channelsQuery(eventID: selectedEventID).fetchAll(db)
        }

        expectNoDifference(
            channels.map(\.id),
            [
                announcementsID,
                generalID,
                lateNewsID,
            ]
        )
    }


}
