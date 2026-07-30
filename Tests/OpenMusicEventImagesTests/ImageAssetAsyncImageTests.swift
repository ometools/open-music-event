import CustomDump
import OpenMusicEventLexicon
import SwiftUI
import Testing

@testable import OpenMusicEventImages

@MainActor
struct ImageAssetAsyncImageTests {
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
}
