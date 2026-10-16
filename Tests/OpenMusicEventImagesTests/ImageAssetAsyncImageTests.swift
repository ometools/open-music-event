import ATProto
#if canImport(AppKit)
import AppKit
#endif
import CustomDump
import OpenMusicEventLexicon
import SwiftUI
import Testing

@testable import OpenMusicEventImages

@MainActor
struct ImageAssetAsyncImageTests {
    #if canImport(AppKit)
    @Test
    func `unavailable hero logo does not constrain fallback title width`() {
        let unavailableLogo = OME.Image(
            source: .known(.blob(ATProto.Blob(
                ref: "bafkreiunavailablelogo",
                mimeType: "image/png",
                size: 1
            ))),
            role: .known(.logo)
        )
        let titleSources: [HeroImageTitleSource] = [
            .logo(.record(unavailableLogo, nil)),
            .title,
        ]
        let titleSourceChain = HeroImageTitleSourceChain(
            title: Text("Abstrvct Azure"),
            sources: titleSources[...]
        )

        let hostingView = NSHostingView(rootView: titleSourceChain)

        #expect(hostingView.fittingSize.width > 164)
    }
    #endif

    @Test
    func `canonical image display preserves rendering metadata`() throws {
        let remoteURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let image = OME.Image(
            source: .known(.url(remoteURL)),
            role: .known(.hero),
            focalPoint: .init(x: 0.2, y: 0.8)
        )
        let display = try #require(image.displayImageAsset())
        let view = ImageAssetAsyncImage(image: display) { EmptyView() }

        expectNoDifference(display, .record(image, nil))
        expectNoDifference(view.displayURL, remoteURL)
        expectNoDifference(view.recordImage?.focalPoint, .init(x: 0.2, y: 0.8))
        expectNoDifference(view.resolvedContentMode, .fill)
    }

    @Test
    func `changing focus does not invalidate image resolution`() throws {
        let remoteURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let image = OME.Image(
            source: .known(.url(remoteURL)),
            role: .known(.hero)
        )
        var focusedImage = image
        focusedImage.focalPoint = .init(x: 0.2, y: 0.8)

        let originalView = ImageAssetAsyncImage(image: .record(image, nil)) { EmptyView() }
        let focusedView = ImageAssetAsyncImage(image: .record(focusedImage, nil)) { EmptyView() }

        // Focus changes reposition the existing pixels without resolving or decoding them again.
        expectNoDifference(focusedView.resolutionTaskID, originalView.resolutionTaskID)
        expectNoDifference(focusedView.renderingCacheKey, originalView.renderingCacheKey)
    }

    @Test
    func `record blob resolves through its publisher PDS`() throws {
        let recordID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let blob = ATProto.Blob(
            ref: "bafkreieventposter",
            mimeType: "image/png",
            size: 120
        )
        let image = OME.Image(source: .known(.blob(blob)), role: .known(.poster))
        let view = ImageAssetAsyncImage(
            image: image.displayImageAsset(recordID: recordID)
        ) { EmptyView() }
        #expect(view.shouldResolveAsset)
        #expect(view.resolutionTaskID.contains(recordID.description))
        #expect(view.resolutionTaskID.contains(blob.ref.rawValue))

        let url = try ImageAssetAsyncImage<EmptyView>.blobURL(
            recordID: recordID,
            blob: blob,
            host: "pds.ome-auth.test"
        )
        expectNoDifference(
            url.absoluteString,
            "https://pds.ome-auth.test/xrpc/com.atproto.sync.getBlob?did=did:plc:organizer&cid=bafkreieventposter"
        )
    }

    @Test
    func `canonical HTTPS image renders without an Event ID`() throws {
        let url = try #require(URL(string: "https://example.com/actor-avatar.jpg"))
        let image = OME.Image(source: .known(.url(url)), role: .known(.photo))
        let display = try #require(image.displayImageAsset())
        let view = ImageAssetAsyncImage(image: display) { EmptyView() }

        expectNoDifference(display, .record(image, nil))
        expectNoDifference(view.displayURL, url)
        #expect(!view.shouldResolveAsset)
    }

    @Test
    func `canonical site map blob keeps its event identity for image resolution`() throws {
        let recordID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let blob = ATProto.Blob(
            ref: "bafkreieventmap", mimeType: "image/png", size: 120
        )
        let image = OME.Image(
            source: .known(.blob(blob)), role: .known(.siteMap)
        )
        let display = try #require(image.displayImageAsset(recordID: recordID))

        expectNoDifference(display.recordID, recordID)
        expectNoDifference(display, .record(image, recordID))
        expectNoDifference(display.role, .siteMap)

        let view = ImageAssetAsyncImage(image: display) { EmptyView() }
        #expect(view.shouldResolveAsset)
    }

    @Test
    func `canonical contributor keeps photo and logo presentation`() throws {
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let contributorID = try #require(Contributor.ID(
            "at://did:plc:organizer/events.openmusic.contributor/3mrdbziccpcai"
        ))
        var contributor = try Contributor(
            id: contributorID,
            event: eventID,
            name: "The Woods Collective",
            createdAt: "2026-09-01T12:00:00Z"
        )
        let photoURL = try #require(URL(string: "https://example.com/collective-photo.jpg"))
        let logoURL = try #require(URL(string: "https://example.com/collective-logo.png"))
        contributor.media = [
            .known(.image(OME.Image(source: .known(.url(logoURL)), role: .known(.logo)))),
            .known(.image(OME.Image(source: .known(.url(photoURL)), role: .known(.photo)))),
        ]

        let artwork = try #require(contributor.artworkDisplayImage)
        let logo = try #require(contributor.logoDisplayImage)
        expectNoDifference(artwork.url, photoURL)
        expectNoDifference(logo.url, logoURL)
        expectNoDifference(artwork.recordID, eventID)
        expectNoDifference(logo.recordID, eventID)
        expectNoDifference(
            contributor.heroImageSources.map(\.kind),
            [.primaryImage, .logo]
        )
    }
}
