import ATProto
import Foundation
import Lexicon
import SQLiteData

extension OpenMusicEvent {
    public struct ImageAsset: Codable, Equatable, Sendable {
        public init(
            assetKey: String? = nil,
            source: Source,
            role: Role,
            renderKind: RenderKind,
            appearance: Appearance? = nil,
            materializationPolicy: MaterializationPolicy,
            thumbhash: String? = nil,
            focalPoint: FocalPoint? = nil
        ) {
            self.assetKey = assetKey
            self.source = source
            self.role = role
            self.renderKind = renderKind
            self.appearance = appearance
            self.materializationPolicy = materializationPolicy
            self.thumbhash = thumbhash
            self.focalPoint = focalPoint
        }

        public var assetKey: String?
        public var source: Source
        public var role: Role
        public var renderKind: RenderKind
        public var appearance: Appearance?
        public var materializationPolicy: MaterializationPolicy
        public var thumbhash: String?
        public var focalPoint: FocalPoint?
    }
}

extension OpenMusicEvent.ImageAsset {
    public enum Source: Codable, Equatable, Sendable {
        case blob(ATProto.Blob)
        case url(URL)

        private enum CodingKeys: String, CodingKey {
            case blob
            case url
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let blob = try container.decodeIfPresent(ATProto.Blob.self, forKey: .blob) {
                self = .blob(blob)
            } else {
                self = .url(try container.decode(URL.self, forKey: .url))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .blob(blob):
                try container.encode(blob, forKey: .blob)
            case let .url(url):
                try container.encode(url, forKey: .url)
            }
        }
    }

    public enum Role: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case hero
        case logo
        case photo
        case icon
        case siteMap
        case poster
    }

    public enum RenderKind: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case transparent
        case fullImage
    }

    public enum Appearance: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case light
        case dark
    }

    public enum MaterializationPolicy: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case prefetchOnOpen
        case lazy
    }

    public struct FocalPoint: Codable, Equatable, Sendable {
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public var x: Double
        public var y: Double
    }
}

public extension OpenMusicEvent.ImageAsset {
    static func calendarHero(url: URL) -> Self {
        Self(
            source: .url(url),
            role: .hero,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )
    }

    static func calendarLogo(url: URL) -> Self {
        Self(
            source: .url(url),
            role: .logo,
            renderKind: .transparent,
            materializationPolicy: .lazy
        )
    }

    static func stageHero(url: URL) -> Self {
        Self(
            source: .url(url),
            role: .hero,
            renderKind: .fullImage,
            materializationPolicy: .prefetchOnOpen
        )
    }

    static func stageLogo(url: URL) -> Self {
        Self(
            source: .url(url),
            role: .logo,
            renderKind: .transparent,
            materializationPolicy: .prefetchOnOpen
        )
    }

    static func stagePoster(url: URL) -> Self {
        Self(
            source: .url(url),
            role: .poster,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )
    }

    var url: URL? {
        if case let .url(url) = source {
            return url
        }
        return nil
    }

    var isTemplateLike: Bool {
        renderKind == .transparent
    }
}

public extension Collection where Element == OpenMusicEvent.ImageAsset {
    func imageAsset(
        role: OpenMusicEvent.ImageAsset.Role,
        appearance: OpenMusicEvent.ImageAsset.Appearance? = nil
    ) -> Element? {
        if let appearance,
           let exact = first(where: { $0.role == role && $0.appearance == appearance }) {
            return exact
        }

        if let neutral = first(where: { $0.role == role && $0.appearance == nil }) {
            return neutral
        }

        return first(where: { $0.role == role })
    }

    func normalizingIncompleteAppearancePairs() -> [OpenMusicEvent.ImageAsset] {
        var appearancesByKey: [String: AppearancePairCompleteness] = [:]

        for image in self {
            guard let appearance = image.appearance else { continue }
            appearancesByKey[image.appearancePairKey, default: AppearancePairCompleteness()]
                .insert(appearance)
        }

        return map { image in
            guard image.appearance != nil,
                  appearancesByKey[image.appearancePairKey]?.isComplete != true
            else {
                return image
            }

            var image = image
            image.appearance = nil
            return image
        }
    }
}

private struct AppearancePairCompleteness {
    var hasDark = false
    var hasLight = false

    var isComplete: Bool {
        hasDark && hasLight
    }

    mutating func insert(_ appearance: OpenMusicEvent.ImageAsset.Appearance) {
        switch appearance {
        case .dark:
            hasDark = true
        case .light:
            hasLight = true
        }
    }
}

private extension OpenMusicEvent.ImageAsset {
    var appearancePairKey: String {
        "\(role.rawValue)|\(renderKind.rawValue)"
    }
}

public extension OpenMusicEvent.Event {
    var imageURL: URL? {
        images?.imageAsset(role: .hero)?.url
    }

    var iconImageURL: URL? {
        images?.imageAsset(role: .icon)?.url
    }

    var siteMapImageURL: URL? {
        images?.imageAsset(role: .siteMap)?.url
    }
}

public extension OpenMusicEvent.Stage {
    var iconImageURL: URL? {
        images?.imageAsset(role: .logo)?.url
    }

    var imageURL: URL? {
        images?.imageAsset(role: .hero)?.url
    }

    var posterImageURL: URL? {
        images?.imageAsset(role: .poster)?.url
    }
}

public extension OpenMusicEvent.Contributor {
    var imageURL: URL? {
        images?.imageAsset(role: .photo)?.url
    }

