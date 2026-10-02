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
    func `an author saves an emergency comms post to the event database`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
        }

        // The author writes the announcement in the same form opened from the category.
        let store = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommsPostComposer.State(
                    eventID: eventID,
                    categoryID: categoryID,
                    author: author,
                    draft: CommsPostDraft(
                        title: "  Gates are open  ",
                        markdown: "  **Welcome** to Wicked Woods.  "
                    )
                )
            ) {
                CommsPostComposer()
            }
        }

        // Emergency delivery is available because the author owns this event.
        store.modify { $0.draft.delivery = .emergency }
        #expect(store.state.canRequestEmergency)

        await store.send(.saveButtonTapped) {
            $0.isSaving = true
        }?.value
        #expect(store.isPresented == false)

        let posts = try await database.read { db in
            try Social.Post.where { $0.category.eq(categoryID) }.fetchAll(db)
        }
        let post = try #require(posts.first)
        expectNoDifference(posts.count, 1)
        expectNoDifference(post.id.authority, eventID.authority)
        expectNoDifference(post.event, eventID)
        expectNoDifference(post.category, categoryID)
        expectNoDifference(post.title, "Gates are open")
        expectNoDifference(post.text, "**Welcome** to Wicked Woods.")
        expectNoDifference(post.delivery, .known(.emergency))
    }

    @Test
    func `an author edits a canonical post without changing its identity`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: categoryID,
                title: "Gates are open", text: "Welcome to the woods."
            )
        }
        let post = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }

        let editor = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 300)
            $0.defaultDatabase = database
        } operation: {
            @Dependency(\.date) var date
            #expect(date() == Date(timeIntervalSince1970: 300))
            return TestStore(
                initialState: CommsPostComposer.State(
                    post: post, eventID: eventID, author: author
                )
            ) {
                CommsPostComposer()
            }
        }
        editor.modify {
            $0.draft.title = "Gates are open now"
            $0.draft.delivery = .silent
        }
        let save = withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 300)
        } operation: {
            editor.send(.saveButtonTapped) { $0.isSaving = true }
        }
        await save?.value
        #expect(editor.isPresented == false)
        let edited = try await database.read {
            try #require(try Social.Post.find(post.id).fetchOne($0))
        }
        expectNoDifference(edited.id, post.id)
        expectNoDifference(edited.createdAt, post.createdAt)
        expectNoDifference(edited.title, "Gates are open now")
        expectNoDifference(edited.delivery, .known(.silent))
        expectNoDifference(edited.updatedAt, "1970-01-01T00:05:00Z")
    }

    @Test
    func `editing a post preserves an unknown delivery value`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        let author = try #require(DID("did:plc:organizer"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "General")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: categoryID,
                title: "Gates are open", text: "Welcome to the woods."
            )
            var post = try #require(try Social.Post.find(postID).fetchOne(db))
            post.delivery = .unknown(.string("future-priority"))
            try Social.Post.upsert { post }.execute(db)
        }
        let futurePost = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        let futureEditor = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 600)
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommsPostComposer.State(
                    post: futurePost, eventID: eventID, author: author
                )
            ) {
                CommsPostComposer()
            }
        }
        #expect(futureEditor.state.hasUnknownDelivery)
        futureEditor.modify { $0.draft.title = "" }
        await futureEditor.send(.saveButtonTapped) { $0.isSaving = true }?.value
        let cleared = try await database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        #expect(cleared.title == nil)
        #expect(cleared.delivery == .unknown(.string("future-priority")))
    }

    @Test
    func createStageSavesNewCanonicalEventPlace() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let existingID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(
                db, id: existingID, eventID: eventID, name: "Old Meadow"
            )
        }
        let logoURL = try #require(URL(string: "https://example.com/new-logo.png"))
        let heroURL = try #require(URL(string: "https://example.com/new-hero.png"))

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditStage.State(eventID: eventID)
            state.form.value.name = " New Meadow "
            state.category = " workshop "
            state.sortIndex = " 4 "
            state.colorHex = "#123456"
            state.iconName = OME.SemanticIcon.gridOfSquares.rawValue
            state.shortLabel = "NM"
            state.mediaEntries = [
                .init(value: .known(.image(OME.Image(
                    source: .known(.url(logoURL)),
                    role: .known(.logo)
                )))),
                .init(value: .known(.image(OME.Image(
                    source: .known(.url(heroURL)),
                    role: .known(.hero)
                )))),
            ]

            return TestStore(initialState: state) {
                EditStage()
            }
        }

        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let places = try await database.read { db in
            try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
        }
        expectNoDifference(places.count, 2)
        let stage = try #require(places.first { $0.id != existingID })
        #expect(stage.id.authority == eventID.authority)
        #expect(stage.name == "New Meadow")
        #expect(stage.stageUse?.category == "workshop")
        #expect(stage.stageUse?.sortIndex == 4)
        #expect(stage.stageUse?.color?.rawValue == 0x123456)
        #expect(stage.stageUse?.icon == .gridOfSquares)
        #expect(stage.stageUse?.shortLabel == "NM")
        let imageURLs = (stage.media ?? []).compactMap { medium -> URL? in
            guard case let .known(.image(image)) = medium else { return nil }
            return image.displayImageAsset(recordID: eventID)?.url
        }
        expectNoDifference(
            imageURLs.map(\.absoluteString).sorted(),
            ["https://example.com/new-hero.png", "https://example.com/new-logo.png"]
        )
    }

    @Test
    func createStageAddsFirstCanonicalEventPlace() async throws {
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
            var state = EditStage.State(eventID: eventID)
            state.form.value.name = "Meadow Stage"
            return TestStore(initialState: state) {
                EditStage()
            }
        }

        await store.send(.saveButtonTapped)?.value
        await waitUntil { !store.state.isSaving && !store.isPresented }

        let places = try await database.read { db in
            try StagesViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        expectNoDifference(places.map(\.name), ["Meadow Stage"])
        #expect(places.first?.id.authority == eventID.authority)
        #expect(places.first?.stageUse != nil)
    }

    @Test
    func editStageMediaImportAddsImageThroughParentDestination() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let image = ImportImages.Configuration.stagePoster.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000057a6")!,
            title: "Stage Poster",
            sourceName: "stage-poster.png",
            sourceURL: URL(fileURLWithPath: "/tmp/stage-poster.png"),
            mimeType: "image/png",
            data: Data("stage-poster".utf8)
        )

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditStage.State(eventID: eventID)) {
                EditStage()
            }
        }

        store.send(.addImageButtonTapped)
        let importStore = try #require(
            $store.scope(\.destination).importImages.wrappedValue
        )
        importStore.send(.imagesImported([image]))
        await importStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        var selectedImage = image
        selectedImage.image.title = image.trimmedTitle
        expectNoDifference(store.mediaEntries.map(\.importedImage), [selectedImage])
        #expect(store.mediaEntries.first?.imageValue?.image.role == .known(.poster))
    }

    @Test
    func stagesViewerDeleteRemovesEventStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StagesViewer.State(eventID: eventID)) {
                StagesViewer()
            }
        }

        await store.send(.deleteStages([stageID]))?.value

        #expect(store.state.errorMessage == nil)

        let stage = try await database.read { db in
            try StageDetail.stageQuery(
                stageID: stageID,
                eventID: eventID
            )
            .fetchOne(db)
        }
        #expect(stage == nil)
    }

    @Test
    func launchRestoreMountsEventViewer() async throws {
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
        #expect(store.state.root.destination?.eventViewer?.id == eventID)
        expectNoDifference(
            store.state.root.destination?.eventViewer?.pendingScheduleLaunchAction,
            .jumpToCurrentTime
        )
    }

}
