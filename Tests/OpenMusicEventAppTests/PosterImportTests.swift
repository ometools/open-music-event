import ATProto
import ATProtoTypes
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventDatabase

@MainActor
struct PosterImportTests {
    @Test
    func importingPostersAppendsEventMediaAndStagesBlobs() async throws {
        let database = try makePreparedDatabase()
        let event = try event(media: [heroImage()])
        try await database.write { try Event.insert { event }.execute($0) }
        let directory = try temporaryDirectoryURL()
        let fileStore = testLocalImageFileStore(directory: directory)

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.localImageFileStore = fileStore
        } operation: {
            Store(initialState: PostersViewer.State(eventID: event.id)) { PostersViewer() }
        }
        var first = ImportImages.Configuration.posters.importedImage(
            title: "Lineup",
            sourceName: "lineup.png",
            mimeType: "image/png",
            data: Data("first poster".utf8)
        )
        first.image.appearance = .known(.dark)
        let second = ImportImages.Configuration.posters.importedImage(
            title: "After Hours",
            sourceName: "after-hours.png",
            mimeType: "image/png",
            data: Data("second poster".utf8)
        )

        // Adding posters keeps the existing event artwork and writes both new images to the Event record.
        store.send(.addButtonTapped)
        let importStore = try #require(store.spawn(\.importImages))
        importStore.send(.imagesImported([first, second]))
        await importStore.send(.saveButtonTapped)?.value

        let saved = try #require(await database.read { try Event.find(event.id).fetchOne($0) })
        let posters = EventPoster.all(in: saved)
        await waitUntil { store.posters.count == 2 }
        expectNoDifference(posters.compactMap(\.displayTitle), ["Lineup", "After Hours"])
        #expect(saved.media?.count == 3)
        #expect(saved.media?.first == heroImage())
        #expect(posters[0].image.appearance == nil)
        #expect(store.spawn(\.importImages) == nil)

        // Each imported image is a staged ATProto blob that the existing image view can display.
        try withDependencies {
            $0.localImageFileStore = fileStore
        } operation: {
            for poster in posters {
                guard case let .known(.blob(blob)) = poster.image.source else {
                    Issue.record("Imported poster did not contain a blob")
                    continue
                }
                let url = try #require(try stagedLocalImageBlobURL(for: blob))
                #expect(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    @Test
    func posterTapOpensDetailAndEditingUpdatesTheEventRecord() async throws {
        let database = try makePreparedDatabase()
        let event = try event(media: [heroImage(), posterImage(title: "Lineup")])
        try await database.write { try Event.insert { event }.execute($0) }
        let posterID = EventPoster.ID(eventID: event.id, mediaIndex: 1)

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: PostersViewer.State(eventID: event.id)) { PostersViewer() }
        }
        await waitUntil { store.posters.count == 1 }
        store.send(.posterButtonTapped(posterID))
        expectNoDifference(store.destination?.posterDetail?.posterID, posterID)

        let editStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditPoster.State(posterID: posterID)) { EditPoster() }
        }
        await waitUntil { editStore.hasLoadedDraft }
        #expect(editStore.imageInfo?.image.title == "Lineup")
        #expect(editStore.imageInfo?.image.alt == nil)
        var editedState = EditPoster.State(posterID: posterID)
        let originalImage = try #require(store.posters.first?.image)
        editedState.originalImage = originalImage
        var imageInfo = ImageInfo.State(image: originalImage, configuration: .posters)
        imageInfo.title = " Updated Lineup "
        imageInfo.alt = " Updated lineup poster "
        imageInfo.image.appearance = .known(.dark)
        imageInfo.image.focalPoint = .init(x: 0.4, y: 0.65)
        editedState.imageInfo = Spawn(imageInfo)
        editedState.hasLoadedDraft = true

        let saveStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: editedState) { EditPoster() }
        }
        await saveStore.send(.saveButtonTapped)?.value

        let saved = try #require(await database.read { try Event.find(event.id).fetchOne($0) })
        let poster = try #require(EventPoster.all(in: saved).first)
        #expect(poster.displayTitle == "Updated Lineup")
        #expect(poster.image.alt?.rawValue == "Updated lineup poster")
        #expect(poster.image.appearance == .known(.dark))
        #expect(poster.image.focalPoint == .init(x: 0.4, y: 0.65))
        #expect(saved.media?.first == heroImage())

        // Clearing the field removes the text alternative from the same poster.
        var clearingState = EditPoster.State(posterID: posterID)
        clearingState.originalImage = poster.image
        var clearingInfo = ImageInfo.State(image: poster.image, configuration: .posters)
        clearingInfo.alt = " \n "
        clearingState.imageInfo = Spawn(clearingInfo)
        clearingState.hasLoadedDraft = true
        let clearStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: clearingState) { EditPoster() }
        }
        await clearStore.send(.saveButtonTapped)?.value

        let cleared = try #require(await database.read { try Event.find(event.id).fetchOne($0) })
        #expect(EventPoster.all(in: cleared).first?.image.alt == nil)
    }

    @Test
    func deletingAPosterPreservesOtherEventMedia() async throws {
        let database = try makePreparedDatabase()
        let event = try event(media: [
            heroImage(),
            posterImage(title: "First"),
            posterImage(title: "Second"),
        ])
        try await database.write { try Event.insert { event }.execute($0) }
        let posterID = EventPoster.ID(eventID: event.id, mediaIndex: 1)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditPoster.State(posterID: posterID)) { EditPoster() }
        }
        await waitUntil { store.hasLoadedDraft }

        // Deleting the first poster removes only that array entry.
        store.send(.deleteButtonTapped)
        #expect(store.destination?.deleteConfirmation != nil)
        await store.send(.destination(.deleteConfirmation(.deleteButtonTapped)))?.value

        let saved = try #require(await database.read { try Event.find(event.id).fetchOne($0) })
        expectNoDifference(EventPoster.all(in: saved).compactMap(\.displayTitle), ["Second"])
        #expect(saved.media?.first == heroImage())
        #expect(store.errorMessage == nil)
    }

    @Test
    func posterImageInfoConfigurationLocksPosterRenderingOptions() {
        let configuration = ImportImages.Configuration.posters.imageInfoConfiguration
        expectNoDifference(configuration.roleOptions(including: .known(.poster)), [.poster])
        expectNoDifference(configuration.renderingModeOptions(including: .known(.original)), [.original])
        #expect(configuration.allowsAppearance)
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    private func event(media: [Open<OME.Media>]) throws -> Event {
        try Event(
            id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
            name: "Test Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver")),
            media: media
        )
    }

    private func heroImage() -> Open<OME.Media> {
        .known(.image(.init(
            source: .known(.url(URL(string: "https://example.com/hero.png")!)),
            role: .known(.hero)
        )))
    }

    private func posterImage(title: String) -> Open<OME.Media> {
        .known(.image(.init(
            source: .known(.url(URL(string: "https://example.com/\(title).png")!)),
            title: title,
            role: .known(.poster)
        )))
    }

    private func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testLocalImageFileStore(directory: URL) -> LocalImageFileStoreClient {
        return LocalImageFileStoreClient(
            existingFileURL: { key, mimeType in
                let url = directory.appending(path: key)
                    .appendingPathExtension(mimeType == "image/png" ? "png" : "jpg")
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            },
            write: { key, data, mimeType in
                let url = directory.appending(path: key)
                    .appendingPathExtension(mimeType == "image/png" ? "png" : "jpg")
                try data.write(to: url, options: .atomic)
                return url
            }
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition was not satisfied", sourceLocation: sourceLocation)
    }
}
