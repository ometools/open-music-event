import ATProto
import Foundation
import Lexicon
import OpenMusicEventLexicon

public typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

public struct CalendarDTO: Codable, Equatable, Sendable {
    public static let defaultCalendar = CalendarDTO(name: "Events")

    public init(
        name: String,
        description: String? = nil,
        images: [SourceImageAsset]? = nil
    ) {
        self.name = name
        self.description = description
        self.images = images
    }

    public init(_ draft: OMERecord.Calendar.Draft) {
        self.init(
            name: draft.name,
            description: draft.description,
            images: draft.images?.map(SourceImageAsset.init).normalizingIncompleteAppearancePairs()
        )
    }

    public init(_ calendar: OMERecord.Calendar) {
        self.init(
            name: calendar.name,
            description: calendar.description,
            images: calendar.images?.map(SourceImageAsset.init).normalizingIncompleteAppearancePairs()
        )
    }

    public var name: String
    public var description: String?
    public var images: [SourceImageAsset]?

    public func recordDraft(ownerID: OMERecord.Organizer.ID) -> OMERecord.Calendar.Draft {
        OMERecord.Calendar.Draft(
            id: OMERecord.Calendar.ID(
                ownerID: ownerID,
                calendarID: OMERecord.Calendar.defaultID
            ),
            name: name,
            description: description,
            images: images?.map(\.recordValue)
        )
    }
}

public struct EventDTO: Codable, Equatable, Sendable {
    public init(
        id: OMERecord.Event.ID?,
        name: String,
        description: String?,
        startDate: LocalDate?,
        endDate: LocalDate?,
        status: Open<OMERecord.Event.Status>?,
        mode: Open<OMERecord.Event.Mode>?,
        locations: [OMERecord.Event.Location]?,
        uris: [OMERecord.Event.EventURI]?,
        timeZone: TimeZone,
        images: [SourceImageAsset]?,
        contactNumbers: [OMERecord.Event.ContactNumber]?,
        categoryConfigs: OMERecord.Event.CategoryConfigs?,
        policies: OMERecord.Event.Policies? = nil,
        reportingLink: OMERecord.Event.ReportingLink? = nil,
        owner: OMERecord.Contributor.Actor? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.mode = mode
        self.locations = locations
        self.uris = uris
        self.timeZone = timeZone
        self.images = images
        self.contactNumbers = contactNumbers
        self.categoryConfigs = categoryConfigs
        self.policies = policies
        self.reportingLink = reportingLink
        self.owner = owner
    }

