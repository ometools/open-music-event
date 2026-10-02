import Bluesky
import ATProto
import ATProtoTypes
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

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func editContributorSavesChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        _ = try await insertCanonicalContributor(into: database, name: "Old Name")

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.continuousClock = ContinuousClock()
        } operation: {
            TestStore(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(store.state.hasLoadedDraft)
        store.modify {
            $0.form.value.name = " New Name "
            $0.form.value.bio = " Updated bio "
            $0.imageURL = "https://example.com/image.jpg"
            $0.logoURL = " "
            var link = EditableLink()
            link.url = "https://example.com"
            link.title = " Bookings "
            link.description = " Contact the artist "
            link.roleChoice = "contact"
            link.useChoice = "nonEmergency"
            link.platformRawValue = ExternalPlatform.website.rawValue
            $0.form.value.links = [link]
        }

        let submittedValue = store.state.form.value
        let submission = store.send(.saveButtonTapped)
        let save = await store.receive(
            \.formSubmitted,
            .equals(submittedValue),
            timeout: .seconds(1)
        )
        let dismissal = await store.receive(\.saveSucceeded, timeout: .seconds(1))
        await dismissal?.value
        await save?.value
        await submission?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.name == "New Name")
        #expect(contributor.description == "Updated bio")
        let images = (contributor.media ?? []).compactMap { medium -> OME.Image? in
            guard case let .known(.image(image)) = medium else { return nil }
            return image
        }
        #expect(images.count == 1)
        #expect(images.first?.role == .known(.photo))
        #expect(images.first?.displayImageAsset(recordID: eventID)?.url?.absoluteString
            == "https://example.com/image.jpg")
        #expect(contributor.links?.map(\.url.absoluteString) == ["https://example.com"])
        #expect(contributor.links?.map(\.title) == ["Bookings"])
        #expect(contributor.links?.map(\.description) == ["Contact the artist"])
        #expect(contributor.links?.map(\.role) == [
            .known(.contact(.init(use: .known(.nonEmergency))))
        ])
        #expect(contributor.links?.map(\.platform) == [.known(.website)])
    }

    @Test
    func editContributorReordersAndDeletesLinksWithoutChangingUnknownRole() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let unknownRole: Open<OME.Link.Role> = .unknown(.object([
            "$type": "events.example.defs#pressLink",
            "audience": "press",
        ]))
        _ = try await insertCanonicalContributor(
            into: database,
            name: "Artist One",
            links: [
                OME.Link(
                    url: try #require(URL(string: "https://example.com/press")),
                    title: "Press",
                    role: unknownRole
                ),
                OME.Link(
                    url: try #require(URL(string: "https://example.com/shop")),
                    title: "Shop",
                    role: .known(.website(.init()))
                ),
                OME.Link(
                    url: try #require(URL(string: "https://example.com/tickets")),
                    title: "Tickets",
                    role: .known(.tickets(.init()))
                ),
            ]
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.continuousClock = ContinuousClock()
        } operation: {
            TestStore(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(store.state.form.value.links.map(\.title) == ["Press", "Shop", "Tickets"])
        let pressID = store.state.form.value.links[0].id
        let shopID = store.state.form.value.links[1].id
        let ticketsID = store.state.form.value.links[2].id

        await store.send(.editLinkButtonTapped(pressID))?.value
        #expect(store.state.editingLinkID == pressID)
        store.modify { $0.form.value.links[0].title = "Press Kit" }
        await store.send(.moveLinkButtonTapped(ticketsID, -1))?.value
        await store.send(.moveLinkButtonTapped(ticketsID, -1))?.value
        await store.send(.removeLinkButtonTapped(shopID))?.value
        #expect(store.state.form.value.links.map(\.title) == ["Tickets", "Press Kit"])

        let submittedValue = store.state.form.value
        let submission = store.send(.saveButtonTapped)
        let save = await store.receive(
            \.formSubmitted,
            .equals(submittedValue),
            timeout: .seconds(1)
        )
        let dismissal = await store.receive(\.saveSucceeded, timeout: .seconds(1))
        await dismissal?.value
        await save?.value
        await submission?.value

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                ).fetchOne(db)
            )
        }
        #expect(contributor.links?.map(\.title) == ["Tickets", "Press Kit"])
        #expect(contributor.links?.map(\.url.absoluteString) == [
            "https://example.com/tickets",
            "https://example.com/press",
        ])
        #expect(contributor.links?.last?.role == unknownRole)
    }

    @Test
    func editContributorImagePickerImportAddsImageThroughParentDestination() async throws {
        let eventID = canonicalRouteEventID
        let image = ImportImages.Configuration.contributorPhoto.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000c001")!,
            title: "Contributor Photo",
            sourceName: "contributor-photo.png",
            sourceURL: URL(fileURLWithPath: "/tmp/contributor-photo.png"),
            mimeType: "image/png",
            data: Data("contributor-photo".utf8)
        )

        @Bindable var store = Store(initialState: EditContributor.State(eventID: eventID)) {
            EditContributor()
        }

        store.send(.photoImagePicker(.addButtonTapped))
        let importStore = try #require(
            $store.scope(\.destination).photoImportImages.wrappedValue
        )
        importStore.send(.imagesImported([image]))
        await importStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        var selectedImage = image
        selectedImage.image.title = "Contributor Photo"
        expectNoDifference(store.photoImagePicker.images.map(\.importedImage), [selectedImage])
        #expect(store.photoImagePicker.images.first?.image.title == "Contributor Photo")
        #expect(store.logoImagePicker.images.isEmpty)
    }

    @Test
    func editContributorPhotoDetailsSaveThroughParentDestination() async throws {
        let eventID = canonicalRouteEventID
        let imageID = UUID(uuidString: "00000000-0000-0000-0000-00000000c004")!
        let imageURL = try #require(URL(string: "https://example.com/contributor-photo.jpg"))
        let image = ImageAssetPicker.ImageValue(
            id: imageID,
            image: OME.Image(
                source: .known(.url(imageURL)),
                role: .known(.photo)
            )
        )
        var state = EditContributor.State(eventID: eventID)
        state.photoImagePicker.images = [image]

        @Bindable var store = Store(initialState: state) {
            EditContributor()
        }

        store.send(.photoImagePicker(.imageInfoButtonTapped(imageID)))
        @Bindable var imageInfoStore = try #require(
            $store.scope(\.destination).photoImageInfo.wrappedValue
        )
        $imageInfoStore.image.appearance.wrappedValue = .known(.dark)
        $imageInfoStore.title.wrappedValue = "Updated contributor photo"
        await imageInfoStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        expectNoDifference(store.photoImagePicker.images.map(\.image.appearance), [.known(.dark)])
        #expect(store.photoImagePicker.images.first?.image.title == "Updated contributor photo")
        #expect(store.logoImagePicker.images.isEmpty)
    }

    @Test
    func `image picker shows remote URL and local filename`() throws {
        let remoteURL = try #require(
            URL(
                string: "https://wickedwoods.festivalpro.com/?getPublicFile&ENCSTR=qgHiinSYLIbtusbFnwpO"
            )
        )
        let remoteImage = ImageAssetPicker.ImageValue(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000c002"),
            image: OME.Image(
                source: .known(.url(remoteURL)),
                role: .known(.photo)
            )
        )

        // The contributor's remote endpoint keeps its complete URL, including the query.
        expectNoDifference(remoteImage.displaySource, remoteURL.absoluteString)

        let localImage = ImageAssetPicker.ImageValue(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000c003"),
            image: OME.Image(
                source: .known(.url(URL(fileURLWithPath: "/tmp/contributor-photo.png"))),
                role: .known(.photo)
            )
        )

        // A local asset stays concise because its filename identifies it.
        expectNoDifference(localImage.displaySource, "contributor-photo.png")
    }

    @Test
    func editContributorSaveSurfacesUnderlyingError() async throws {
        let database = try defaultDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditContributor.State(contributorID: contributorID, eventID: eventID)
            state.hasLoadedDraft = true
            state.form.value.name = "New Name"

            return TestStore(initialState: state) {
                EditContributor()
            }
        }

        let submittedValue = store.state.form.value
        let submission = store.send(.saveButtonTapped)
        let save = await store.receive(
            \.formSubmitted,
            .equals(submittedValue),
            timeout: .seconds(1)
        )
        let failure = await store.receive(
            \.saveFailed,
            TestStoreMatcher<String>(matching: { $0.hasPrefix("Unable to save contributor: ") }),
            timeout: .seconds(1)
        )
        await failure?.value
        await save?.value
        await submission?.value

        #expect(store.state.isSaving == false)
        #expect(store.isPresented)
        #expect(store.state.errorMessage?.hasPrefix("Unable to save contributor: ") == true)
        #expect(store.state.errorMessage != "Unable to save contributor.")
    }

    @Test
    func editContributorBindingWritesThroughToForm() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        _ = try await insertCanonicalContributor(into: database, name: "Old Name")

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(store.hasLoadedDraft)
        #expect(store.form.value.name == "Old Name")

        // This is the binding used by the editable name field.
        $store.form.value.name.wrappedValue = "New Name"
        #expect(store.form.value.name == "New Name")
    }


}
