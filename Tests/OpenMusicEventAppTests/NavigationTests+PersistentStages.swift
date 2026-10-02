import ATProto
import Clocks
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Observation
import SQLiteData
import Testing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

extension NavigationTests {
    @Test
    func createPersistentStageProfileSavesCanonicalFields() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageForm.State(eventID: eventID)) {
                StageForm()
            }
        }
        var link = EditableLink()
        link.title = "Stage website"
        link.url = "https://example.com/stage"
        store.modify {
            $0.form.value.name = " Meadow Stage "
            $0.form.value.description = " Under the trees "
            $0.form.value.links = [link]
            $0.logoImagePicker.replaceURLString("https://example.com/stage-logo.png")
        }

        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        let stage = try await database.read { db in
            try #require(try Stage.all.fetchOne(db))
        }
        #expect(stage.id.authority == eventID.authority)
        #expect(stage.name == "Meadow Stage")
        #expect(stage.description == "Under the trees")
        #expect(stage.links?.first?.url.absoluteString == "https://example.com/stage")
        #expect(stage.media?.compactMap { medium -> String? in
            guard case let .known(.image(image)) = medium else { return nil }
            return image.displayImageAsset(recordID: eventID)?.url?.absoluteString
        } == ["https://example.com/stage-logo.png"])
    }

    @Test
    func editPersistentStageProfileAndDeleteUnlinkedRecord() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.stage", "3mrdbziccpcaz")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            let stage = try Stage(
                id: stageID,
                name: "Old Stage",
                createdAt: "2026-09-01T12:00:00Z"
            )
            try Stage.insert { stage }.execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageForm.State(stageID: stageID, eventID: eventID)) {
                StageForm()
            }
        }
        #expect(store.state.hasLoadedDraft)
        store.modify {
            $0.form.value.name = "New Stage"
            $0.form.value.description = "A new description"
        }
        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        let updated = try await database.read { db in
            try #require(try Stage.find(stageID).fetchOne(db))
        }
        #expect(updated.name == "New Stage")
        #expect(updated.description == "A new description")
        #expect(updated.createdAt.rawValue == "2026-09-01T12:00:00Z")

        let deleteStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageForm.State(stageID: stageID, eventID: eventID)) {
                StageForm()
            }
        }
        await deleteStore.send(.deleteButtonTapped)?.value
        #expect(deleteStore.state.showsDeleteConfirmation)
        await deleteStore.send(.deleteConfirmed)?.value
        await waitUntil { !deleteStore.state.isSaving && !deleteStore.isPresented }
        #expect(try await database.read { try Stage.find(stageID).fetchOne($0) } == nil)
    }

    @Test
    func creatingStageProfileFromEventStageLinksTheNewRecord() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EventPlaceForm.State(eventID: eventID)) {
                EventPlaceForm()
            }
        }
        store.send(.createPersistentStageTapped)
        @Bindable var profileStore = try #require(
            $store.scope(\.destination).persistentStageEditor.wrappedValue
        )
        $profileStore.form.value.name.wrappedValue = "Meadow Profile"
        await profileStore.send(.saveButtonTapped)?.value

        await waitUntil { store.form.value.persistentStageID != nil }
        let linkedID = try #require(store.form.value.persistentStageID)
        let profile = try await database.read { db in
            try #require(try Stage.find(linkedID).fetchOne(db))
        }
        #expect(profile.name == "Meadow Profile")
    }
}