    public init(
        id: OMERecord.Event.ID?,
        name: String,
        description: String?,
        startDate: LocalDate?,
        endDate: LocalDate?,
        status: Open<OMERecord.Event.Status>?,
        mode: Open<OMERecord.Event.Mode>?,
        locations: [OMERecord.Event.Location]?,
        uris: [OMERecord.Event.EventURI]?,
        timeZone: TimeZone,
        imageURL: URL?,
        iconImageURL: URL?,
        siteMapImageURL: URL?,
        contactNumbers: [OMERecord.Event.ContactNumber]?,
        categoryConfigs: OMERecord.Event.CategoryConfigs?,
        policies: OMERecord.Event.Policies? = nil,
        reportingLink: OMERecord.Event.ReportingLink? = nil,
        owner: OMERecord.Contributor.Actor? = nil
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
            policies: policies,
            reportingLink: reportingLink,
            owner: owner
        )
    }

    public init(_ draft: OMERecord.Event.Draft) {
        self.init(
            id: draft.id,
            name: draft.name,
            description: draft.description,
            startDate: draft.startDate,
            endDate: draft.endDate,
            status: draft.status,
            mode: draft.mode,
            locations: draft.locations,
            uris: draft.uris,
            timeZone: draft.timeZone,
            images: draft.images?.map(SourceImageAsset.init).normalizingIncompleteAppearancePairs(),
            contactNumbers: draft.contactNumbers,
            categoryConfigs: draft.categoryConfigs,
            policies: draft.policies,
            reportingLink: draft.reportingLink,
            owner: draft.owner
        )
    }

    public var id: OMERecord.Event.ID?
    public var name: String
    public var description: String?
    public var startDate: LocalDate?
    public var endDate: LocalDate?
    public var status: Open<OMERecord.Event.Status>?
    public var mode: Open<OMERecord.Event.Mode>?
    public var locations: [OMERecord.Event.Location]?
    public var uris: [OMERecord.Event.EventURI]?
    @SourceTimeZone public var timeZone: TimeZone
    public var images: [SourceImageAsset]?
    public var contactNumbers: [OMERecord.Event.ContactNumber]?
    public var categoryConfigs: OMERecord.Event.CategoryConfigs?
    public var policies: OMERecord.Event.Policies?
    public var reportingLink: OMERecord.Event.ReportingLink?
    public var owner: OMERecord.Contributor.Actor?

    public var recordDraft: OMERecord.Event.Draft {
        OMERecord.Event.Draft(
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
            images: images?.map(\.recordValue),
            contactNumbers: contactNumbers,
            categoryConfigs: categoryConfigs,
            policies: policies,
            reportingLink: reportingLink,
            owner: owner
        )
    }

    public var imageURL: URL? {
        images?.first(where: { $0.role == .hero })?.url
    }

    public var iconImageURL: URL? {
        images?.first(where: { $0.role == .icon })?.url
    }

    public var siteMapImageURL: URL? {
        images?.first(where: { $0.role == .siteMap })?.url
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case startDate
        case endDate
        case status
        case mode
        case locations
        case uris
        case timeZone
        case images
        case imageURL
        case iconImageURL
        case siteMapImageURL
        case contactNumbers
        case categoryConfigs
        case policies
        case reportingLink
        case owner
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let images = try container.decodeIfPresent([SourceImageAsset].self, forKey: .images)
            ?? Self.legacyImages(
                heroURL: try container.decodeIfPresent(URL.self, forKey: .imageURL),
                iconURL: try container.decodeIfPresent(URL.self, forKey: .iconImageURL),
                siteMapURL: try container.decodeIfPresent(URL.self, forKey: .siteMapImageURL)
            )

        self.init(
            id: try container.decodeIfPresent(OMERecord.Event.ID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            startDate: try container.decodeIfPresent(LocalDate.self, forKey: .startDate),
            endDate: try container.decodeIfPresent(LocalDate.self, forKey: .endDate),
            status: try container.decodeIfPresent(Open<OMERecord.Event.Status>.self, forKey: .status),
            mode: try container.decodeIfPresent(Open<OMERecord.Event.Mode>.self, forKey: .mode),
            locations: try container.decodeIfPresent([OMERecord.Event.Location].self, forKey: .locations),
            uris: try container.decodeIfPresent([OMERecord.Event.EventURI].self, forKey: .uris),
            timeZone: try container.decode(SourceTimeZone.self, forKey: .timeZone).wrappedValue,
            images: images,
            contactNumbers: try container.decodeIfPresent([OMERecord.Event.ContactNumber].self, forKey: .contactNumbers),
            categoryConfigs: try container.decodeIfPresent(OMERecord.Event.CategoryConfigs.self, forKey: .categoryConfigs),
            policies: try container.decodeIfPresent(OMERecord.Event.Policies.self, forKey: .policies),
            reportingLink: try container.decodeIfPresent(OMERecord.Event.ReportingLink.self, forKey: .reportingLink),
            owner: try container.decodeIfPresent(OMERecord.Contributor.Actor.self, forKey: .owner)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(locations, forKey: .locations)
        try container.encodeIfPresent(uris, forKey: .uris)
        try container.encode(SourceTimeZone(wrappedValue: timeZone), forKey: .timeZone)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(contactNumbers, forKey: .contactNumbers)
        try container.encodeIfPresent(categoryConfigs, forKey: .categoryConfigs)
        try container.encodeIfPresent(policies, forKey: .policies)
        try container.encodeIfPresent(reportingLink, forKey: .reportingLink)
        try container.encodeIfPresent(owner, forKey: .owner)
    }

    private static func legacyImages(
        heroURL: URL?,
        iconURL: URL?,
        siteMapURL: URL?
    ) -> [SourceImageAsset]? {
        let images = [
            heroURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .hero,
                    renderKind: .fullImage,
                    materializationPolicy: .prefetchOnOpen
                )
            },
            iconURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .icon,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            },
            siteMapURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .siteMap,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            },
        ].compactMap { $0 }

        return images.isEmpty ? nil : images
    }
}

public struct StageDTO: Codable, Equatable, Sendable {
    public init(
        id: OMERecord.Stage.ID? = nil,
        name: String,
        color: OMEColor,
        category: OMERecord.Stage.Category? = nil,
        sortIndex: Int? = nil,
        images: [SourceImageAsset]? = nil,
        systemIconName: String? = nil,
        iconShortCode: String? = nil,
        lineup: [OMERecord.ID<OMERecord.Contributor>]? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.category = category
        self.sortIndex = sortIndex
        self.images = images
        self.systemIconName = systemIconName
        self.iconShortCode = iconShortCode
        self.lineup = lineup
    }

