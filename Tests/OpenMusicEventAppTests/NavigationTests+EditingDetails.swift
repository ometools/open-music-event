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
            TestStore(initialState: ContributorForm.State(eventID: eventID)) {
                ContributorForm()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented)
        #expect(
            store.state.form.validation[AnyHashable(\ContributorForm.FormValue.name)]?.errors.map(\.message)
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
            TestStore(initialState: EventPlaceDetail.State(stageID: stageID, eventID: eventID)) {
                EventPlaceDetail()
            }
        }

        let editTask = store.send(.editButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.editPlace(eventID: eventID, placeID: stageID)),
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
        let addedLineupID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaz")
        let persistentStageID = canonicalRouteRecordID("events.openmusic.stage", "3mrdbziccpcay")
        let posterURL = try #require(URL(string: "https://example.com/poster.png"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            let persistentStage = try OpenMusicEventLexicon.Stage(
                id: persistentStageID,
                name: "Meadow Stage",
                createdAt: "2026-09-01T12:00:00Z"
            )
            try OpenMusicEventLexicon.Stage.insert { persistentStage }.execute(db)
            let addedContributor = try Contributor(
                id: addedLineupID,
                event: eventID,
                name: "New Performer",
                createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { addedContributor }.execute(db)
            var place = try EventPlace(
                id: stageID,
                event: eventID,
                name: "Old Meadow",
                createdAt: "2026-09-01T12:00:00Z"
            )
            var stageUse = EventPlace.Kind.Stage()
            stageUse.lineup = [lineupID]
            place.kind = .known(.stage(stageUse))
            place.description = "Old directions"
            place.locators = [.known(.address(Event.Address(country: "CA")))]
            place.links = [OME.Link(url: try #require(URL(string: "https://example.com/old")))]
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
            TestStore(initialState: EventPlaceForm.State(stageID: stageID, eventID: eventID)) {
                EventPlaceForm()
            }
        }

        #expect(store.state.hasLoadedDraft)
        #expect(store.state.form.value.name == "Old Meadow")
        await store.send(.linkPersistentStageTapped(persistentStageID))?.value
        await store.send(.addLineupContributorTapped(addedLineupID))?.value
        await store.send(.moveLineupContributorTapped(addedLineupID, -1))?.value
        let logo = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/logo.png")))),
            role: .known(.logo)
        )
        let hero = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/hero.png")))),
            role: .known(.hero)
        )
        store.modify {
            $0.form.value.name = " New Meadow "
            $0.form.value.description = " New directions "
            $0.form.value.locators[0].street = "Forest Road"
            $0.form.value.links[0].url = "https://example.com/new"
            $0.category = " workshop "
            $0.sortIndex = " 7 "
            $0.colorHex = " #AABBCC "
            $0.iconName = "sparkles"
            $0.shortLabel = " MD "
            $0.mediaEntries.append(.init(value: .known(.image(logo))))
            $0.mediaEntries.append(.init(value: .known(.image(hero))))
        }

        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let stage = try await database.read { db in
            try #require(
                try EventPlaceDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(stage.name == "New Meadow")
        #expect(stage.description == "New directions")
        guard case let .known(.address(address)) = try #require(stage.locators?.first) else {
            Issue.record("Expected an address locator")
            return
        }
        #expect(address.street == "Forest Road")
        #expect(stage.links?.first?.url.absoluteString == "https://example.com/new")
        #expect(stage.stageUse?.category == "workshop")
        #expect(stage.stageUse?.sortIndex == 7)
        #expect(stage.stageUse?.color?.rawValue == 0xAABBCC)
        #expect(stage.stageUse?.icon?.rawValue == "sparkles")
        #expect(stage.stageUse?.shortLabel == "MD")
        #expect(stage.stageUse?.stage == persistentStageID)
        #expect(stage.stageUse?.lineup == [addedLineupID, lineupID])
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
    func editStageMediaLinksCanBeEditedRemovedAndReordered() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let logo = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/logo.png")))),
            role: .known(.logo)
        )
        let external = OME.Media.External(
            uri: try #require(URL(string: "https://example.com/old-video")),
            title: "Old video"
        )
        let oldRecord = OME.Media.RecordReference(
            uri: try #require(ATProto.URI("at://did:plc:organizer/app.bsky.feed.post/old"))
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            var place = try EventPlace(
                id: stageID,
                event: eventID,
                name: "Meadow",
                createdAt: "2026-09-01T12:00:00Z"
            )
            place.kind = .known(.stage(.init()))
            place.media = [
                .known(.image(logo)),
                .known(.external(external)),
                .known(.record(oldRecord)),
            ]
            try EventPlace.insert { place }.execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventPlaceForm.State(stageID: stageID, eventID: eventID)) {
                EventPlaceForm()
            }
        }
        #expect(store.state.mediaEntries.count == 3)
        let externalID = try #require(store.state.mediaEntries.dropFirst().first?.id)
        let oldRecordID = try #require(store.state.mediaEntries.last?.id)
        store.send(.mediaEditButtonTapped(externalID))
        store.send(.mediaDraftURIChanged("https://example.com/live-video"))
        store.send(.mediaDraftTitleChanged("Live video"))
        store.send(.mediaDraftSaveButtonTapped)
        store.send(.mediaDeleteButtonTapped(oldRecordID))
        store.send(.addRecordMediaButtonTapped)
        store.send(.mediaDraftURIChanged("at://did:plc:organizer/app.bsky.feed.post/new"))
        store.send(.mediaDraftSaveButtonTapped)
        let newRecordID = try #require(store.state.mediaEntries.last?.id)
        store.send(.mediaMoveButtonTapped(newRecordID, -1))
        store.send(.mediaMoveButtonTapped(newRecordID, -1))
        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        let edited = try await database.read { db in
            try #require(try EventPlace.find(stageID).fetchOne(db))
        }
        let newRecordURI = try #require(ATProto.URI("at://did:plc:organizer/app.bsky.feed.post/new"))
        let liveVideoURL = try #require(URL(string: "https://example.com/live-video"))
        #expect(edited.media == [
            .known(.record(OME.Media.RecordReference(uri: newRecordURI))),
            .known(.image(logo)),
            .known(.external(OME.Media.External(uri: liveVideoURL, title: "Live video"))),
        ])
    }

    @Test
    func eventPlaceListAddButtonEmitsCreateStageEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventPlaceList.State(eventID: eventID)) {
                EventPlaceList()
            }
        }

        let addTask = store.send(.addButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.createPlace(eventID)),
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
            try SocialCategoryList.channelsQuery(eventID: selectedEventID).fetchAll(db)
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
