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
    func persistentStageMediaRowsCanBeAddedReorderedEditedAndDeleted() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        let createStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageForm.State(eventID: eventID)) { StageForm() }
        }
        createStore.modify { $0.form.value.name = "Meadow Stage" }
        await createStore.send(.addExternalMediaButtonTapped)?.value
        createStore.modify {
            $0.mediaDraft?.uri = "https://example.com/stage-video"
            $0.mediaDraft?.title = "Stage Video"
        }
        await createStore.send(.mediaDraftSaveButtonTapped)?.value
        await createStore.send(.addRecordMediaButtonTapped)?.value
        createStore.modify {
            $0.mediaDraft?.uri = "at://did:web:example.com/app.bsky.feed.post/3mrdbziccpcy"
        }
        await createStore.send(.mediaDraftSaveButtonTapped)?.value
        let recordRowID = try #require(createStore.state.additionalMediaEntries.last?.id)
        await createStore.send(.mediaMoveButtonTapped(recordRowID, -1))?.value
        await createStore.send(.saveButtonTapped)?.value
        await waitUntil { !createStore.state.isSaving && !createStore.isPresented }

        let created = try await database.read { db in
            try #require(try Stage.all.fetchOne(db))
        }
        #expect(created.media?.count == 2)
        guard case .some(.known(.record)) = created.media?.first else {
            Issue.record("Expected reordered AT Protocol media first")
            return
        }

        let editStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageForm.State(stageID: created.id, eventID: eventID)) {
                StageForm()
            }
        }
        let rows = editStore.state.additionalMediaEntries
        #expect(rows.count == 2)
        await editStore.send(.mediaDeleteButtonTapped(try #require(rows.first?.id)))?.value
        await editStore.send(.mediaEditButtonTapped(try #require(rows.last?.id)))?.value
        editStore.modify { $0.mediaDraft?.title = "Updated Stage Video" }
        await editStore.send(.mediaDraftSaveButtonTapped)?.value
        await editStore.send(.saveButtonTapped)?.value
        await waitUntil { !editStore.state.isSaving && !editStore.isPresented }

        let updated = try await database.read { db in
            try #require(try Stage.find(created.id).fetchOne(db))
        }
        #expect(updated.media?.count == 1)
        guard case let .some(.known(.external(external))) = updated.media?.first else {
            Issue.record("Expected the edited external media to remain")
            return
        }
        #expect(external.title == "Updated Stage Video")
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