    public init(
        id: OMERecord.Stage.ID? = nil,
        name: String,
        color: OMEColor,
        category: OMERecord.Stage.Category? = nil,
        sortIndex: Int? = nil,
        iconImageURL: URL? = nil,
        systemIconName: String? = nil,
        iconShortCode: String? = nil,
        imageURL: URL? = nil,
        posterImageURL: URL? = nil,
        lineup: [OMERecord.ID<OMERecord.Contributor>]? = nil
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

    public init(_ draft: OMERecord.Stage.Draft) {
        self.init(
            id: draft.id,
            name: draft.name,
            color: draft.color,
            category: draft.category,
            sortIndex: draft.sortIndex,
            images: draft.images?.map(SourceImageAsset.init).normalizingIncompleteAppearancePairs(),
            systemIconName: draft.systemIconName,
            iconShortCode: draft.iconShortCode,
            lineup: draft.lineup
        )
    }

    public var id: OMERecord.Stage.ID?
    public var name: String
    public var color: OMEColor
    public var category: OMERecord.Stage.Category?
    public var sortIndex: Int?
    public var images: [SourceImageAsset]?
    public var systemIconName: String?
    public var iconShortCode: String?
    public var lineup: [OMERecord.ID<OMERecord.Contributor>]?

    public var recordDraft: OMERecord.Stage.Draft {
        OMERecord.Stage.Draft(
            id: id,
            name: name,
            color: color,
            category: category,
            sortIndex: sortIndex,
            images: images?.map(\.recordValue),
            systemIconName: systemIconName,
            iconShortCode: iconShortCode,
            lineup: lineup
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case category
        case sortIndex
        case images
        case iconImageURL
        case systemIconName
        case iconShortCode
        case imageURL
        case posterImageURL
        case lineup
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let images = try container.decodeIfPresent([SourceImageAsset].self, forKey: .images)
            ?? Self.legacyImages(
                logoURL: try container.decodeIfPresent(URL.self, forKey: .iconImageURL),
                heroURL: try container.decodeIfPresent(URL.self, forKey: .imageURL),
                posterURL: try container.decodeIfPresent(URL.self, forKey: .posterImageURL)
            )

        self.init(
            id: try container.decodeIfPresent(OMERecord.Stage.ID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            color: try container.decode(OMEColor.self, forKey: .color),
            category: try container.decodeIfPresent(OMERecord.Stage.Category.self, forKey: .category),
            sortIndex: try container.decodeIfPresent(Int.self, forKey: .sortIndex),
            images: images,
            systemIconName: try container.decodeIfPresent(String.self, forKey: .systemIconName),
            iconShortCode: try container.decodeIfPresent(String.self, forKey: .iconShortCode),
            lineup: try container.decodeIfPresent([OMERecord.ID<OMERecord.Contributor>].self, forKey: .lineup)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(sortIndex, forKey: .sortIndex)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(systemIconName, forKey: .systemIconName)
        try container.encodeIfPresent(iconShortCode, forKey: .iconShortCode)
        try container.encodeIfPresent(lineup, forKey: .lineup)
    }

    private static func legacyImages(
        logoURL: URL?,
        heroURL: URL?,
        posterURL: URL?
    ) -> [SourceImageAsset]? {
        let images = [
            logoURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .prefetchOnOpen
                )
            },
            heroURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .hero,
                    renderKind: .fullImage,
                    materializationPolicy: .prefetchOnOpen
                )
            },
            posterURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .poster,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            },
        ].compactMap { $0 }

        return images.isEmpty ? nil : images
    }
}

public struct ContributorDTO: Codable, Equatable, Sendable {
    public init(
        id: OMERecord.Contributor.ID? = nil,
        name: String,
        did: DID? = nil,
        bio: String? = nil,
        images: [SourceImageAsset]? = nil,
        kind: OMERecord.Contributor.Kind? = nil,
        links: [ExternalPlatform.Link]? = nil
    ) {
        self.id = id
        self.name = name
        self.did = did
        self.bio = bio
        self.images = images
        self.kind = kind
        self.links = links
    }

    public init(
        id: OMERecord.Contributor.ID? = nil,
        name: String,
        did: DID? = nil,
        bio: String? = nil,
        imageURL: URL? = nil,
        logoURL: URL? = nil,
        kind: OMERecord.Contributor.Kind? = nil,
        links: [ExternalPlatform.Link]? = nil
    ) {
        self.init(
            id: id,
            name: name,
            did: did,
            bio: bio,
            images: Self.legacyImages(photoURL: imageURL, logoURL: logoURL),
            kind: kind,
            links: links
        )
    }

    public init(_ draft: OMERecord.Contributor.Draft) {
        self.init(
            id: draft.id,
            name: draft.name,
            did: draft.did,
            bio: draft.bio,
            images: draft.images?.map(SourceImageAsset.init).normalizingIncompleteAppearancePairs(),
            kind: draft.kind,
            links: draft.links
        )
    }

