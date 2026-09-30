import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing

@testable import OpenMusicEventDatabase
@testable import OpenMusicEventApp
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
            Store(initialState: PostersViewer.State(eventID: eventID)) {
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
        await waitUntil { store.posters.count == 3 }
        #expect(Set(store.posters.map { $0.id.posterID.rawValue.rawValue }) == ["lineup", "lineup-2", "lineup-3"])
        #expect(Set(posters.map { $0.id.posterID.rawValue.rawValue }) == ["lineup", "lineup-2", "lineup-3"])
        #expect(importedPosters.count == 2)
        #expect(Set(importedPosters.compactMap(\.title)) == ["Lineup"])
        #expect(Set(blobs.map(\.parentLocalID)) == ["lineup-2", "lineup-3"])
        #expect(Set(blobs.map(\.parentKind)) == [.poster])
        #expect(Set(blobs.map(\.role)) == [.poster])
        #expect(Set(importedPosters.map(\.image.role)) == [.poster])
        #expect(Set(blobs.compactMap(\.sourceURL)) == [sourceURL1, sourceURL2])
        #expect(Set(blobs.map(\.data)) == [Data("first-poster".utf8), Data("second-poster".utf8)])
        #expect(importedPosters.first { $0.id.posterID.rawValue.rawValue == "lineup-2" }?.image.appearance == nil)

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
    func `contributor photo focus editing does not require stored geometry`() {
        let photo = OMERecord.ImageAsset(
            source: .url(URL(string: "https://example.com/contributor.jpg")!),
            role: .photo,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )

        // A remote contributor photo exposes Focus before its pixels have loaded.
        let photoState = ImageInfo.State(
            asset: photo,
            configuration: .contributorPhoto
        )
        #expect(photoState.canEditFocusPoint)

        // Transparent artwork still has no focal crop to edit.
        var logo = photo
        logo.renderKind = .transparent
        let logoState = ImageInfo.State(
            asset: logo,
            configuration: .contributorLogo
        )
        #expect(!logoState.canEditFocusPoint)
    }

    @Test
    func importingPosterImageReplacesExistingLocalBlob() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let cacheDirectoryURL = try temporaryDirectoryURL()
        let sourceURL = URL(fileURLWithPath: "/tmp/lineup.png")
        let image = ImportImages.Configuration.posters.importedImage(
            title: "Lineup",
            sourceName: "lineup.png",
            sourceURL: sourceURL,
            mimeType: "image/png",
            data: Data("new-poster".utf8)
        )
        let orphanedBlobKey = LocalImageBlob.assetKey(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            parentKind: .poster,
            parentLocalID: "lineup-2",
            role: .poster
        )

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Existing Lineup",
            eventID: eventID,
            in: database
        )
        try await database.write { db in
            let blobs = [
                LocalImageBlob(
                    assetKey: orphanedBlobKey,
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    parentKind: .poster,
                    parentLocalID: "lineup-2",
                    role: .poster,
                    renderKind: .fullImage,
                    mimeType: "image/png",
                    data: Data("old-poster".utf8),
                    sourceURL: nil,
                    lastFetchedAt: Date(timeIntervalSince1970: 1)
                )
            ]
            try LocalImageBlob.insert {
                blobs
            }
            .execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 2)
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.localImageFileStore = testLocalImageFileStore(directory: cacheDirectoryURL)
        } operation: {
            Store(initialState: PostersViewer.State(eventID: eventID)) {
                PostersViewer()
            }
        }

        store.send(.addButtonTapped)
        let importStore = try #require(store.spawn(\.importImages))
        importStore.send(.imagesImported([image]))
        await importStore.send(.saveButtonTapped)?.value

        let poster = try #require(await database.read { db in
            try OMERecord.Poster
                .where { $0.id.posterID.eq(Self.localPosterID("lineup-2")) }
                .fetchOne(db)
        })
        let blob = try #require(await database.read { db in
            try LocalImageBlob.find(orphanedBlobKey).fetchOne(db)
        })

        #expect(poster.title == "Lineup")
        expectNoDifference(blob.data, Data("new-poster".utf8))
        expectNoDifference(blob.sourceURL, sourceURL)
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
        @Bindable var store = Store(
            initialState: ImportImages.State(
                configuration: .posters,
                images: [importedImage]
            )
        ) {
            ImportImages { _ in }
        }

        store.send(.imageInfoButtonTapped(imageID))
        @Bindable var imageInfoStore = try #require(
            $store.scope(\.destination).imageInfo.wrappedValue
        )
        $imageInfoStore.asset.appearance.wrappedValue = .dark
        $imageInfoStore.asset.focalPoint.wrappedValue = OMERecord.ImageAsset.FocalPoint(
            x: 0.4,
            y: 0.65
        )

        await imageInfoStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        let updatedImage = try #require(store.images.first)
        expectNoDifference(updatedImage.localImageImportRequest.appearance, .dark)
        expectNoDifference(
            updatedImage.localImageImportRequest.focalPoint,
            OMERecord.ImageAsset.FocalPoint(x: 0.4, y: 0.65)
        )
    }

    @Test
    func importImagesSaveNormalizesLoneAppearanceAsStandard() async throws {
        var image = ImportImages.Configuration.posters.importedImage(
            title: "Night Poster",
            sourceName: "night-poster.png",
            sourceURL: URL(fileURLWithPath: "/tmp/night-poster.png"),
            mimeType: "image/png",
            data: Data("night-poster".utf8)
        )
        image.asset.appearance = .dark
        let savedImages = SavedImportedImages()

        let store = Store(
            initialState: ImportImages.State(
                configuration: .posters,
                images: [image]
            )
        ) {
            ImportImages { images in
                await savedImages.setValue(images)
            }
        }

        await store.send(.saveButtonTapped)?.value

        let savedImage = try #require(await savedImages.value?.first)
        expectNoDifference(savedImage.asset.appearance, nil)
        expectNoDifference(savedImage.localImageImportRequest.appearance, nil)
    }

    @Test
    func importImagesSaveKeepsPairedAppearances() async throws {
        var lightImage = ImportImages.Configuration.posters.importedImage(
            title: "Day Poster",
            sourceName: "day-poster.png",
            sourceURL: URL(fileURLWithPath: "/tmp/day-poster.png"),
            mimeType: "image/png",
            data: Data("day-poster".utf8)
        )
        lightImage.asset.appearance = .light
        var darkImage = ImportImages.Configuration.posters.importedImage(
            title: "Night Poster",
            sourceName: "night-poster.png",
            sourceURL: URL(fileURLWithPath: "/tmp/night-poster.png"),
            mimeType: "image/png",
            data: Data("night-poster".utf8)
        )
        darkImage.asset.appearance = .dark
        let savedImages = SavedImportedImages()

        let store = Store(
            initialState: ImportImages.State(
                configuration: .posters,
                images: [lightImage, darkImage]
            )
        ) {
            ImportImages { images in
                await savedImages.setValue(images)
            }
        }

        await store.send(.saveButtonTapped)?.value

        let images = try #require(await savedImages.value)
        expectNoDifference(images.map(\.asset.appearance), [.light, .dark])
        expectNoDifference(images.map(\.localImageImportRequest.appearance), [.light, .dark])
    }

    @Test
    func imageAssetPickerMaterializationNormalizesLoneAppearanceAsStandard() throws {
        let eventID = eventID("event-1")
        let posterID = OMERecord.Poster.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            posterID: Self.localPosterID("lineup")
        )
        let asset = OMERecord.ImageAsset(
            source: .url(try #require(URL(string: "https://example.com/poster.png"))),
            role: .poster,
            renderKind: .fullImage,
            appearance: .dark,
            materializationPolicy: .lazy,
            focalPoint: OMERecord.ImageAsset.FocalPoint(x: 0.4, y: 0.65)
        )

        let preparedImages = try withDependencies {
            $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000317")!)
        } operation: {
            try ImageAssetPicker.State.materializedImages(
                [ImageAssetPicker.ImageValue(asset: asset)],
                context: .init(posterID: posterID)
            )
        }

        expectNoDifference(preparedImages.images.map(\.appearance), [nil])
        expectNoDifference(preparedImages.images.map(\.focalPoint), [asset.focalPoint])
    }

    @Test
    func posterTapOpensPosterDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Lineup",
            eventID: eventID,
            in: database
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: PostersViewer.State(eventID: eventID)) {
                PostersViewer()
            }
        }
        let posterID = OMERecord.Poster.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            posterID: Self.localPosterID("lineup")
        )

        store.send(.posterButtonTapped(posterID))

        expectNoDifference(store.destination?.posterDetail?.posterID, posterID)
    }

    @Test
    func posterDetailEditButtonOpensEditPoster() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Lineup",
            eventID: eventID,
            in: database
        )
        let posterID = OMERecord.Poster.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            posterID: Self.localPosterID("lineup")
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: PosterDetail.State(posterID: posterID)) {
                PosterDetail()
            }
        }

        store.send(.editButtonTapped)

        expectNoDifference(store.destination?.editPoster?.posterID, posterID)
    }

    @Test
    func deletingPosterFromDetailDismissesDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Lineup",
            eventID: eventID,
            in: database
        )

        let poster = try #require(await database.read { db in
            try OMERecord.Poster.fetchOne(db)
        })
        let blobKey = try await seedLocalImageBlob(
            posterID: poster.id,
            data: Data("poster".utf8),
            in: database
        )
        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: PostersViewer.State(eventID: eventID)) {
                PostersViewer()
            }
        }

        await waitUntil { store.posters.count == 1 }
        store.send(.posterButtonTapped(poster.id))
        let detail = try #require(
            $store.scope(\.destination).posterDetail.wrappedValue
        )
        @Bindable var detailStore = detail
        detailStore.send(.editButtonTapped)
        let editStore = try #require(
            $detailStore.scope(\.destination).editPoster.wrappedValue
        )

        await waitUntil { editStore.hasLoadedDraft }
        editStore.send(.deleteButtonTapped)
        await editStore.send(.destination(.deleteConfirmation(.deleteButtonTapped)))?.value
        await waitUntil { store.destination == nil }
        await waitUntil { store.posters.isEmpty }

        let deletedBlob = try await database.read { db in
            try LocalImageBlob.find(blobKey).fetchOne(db)
        }
        #expect(deletedBlob == nil)
    }

    @Test
    func editPosterImageInfoUpdatesDraftAsset() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Lineup",
            eventID: eventID,
            in: database
        )

        let poster = try #require(await database.read { db in
            try OMERecord.Poster.fetchOne(db)
        })
        var editedAsset = poster.image
        editedAsset.appearance = .dark
        editedAsset.focalPoint = OMERecord.ImageAsset.FocalPoint(x: 0.4, y: 0.65)
        var expectedAsset = editedAsset
        expectedAsset.appearance = nil

        var state = EditPoster.State(
            posterID: poster.id,
            imageInfo: Spawn(
                ImageInfo.State(
                    asset: editedAsset,
                    configuration: .posters,
                    sourceLabel: "Lineup"
                )
            )
        )
        state.title = "Lineup"
        state.hasLoadedDraft = true

        let draft = try state.preparedDraft()

        expectNoDifference(draft.image, expectedAsset)
    }

    @Test
    func savingEditPosterUpdatesTitleAndImageAsset() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Lineup",
            eventID: eventID,
            in: database
        )

        let poster = try #require(await database.read { db in
            try OMERecord.Poster.fetchOne(db)
        })
        var editedAsset = poster.image
        editedAsset.appearance = .dark
        editedAsset.focalPoint = OMERecord.ImageAsset.FocalPoint(x: 0.4, y: 0.65)
        var expectedAsset = editedAsset
        expectedAsset.appearance = nil

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = EditPoster.State(posterID: poster.id)
            state.title = " Updated Lineup "
            state.imageInfo = Spawn(
                ImageInfo.State(
                    asset: editedAsset,
                    configuration: .posters,
                    sourceLabel: "Lineup"
                )
            )
            state.hasLoadedDraft = true

            return Store(initialState: state) {
                EditPoster()
            }
        }

        await store.send(.saveButtonTapped)?.value

        let updatedPoster = try #require(await database.read { db in
            try OMERecord.Poster.fetchOne(db)
        })
        expectNoDifference(updatedPoster.title, "Updated Lineup")
        expectNoDifference(updatedPoster.image, expectedAsset)
        #expect(store.isPresented == false)
    }

    @Test
    func mountedEditPosterLoadsAndSavesDraft() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Lineup",
            eventID: eventID,
            in: database
        )

        let poster = try #require(await database.read { db in
            try OMERecord.Poster.fetchOne(db)
        })
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: EditPoster.State(posterID: poster.id)) {
                EditPoster()
            }
        }

        await waitUntil { store.hasLoadedDraft }
        #expect(store.title == "Lineup")

        await store.send(.saveButtonTapped)?.value

        let updatedPoster = try #require(await database.read { db in
            try OMERecord.Poster.fetchOne(db)
        })
        expectNoDifference(updatedPoster.title, "Lineup")
        #expect(store.isPresented == false)
    }

    @Test
    func deletingPosterRemovesPosterAndLocalBlob() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await seedEvent(eventID, in: database)
        try await seedPoster(
            posterID: "lineup",
            title: "Lineup",
            eventID: eventID,
            in: database
        )

        let poster = try #require(await database.read { db in
            try OMERecord.Poster.fetchOne(db)
        })
        let blobKey = try await seedLocalImageBlob(
            posterID: poster.id,
            data: Data("poster".utf8),
            in: database
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = EditPoster.State(posterID: poster.id)
            state.title = "Lineup"
            state.imageInfo = Spawn(
                ImageInfo.State(
                    asset: poster.image,
                    configuration: .posters,
                    sourceLabel: "Lineup"
                )
            )
            state.hasLoadedDraft = true

            return Store(initialState: state) {
                EditPoster()
            }
        }

        store.send(.deleteButtonTapped)

        #expect(store.destination?.deleteConfirmation != nil)

        await store.send(.destination(.deleteConfirmation(.deleteButtonTapped)))?.value

        let deletedPoster = try await database.read { db in
            try PostersViewer.posterQuery(posterID: poster.id)
                .fetchOne(db)
        }
        let deletedBlob = try await database.read { db in
            try LocalImageBlob.find(blobKey).fetchOne(db)
        }
        #expect(deletedPoster == nil)
        #expect(deletedBlob == nil)
        #expect(store.errorMessage == nil)
        #expect(store.isDeleting == false)
        #expect(store.isPresented == false)
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

    @Test
    func importImagesSaveShowsUnderlyingError() async throws {
        let image = ImportImages.Configuration.posters.importedImage(
            title: "Lineup",
            sourceName: "lineup.png",
            sourceURL: URL(fileURLWithPath: "/tmp/lineup.png"),
            mimeType: "image/png",
            data: Data("poster".utf8)
        )
        let store = Store(
            initialState: ImportImages.State(
                configuration: .posters,
                images: [image]
            )
        ) {
            ImportImages { _ in
                throw PosterImportSaveError.failed
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.errorMessage == "Unable to import images: Test poster import save failed.")
        #expect(store.isSaving == false)
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
                    contactNumbers: nil
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

    private func seedLocalImageBlob(
        posterID: OMERecord.Poster.ID,
        data: Data,
        in database: any DatabaseWriter
    ) async throws -> String {
        let assetKey = LocalImageBlob.assetKey(
            organizerID: posterID.organizerID,
            eventID: posterID.eventID,
            parentKind: .poster,
            parentLocalID: posterID.posterID.rawValue.rawValue,
            role: .poster
        )
        try await database.write { db in
            try LocalImageBlob.insert {
                [
                    LocalImageBlob(
                        assetKey: assetKey,
                        organizerID: posterID.organizerID,
                        eventID: posterID.eventID,
                        parentKind: .poster,
                        parentLocalID: posterID.posterID.rawValue.rawValue,
                        role: .poster,
                        renderKind: .fullImage,
                        mimeType: "image/png",
                        data: data,
                        sourceURL: URL(fileURLWithPath: "/tmp/\(posterID.posterID.rawValue.rawValue).png"),
                        lastFetchedAt: Date(timeIntervalSince1970: 1)
                    )
                ]
            }
            .execute(db)
        }
        return assetKey
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

private actor SavedImportedImages {
    var value: [ImportImages.ImportedImage]?

    func setValue(_ value: [ImportImages.ImportedImage]) {
        self.value = value
    }
}

private enum PosterImportSaveError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Test poster import save failed."
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
