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
        let unavailableLogo = OME.ImageAsset(
            source: .blob(
                ATProto.Blob(
                    ref: "bafkreiunavailablelogo",
                    mimeType: "image/png",
                    size: 1
                )
            ),
            role: .logo,
            renderKind: .transparent,
            materializationPolicy: .lazy
        )
        let titleSources: [HeroImageTitleSource] = [
            .logo(DisplayImageAsset(asset: unavailableLogo)),
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
    func `resolved image location preserves current rendering metadata`() throws {
        let remoteURL = try #require(URL(string: "https://example.com/hero.jpg"))
        var currentAsset = OME.ImageAsset(
            source: .url(remoteURL),
            role: .hero,
            renderKind: .fullImage,
            materializationPolicy: .lazy,
            thumbhash: "current-thumbhash",
            focalPoint: .init(x: 0.2, y: 0.8)
        )

        // The image was resolved before the user changed its focus metadata.
        var resolvedAsset = currentAsset
        resolvedAsset.assetKey = "event|hero"
        resolvedAsset.source = .url(URL(fileURLWithPath: "/tmp/event-hero.jpg"))
        resolvedAsset.thumbhash = "stale-thumbhash"
        resolvedAsset.focalPoint = .init(x: 0.5, y: 0.5)

        // Rendering reuses the resolved file without restoring stale metadata.
        let displayAsset = ImageAssetAsyncImage<EmptyView>.displayAsset(
            asset: currentAsset,
            resolvedAsset: resolvedAsset
        )
        currentAsset.assetKey = resolvedAsset.assetKey
        currentAsset.source = resolvedAsset.source
        expectNoDifference(displayAsset, currentAsset)
    }

    @Test
    func `changing focus does not invalidate image resolution`() throws {
        let remoteURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let asset = OME.ImageAsset(
            source: .url(remoteURL),
            role: .hero,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )
        var focusedAsset = asset
        focusedAsset.focalPoint = .init(x: 0.2, y: 0.8)

        let originalImage = ImageAssetAsyncImage(asset: asset) { EmptyView() }
        let focusedImage = ImageAssetAsyncImage(asset: focusedAsset) { EmptyView() }

        // Focus changes reposition the existing pixels without resolving or decoding them again.
        expectNoDifference(focusedImage.resolutionTaskID, originalImage.resolutionTaskID)
        expectNoDifference(focusedImage.renderingCacheKey, originalImage.renderingCacheKey)
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
        let asset = OME.ImageAsset(
            source: .blob(blob),
            role: .poster,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )
        let view = ImageAssetAsyncImage(
            image: DisplayImageAsset(asset: asset, recordID: recordID)
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
}
