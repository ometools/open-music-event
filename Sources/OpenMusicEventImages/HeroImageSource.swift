import OpenMusicEventDatabase
import OpenMusicEventLexicon
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct DisplayImageAsset: Equatable, Sendable {
    public init(
        asset: OME.ImageAsset,
        cacheContext: LocalImageCacheContext? = nil,
        recordID: Event.ID? = nil
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.recordID = recordID
    }

    public var asset: OME.ImageAsset
    public var cacheContext: LocalImageCacheContext?
    public var recordID: Event.ID?
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

public extension Event {
    var heroImageSources: [HeroImageSource] {
        displayImages
            .sorted { $0.priority < $1.priority }
            .map { image in
                let kind: HeroImageSource.Kind = image.asset.asset.role == .icon
                    || image.asset.asset.role == .logo ? .logo : .primaryImage
                return HeroImageSource(kind, image: image.asset)
            }
    }

    var heroImageTitleSources: [HeroImageTitleSource] {
        let logo = displayImages.first { $0.asset.asset.role == .icon }
            ?? displayImages.first { $0.asset.asset.role == .logo }
        return [logo.map { .logo($0.asset) }, .title].compactMap { $0 }
    }
}

private extension Event {
    var displayImages: [(priority: Int, asset: DisplayImageAsset)] {
        (media ?? []).compactMap { medium in
            guard case let .known(.image(image)) = medium,
                  image.role != .known(.siteMap),
                  let asset = image.displayImageAsset(recordID: id) else { return nil }
            let priority: Int = switch asset.asset.role {
            case .poster: 0
            case .hero: 1
            case .photo: 2
            case .icon: 4
            case .logo: 5
            case .siteMap: 6
            }
            return (priority, asset)
        }
    }
}

public extension Contributor {
    var artworkDisplayImage: DisplayImageAsset? {
        displayImages.first { $0.asset.role == .photo }
            ?? displayImages.first { $0.asset.role == .logo }
    }

    var logoDisplayImage: DisplayImageAsset? {
        displayImages.first { $0.asset.role == .logo }
    }

    var heroImageSources: [HeroImageSource] {
        [
            artworkDisplayImage.map(HeroImageSource.primaryImage),
            logoDisplayImage.map(HeroImageSource.logo),
        ].compactMap { $0 }
    }

    var heroImageTitleSources: [HeroImageTitleSource] {
        [
            logoDisplayImage.map(HeroImageTitleSource.logo),
            .title,
        ].compactMap { $0 }
    }
}

private extension Contributor {
    var displayImages: [DisplayImageAsset] {
        (media ?? []).compactMap { medium in
            guard case let .known(.image(image)) = medium,
                  image.role == nil || image.role == .known(.photo) || image.role == .known(.logo)
            else { return nil }
            return image.displayImageAsset(recordID: event)
        }
    }
}

public extension EventPlace {
    var heroImageSources: [HeroImageSource] {
        (media ?? []).compactMap { medium in
            guard case let .known(.image(image)) = medium,
                  image.role != .known(.siteMap),
                  let asset = image.displayImageAsset(recordID: event)
            else { return nil }
            let kind: HeroImageSource.Kind = asset.asset.role == .logo || asset.asset.role == .icon
                ? .logo : .primaryImage
            return HeroImageSource(kind, image: asset)
        }
    }

    var heroImageTitleSources: [HeroImageTitleSource] {
        [
            stageLogoDisplayImage.map(HeroImageTitleSource.logo),
            .title,
        ].compactMap { $0 }
    }

    var stageLogoDisplayImage: DisplayImageAsset? {
        (media ?? []).compactMap { medium -> DisplayImageAsset? in
            guard case let .known(.image(image)) = medium,
                  image.role == .known(.logo) || image.role == .known(.icon(.init()))
            else { return nil }
            return image.displayImageAsset(recordID: event)
        }
        .first
    }
}

public extension ProgramItem {
    var heroImageSources: [HeroImageSource] {
        (media ?? []).compactMap { medium in
            guard case let .known(.image(image)) = medium,
                  image.role != .known(.siteMap),
                  let asset = image.displayImageAsset(recordID: event)
            else { return nil }
            let kind: HeroImageSource.Kind = asset.asset.role == .logo || asset.asset.role == .icon
                ? .logo : .primaryImage
            return HeroImageSource(kind, image: asset)
        }
    }
}

public extension OME.Image {
    func displayImageAsset(recordID: Event.ID) -> DisplayImageAsset? {
        let source: OME.ImageAsset.Source
        switch self.source {
        case let .known(.blob(blob)):
            source = .blob(blob)
        case let .known(.url(url)):
            source = .url(url)
        case .unknown:
            return nil
        }

        let role: OME.ImageAsset.Role
        switch self.role {
        case .known(.hero): role = .hero
        case .known(.logo): role = .logo
        case .known(.photo), .none, .unknown: role = .photo
        case .known(.icon): role = .icon
        case .known(.poster): role = .poster
        case .known(.siteMap): role = .siteMap
        }

        let appearance: OME.ImageAsset.Appearance?
        switch self.appearance {
        case .known(.light): appearance = .light
        case .known(.dark): appearance = .dark
        case .none, .unknown: appearance = nil
        }

        return DisplayImageAsset(
            asset: OME.ImageAsset(
                source: source,
                role: role,
                renderKind: renderingMode == .known(.template) ? .transparent : .fullImage,
                appearance: appearance,
                materializationPolicy: .lazy,
                focalPoint: focalPoint.map {
                    OME.ImageAsset.FocalPoint(x: $0.x, y: $0.y)
                }
            ),
            recordID: recordID
        )
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
