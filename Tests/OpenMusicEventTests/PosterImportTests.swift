import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventDatabase
import SQLiteData
import Testing

@testable import OpenMusicEvent
@testable import OpenMusicEventAppEventViewer

@MainActor
struct PosterImportTests {
    @Test
    func importingMultiplePosterImagesCreatesPostersAndLocalBlobs() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let sourceURL1 = URL(fileURLWithPath: "/tmp/lineup.png")
        let sourceURL2 = URL(fileURLWithPath: "/tmp/lineup-copy.jpg")
        let importConfiguration = ImportImages.Configuration.posters

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Existing Lineup",
            eventID: eventID,
            in: database
        )

        let store = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 1_000)
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            Store(initialState: PostersViewer.State(eventID: eventID, database: database)) {
                PostersViewer()
            }
        }
        var firstImage = importConfiguration.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Lineup",
            sourceName: "lineup.png",
            sourceURL: sourceURL1,
            mimeType: "image/png",
            data: Data("first-poster".utf8)
        )
        firstImage.asset.appearance = .dark
        let secondImage = importConfiguration.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Lineup",
            sourceName: "lineup-copy.jpg",
            sourceURL: sourceURL2,
            mimeType: "image/jpeg",
            data: Data("second-poster".utf8)
        )

        store.send(.addButtonTapped)
        let importStore = try #require(store.spawn(\.importImages))
        importStore.send(.imagesImported([firstImage, secondImage]))
        await importStore.send(.saveButtonTapped)?.value

        let posters = try await database.read { db in
            try OMERecord.Poster.fetchAll(db)
        }
        let blobs = try await database.read { db in
            try LocalImageBlob.fetchAll(db)
        }
        let importedPosters = posters.filter { $0.id.posterID.rawValue.rawValue != "lineup" }

        #expect(store.spawn(\.importImages) == nil)
        #expect(Set(posters.map { $0.id.posterID.rawValue.rawValue }) == ["lineup", "lineup-2", "lineup-3"])
        #expect(importedPosters.count == 2)
        #expect(Set(importedPosters.compactMap(\.title)) == ["Lineup"])
        #expect(Set(blobs.map(\.parentLocalID)) == ["lineup-2", "lineup-3"])
        #expect(Set(blobs.map(\.parentKind)) == [.poster])
        #expect(Set(blobs.map(\.role)) == [.poster])
        #expect(Set(importedPosters.map(\.image.role)) == [.poster])
        #expect(Set(blobs.compactMap(\.sourceURL)) == [sourceURL1, sourceURL2])
        #expect(Set(blobs.map(\.data)) == [Data("first-poster".utf8), Data("second-poster".utf8)])
        #expect(importedPosters.first { $0.id.posterID.rawValue.rawValue == "lineup-2" }?.image.appearance == .dark)

        for poster in importedPosters {
            let fileURL = try #require(poster.image.url)
            #expect(fileURL.isFileURL)
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    @Test
    func posterImageInfoConfigurationLocksPosterRenderingOptions() {
        let configuration = ImportImages.Configuration.posters.imageInfoConfiguration

        expectNoDifference(configuration.roleOptions(including: .poster), [.poster])
        expectNoDifference(configuration.renderKindOptions(including: .fullImage), [.fullImage])
        expectNoDifference(configuration.allowedMaterializationPolicies, [.lazy])
        #expect(configuration.allowsAppearance)
        #expect(!configuration.allowsMaterializationPolicy)
    }

    @Test
    func editingPosterImageInfoUpdatesImportedAsset() async throws {
        let imageID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let importedImage = ImportImages.Configuration.posters.importedImage(
            id: imageID,
            title: "Night Poster",
            sourceName: "night-poster.png",
            sourceURL: URL(fileURLWithPath: "/tmp/night-poster.png"),
            mimeType: "image/png",
            data: Data("night-poster".utf8)
        )
        var editedAsset = importedImage.asset
        editedAsset.appearance = .dark

        let store = Store(
            initialState: ImportImages.State(
                configuration: .posters,
                imageInfo: Spawn(
                    ImageInfo.State(
                        id: imageID,
                        asset: editedAsset,
                        configuration: .posters,
                        sourceLabel: importedImage.sourceLabel
                    )
                ),
                images: [importedImage]
            )
        ) {
            ImportImages { _ in }
        }
        let imageInfoStore = try #require(store.spawn(\.imageInfo))

        await imageInfoStore.send(.saveButtonTapped)?.value

        let updatedImage = try #require(store.images.first)
        expectNoDifference(updatedImage.asset, editedAsset)
        expectNoDifference(updatedImage.localImageImportRequest.appearance, .dark)
        #expect(store.spawn(\.imageInfo) == nil)
    }

    @Test
    func importImagesDoesNotSaveWithoutImages() {
        let store = Store(initialState: ImportImages.State(configuration: .posters)) {
            ImportImages { _ in }
        }

        #expect(store.canSave == false)
        store.send(.saveButtonTapped)
        #expect(store.canSave == false)
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

    private func seedEvent(
        _ eventID: OMERecord.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OMERecord.Event.insert {
                OMERecord.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone.current,
                    imageURL: nil,
                    iconImageURL: nil,
                    siteMapImageURL: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
        }
    }

    private func seedPoster(
        posterID: String,
        title: String,
        eventID: OMERecord.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        let imageURL = try #require(URL(string: "https://example.com/\(posterID).png"))

        try await database.write { db in
            try OMERecord.Poster.insert {
                OMERecord.Poster.Draft(
                    id: OMERecord.Poster.ID(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        posterID: Self.localPosterID(posterID)
                    ),
                    title: title,
                    imageURL: imageURL
                )
            }
            .execute(db)
        }
    }

    private func eventID(_ string: String) -> OMERecord.Event.ID {
        OMERecord.Event.ID(
            organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
            eventID: OMERecord.ID<OMERecord.Event>(.init(string))
        )
    }

    private nonisolated static func localPosterID(_ string: String) -> OMERecord.ID<OMERecord.Poster> {
        OMERecord.ID<OMERecord.Poster>(.init(string))
    }

    private func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testLocalImageFileStore(directory: URL) -> LocalImageFileStoreClient {
        LocalImageFileStoreClient { assetKey, data, mimeType in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory
                .appending(path: assetKey.fileSafeComponent)
                .appendingPathExtension(mimeType.fileExtension)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
    }
}

private extension String {
    var fileSafeComponent: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? UUID().uuidString
    }

    var fileExtension: String {
        switch self {
        case "image/png":
            return "png"
        case "image/jpeg":
            return "jpg"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        case "image/svg+xml":
            return "svg"
        default:
            return "bin"
        }
    }
}
