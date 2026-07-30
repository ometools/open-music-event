import OpenMusicEventDatabase
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct DisplayImageAsset: Equatable, Sendable {
    public init(
        asset: OME.ImageAsset,
        cacheContext: LocalImageCacheContext? = nil
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
    }

    public var asset: OME.ImageAsset
    public var cacheContext: LocalImageCacheContext?
}

public struct HeroImageSource: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case primaryImage
        case logo
    }

    public init(_ kind: Kind, image: DisplayImageAsset) {
        self.kind = kind
        self.image = image
    }

    public var kind: Kind
    public var image: DisplayImageAsset
}

public extension HeroImageSource {
    static func primaryImage(_ image: DisplayImageAsset) -> Self {
        Self(.primaryImage, image: image)
    }

    static func logo(_ image: DisplayImageAsset) -> Self {
        Self(.logo, image: image)
    }
}

public enum HeroImageTitleSource: Equatable, Sendable {
    case logo(DisplayImageAsset)
    case title
}

public extension Collection where Element == HeroImageTitleSource {
    var containsLogo: Bool {
        contains {
            if case .logo = $0 {
                return true
            }
            return false
        }
    }
}

public enum HeroImageRenderer: Equatable, Sendable {
    case fullBleedImage
    case centeredLogo
}

public struct HeroImageRendering: Sendable {
    public init(
        rendererForSource: @escaping @Sendable (HeroImageSource.Kind) -> HeroImageRenderer
    ) {
        self.rendererForSource = rendererForSource
    }

    public var rendererForSource: @Sendable (HeroImageSource.Kind) -> HeroImageRenderer

    public func renderer(for kind: HeroImageSource.Kind) -> HeroImageRenderer {
        rendererForSource(kind)
    }

    public static let automatic = Self { kind in
        switch kind {
        case .primaryImage:
            .fullBleedImage
        case .logo:
            .centeredLogo
        }
    }
}

private struct HeroImageRenderingKey: EnvironmentKey {
    static let defaultValue = HeroImageRendering.automatic
}

public extension EnvironmentValues {
    var heroImageRendering: HeroImageRendering {
        get { self[HeroImageRenderingKey.self] }
        set { self[HeroImageRenderingKey.self] = newValue }
    }
}

public extension OME.Calendar {
    var heroImageSources: [HeroImageSource] {
        let context = LocalImageCacheContext(calendarID: id)
        return [
            images?.imageAsset(role: .hero).map {
                .primaryImage(DisplayImageAsset(asset: $0, cacheContext: context))
            },
            images?.imageAsset(role: .logo).map {
                .logo(DisplayImageAsset(asset: $0, cacheContext: context))
            },
        ].compactMap { $0 }
    }

    var heroImageTitleSources: [HeroImageTitleSource] {
        let context = LocalImageCacheContext(calendarID: id)
        return [
            images?.imageAsset(role: .logo).map {
                .logo(DisplayImageAsset(asset: $0, cacheContext: context))
            },
            .title,
        ].compactMap { $0 }
    }
}

public extension OME.Event {
    var heroImageSources: [HeroImageSource] {
        let context = LocalImageCacheContext(eventID: id)
        return [
            images?.imageAsset(role: .hero).map {
                .primaryImage(DisplayImageAsset(asset: $0, cacheContext: context))
            },
            images?.imageAsset(role: .icon).map {
                .logo(DisplayImageAsset(asset: $0, cacheContext: context))
            },
        ].compactMap { $0 }
    }

    func heroImageSources(posters: [OME.Poster]) -> [HeroImageSource] {
        let context = LocalImageCacheContext(eventID: id)
        var sources = [HeroImageSource]()
        if let hero = images?.imageAsset(role: .hero) {
            sources.append(.primaryImage(DisplayImageAsset(asset: hero, cacheContext: context)))
        }
        sources.append(contentsOf: posters.map { poster in
            .primaryImage(
                DisplayImageAsset(
                    asset: poster.image,
                    cacheContext: .init(posterID: poster.id)
                )
            )
        })
        if let icon = images?.imageAsset(role: .icon) {
            sources.append(.logo(DisplayImageAsset(asset: icon, cacheContext: context)))
        }
        return sources
    }

    var heroImageTitleSources: [HeroImageTitleSource] {
        let context = LocalImageCacheContext(eventID: id)
        return [
            images?.imageAsset(role: .icon).map {
                .logo(DisplayImageAsset(asset: $0, cacheContext: context))
            },
            .title,
        ].compactMap { $0 }
    }
}

public extension OME.Stage {
    var heroImageSources: [HeroImageSource] {
        let context = LocalImageCacheContext(stageID: id)
        return [
            images?.imageAsset(role: .hero).map {
                .primaryImage(DisplayImageAsset(asset: $0, cacheContext: context))
            },
            images?.imageAsset(role: .logo).map {
                .logo(DisplayImageAsset(asset: $0, cacheContext: context))
            },
        ].compactMap { $0 }
    }

    var heroImageTitleSources: [HeroImageTitleSource] {
        let context = LocalImageCacheContext(stageID: id)
        return [
            images?.imageAsset(role: .logo).map {
                .logo(DisplayImageAsset(asset: $0, cacheContext: context))
            },
            .title,
        ].compactMap { $0 }
    }
}