    public var id: OMERecord.Contributor.ID?
    public var name: String
    public var did: DID?
    public var bio: String?
    public var images: [SourceImageAsset]?
    public var kind: OMERecord.Contributor.Kind?
    public var links: [ExternalPlatform.Link]?

    public var recordDraft: OMERecord.Contributor.Draft {
        OMERecord.Contributor.Draft(
            id: id,
            name: name,
            did: did,
            bio: bio,
            images: images?.map(\.recordValue),
            kind: kind,
            links: links
        )
    }

    public var imageURL: URL? {
        images?.first(where: { $0.role == .photo })?.url
    }

    public var logoURL: URL? {
        images?.first(where: { $0.role == .logo })?.url
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case did
        case bio
        case images
        case imageURL
        case logoURL
        case kind
        case links
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let images = try container.decodeIfPresent([SourceImageAsset].self, forKey: .images)
            ?? Self.legacyImages(
                photoURL: try container.decodeIfPresent(URL.self, forKey: .imageURL),
                logoURL: try container.decodeIfPresent(URL.self, forKey: .logoURL)
            )

        self.init(
            id: try container.decodeIfPresent(OMERecord.Contributor.ID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            did: try container.decodeIfPresent(DID.self, forKey: .did),
            bio: try container.decodeIfPresent(String.self, forKey: .bio),
            images: images,
            kind: try container.decodeIfPresent(OMERecord.Contributor.Kind.self, forKey: .kind),
            links: try container.decodeIfPresent([ExternalPlatform.Link].self, forKey: .links)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(did, forKey: .did)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(links, forKey: .links)
    }

    private static func legacyImages(
        photoURL: URL?,
        logoURL: URL?
    ) -> [SourceImageAsset]? {
        let images = [
            photoURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                )
            },
            logoURL.map {
                SourceImageAsset(
                    source: .url($0),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .lazy
                )
            },
        ].compactMap { $0 }

        return images.isEmpty ? nil : images
    }
}

public typealias ChannelDTO = OMERecord.Channel.Draft

public struct PosterDTO: Codable, Equatable, Sendable {
    public init(
        id: OMERecord.Poster.ID?,
        title: String?,
        image: SourceImageAsset
    ) {
        self.id = id
        self.title = title
        self.image = image
    }

    public init(
        id: OMERecord.Poster.ID?,
        title: String?,
        imageURL: URL
    ) {
        self.init(
            id: id,
            title: title,
            image: SourceImageAsset(
                source: .url(imageURL),
                role: .poster,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        )
    }

    public init(_ draft: OMERecord.Poster.Draft) {
        self.init(
            id: draft.id,
            title: draft.title,
            image: [SourceImageAsset(draft.image)].normalizingIncompleteAppearancePairs()[0]
        )
    }

    public var id: OMERecord.Poster.ID?
    public var title: String?
    public var image: SourceImageAsset

    public var recordDraft: OMERecord.Poster.Draft {
        OMERecord.Poster.Draft(
            id: id,
            title: title,
            image: image.recordValue
        )
    }

    public var imageURL: URL? {
        image.url
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case image
        case imageURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let image = try container.decodeIfPresent(SourceImageAsset.self, forKey: .image)
            ?? SourceImageAsset(
                source: .url(try container.decode(URL.self, forKey: .imageURL)),
                role: .poster,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )

        self.init(
            id: try container.decodeIfPresent(OMERecord.Poster.ID.self, forKey: .id),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            image: image
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(image, forKey: .image)
    }
}

private extension SourceImageAsset {
    init(_ imageAsset: OMERecord.ImageAsset) {
        self.init(
            assetKey: imageAsset.assetKey,
            source: {
                switch imageAsset.source {
                case let .blob(blob):
                    // Source DTOs are collaboration-level and should stay path/URL based.
                    let url = URL(string: "atproto-blob://\(blob.ref.rawValue)")!
                    return .url(url)
                case let .url(url):
                    return .url(url)
                }
            }(),
            role: imageAsset.role,
            renderKind: imageAsset.renderKind,
            appearance: imageAsset.appearance,
            materializationPolicy: imageAsset.materializationPolicy,
            thumbhash: imageAsset.thumbhash,
            focalPoint: imageAsset.focalPoint
        )
    }

    var recordValue: OMERecord.ImageAsset {
        OMERecord.ImageAsset(
            assetKey: assetKey,
            source: .url(url),
            role: role,
            renderKind: renderKind,
            appearance: appearance,
            materializationPolicy: materializationPolicy,
            thumbhash: thumbhash,
            focalPoint: focalPoint
        )
    }

    var url: URL {
        switch source {
        case let .file(path):
            URL(filePath: path)
        case let .url(url):
            url
        }
    }
}