    var logoURL: URL? {
        images?.imageAsset(role: .logo)?.url
    }
}

public extension OpenMusicEvent.Poster {
    var imageURL: URL? {
        image.url
    }
}

public extension OpenMusicEvent.Poster.Draft {
    init(
        id: OME.Poster.ID? = nil,
        title: String? = nil,
        imageURL: URL
    ) {
        self.init(
            id: id,
            title: title,
            image: OME.ImageAsset(
                source: .url(imageURL),
                role: .poster,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        )
    }
}

public extension OpenMusicEvent.Event.Draft {
    init(
        id: OME.Event.ID? = nil,
        name: String,
        description: String? = nil,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        status: Open<OME.Event.Status>? = nil,
        mode: Open<OME.Event.Mode>? = nil,
        locations: [OME.Event.Location]? = nil,
        uris: [OME.Event.EventURI]? = nil,
        timeZone: TimeZone,
        imageURL: URL? = nil,
        iconImageURL: URL? = nil,
        siteMapImageURL: URL? = nil,
        contactNumbers: [OME.Event.ContactNumber]? = nil,
        categoryConfigs: OME.Event.CategoryConfigs? = nil,
        reportingLink: OME.Event.ReportingLink? = nil,
        owner: OME.Contributor.Actor? = nil
    ) {
        self.init(
            id: id,
            name: name,
            description: description,
            startDate: startDate,
            endDate: endDate,
            status: status,
            mode: mode,
            locations: locations,
            uris: uris,
            timeZone: timeZone,
            images: Self.legacyImages(
                heroURL: imageURL,
                iconURL: iconImageURL,
                siteMapURL: siteMapImageURL
            ),
            contactNumbers: contactNumbers,
            categoryConfigs: categoryConfigs,
            reportingLink: reportingLink,
            owner: owner
        )
    }

    static func legacyImages(
        heroURL: URL?,
        iconURL: URL?,
        siteMapURL: URL?
    ) -> [OME.ImageAsset]? {
        let images = [
            heroURL.map {
                OME.ImageAsset(
                    source: .url($0),
                    role: .hero,
                    renderKind: .fullImage,
                    materializationPolicy: .prefetchOnOpen
                )
            },
            iconURL.map {
                OME.ImageAsset(
                    source: .url($0),
                    role: .icon,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            },
            siteMapURL.map {
                OME.ImageAsset(
                    source: .url($0),
                    role: .siteMap,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            },
        ].compactMap { $0 }

        return images.isEmpty ? nil : images
    }

    var imageURL: URL? {
        images?.imageAsset(role: .hero)?.url
    }

    var iconImageURL: URL? {
        images?.imageAsset(role: .icon)?.url
    }

    var siteMapImageURL: URL? {
        images?.imageAsset(role: .siteMap)?.url
    }
}

public extension OpenMusicEvent.Stage.Draft {
    init(
        id: OME.Stage.ID? = nil,
        name: String,
        color: OMEColor,
        category: OME.Stage.Category? = nil,
        sortIndex: Int? = nil,
        iconImageURL: URL? = nil,
        systemIconName: String? = nil,
        iconShortCode: String? = nil,
        imageURL: URL? = nil,
        posterImageURL: URL? = nil,
        lineup: [OME.ID<OME.Contributor>]? = nil
    ) {
        self.init(
            id: id,
            name: name,
            color: color,
            category: category,
            sortIndex: sortIndex,
            images: Self.legacyImages(
                logoURL: iconImageURL,
                heroURL: imageURL,
                posterURL: posterImageURL
            ),
            systemIconName: systemIconName,
            iconShortCode: iconShortCode,
            lineup: lineup
        )
    }

    static func legacyImages(
        logoURL: URL?,
        heroURL: URL?,
        posterURL: URL?
    ) -> [OME.ImageAsset]? {
        let images = [
            logoURL.map(OME.ImageAsset.stageLogo),
            heroURL.map(OME.ImageAsset.stageHero),
            posterURL.map(OME.ImageAsset.stagePoster),
        ].compactMap { $0 }

        return images.isEmpty ? nil : images
    }

    var iconImageURL: URL? {
        images?.imageAsset(role: .logo)?.url
    }

    var imageURL: URL? {
        images?.imageAsset(role: .hero)?.url
    }

    var posterImageURL: URL? {
        images?.imageAsset(role: .poster)?.url
    }
}

public extension OpenMusicEvent.Contributor.Draft {
    init(
        id: OME.Contributor.ID? = nil,
        name: String,
        bio: String? = nil,
        imageURL: URL? = nil,
        logoURL: URL? = nil,
        kind: OME.Contributor.Kind? = nil,
        links: [ExternalPlatform.Link]? = nil
    ) {
        self.init(
            id: id,
            name: name,
            bio: bio,
            images: Self.legacyImages(photoURL: imageURL, logoURL: logoURL),
            kind: kind,
            links: links
        )
    }

    static func legacyImages(
        photoURL: URL?,
        logoURL: URL?
    ) -> [OME.ImageAsset]? {
        let images = [
            photoURL.map {
                OME.ImageAsset(
                    source: .url($0),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            },
            logoURL.map {
                OME.ImageAsset(
                    source: .url($0),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .lazy
                )
            },
        ].compactMap { $0 }

        return images.isEmpty ? nil : images
    }

    var imageURL: URL? {
        images?.imageAsset(role: .photo)?.url
    }

    var logoURL: URL? {
        images?.imageAsset(role: .logo)?.url
    }
}
