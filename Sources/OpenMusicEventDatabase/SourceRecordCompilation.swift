import ATProto
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import Tagged

/// Persist this mapping before publishing so retries keep the source records' identities.
public struct SourcePublicationIdentities: Codable, Equatable, Sendable {
    public var records: [String: ATProto.URI] = [:]
    public init() {}

    public mutating func eventURI(
        sourceDirectory: String,
        account: DID,
        createdAt: Date
    ) throws -> ATProto.URI {
        let identity = String(
            decoding: try JSONEncoder().encode(["event", sourceDirectory]),
            as: UTF8.self
        )
        if let uri = records[identity] {
            guard uri.authority == .did(account),
                  uri.collection?.rawValue == Event.lexiconID.rawValue,
                  uri.rkey != nil
            else {
                throw ValidationError("The identity map contains an incompatible Event: \(identity)")
            }
            return uri
        }
        let previous = records.values.compactMap(\.rkey).max {
            $0.rawValue < $1.rawValue
        }
        let uri = try CanonicalRecordID.next(
            collection: Event.lexiconID,
            in: .did(account),
            at: createdAt,
            after: previous,
            clockID: 0
        )
        records[identity] = uri
        return uri
    }

    mutating func uri(collection: Lexicon.ID, event: Event, key: String) throws -> ATProto.URI {
        let identity = String(decoding: try JSONEncoder().encode([event.id.description, collection.rawValue, key]), as: UTF8.self)
        if let uri = records[identity] {
            guard uri.authority == event.id.authority, uri.collection?.rawValue == collection.rawValue, uri.rkey != nil else {
                throw ValidationError("The identity map contains an incompatible record: \(identity)")
            }
            return uri
        }
        guard let date = ISO8601DateFormatter().date(from: event.createdAt.rawValue) else {
            throw ValidationError("Invalid publication creation timestamp")
        }
        let previous = records.values.compactMap(\.rkey).max { $0.rawValue < $1.rawValue }
        let uri = try CanonicalRecordID.next(collection: collection, in: event.id.authority, at: date, after: previous, clockID: 0)
        records[identity] = uri
        return uri
    }
}

extension SourceRecordPublication {
    public static func prepare(
        source: OpenMusicEventSourceRepository,
        sourceRoot: URL,
        events: [String: Event],
        identities: inout SourcePublicationIdentities,
        preserveLinkText: Bool = false,
        loadImage: @Sendable (URL) async throws -> Data
    ) async throws -> Self {
        guard let first = events.values.first, case let .did(account) = first.id.authority,
              events.values.allSatisfy({ $0.id.authority == .did(account) }) else {
            throw ValidationError("Source events must belong to one publisher")
        }
        var result = Self(account: account)
        var imageData: [ATProto.CID: Data] = [:]
        var loadedImages: [String: ATProto.Blob] = [:]
        var compressedPostImages: Set<URL> = []

        func blob(for url: URL, postEmbed: Bool = false) async throws -> ATProto.Blob {
            let cacheKey = "\(postEmbed):\(url.absoluteString)"
            if let blob = loadedImages[cacheKey] { return blob }
            guard url.isFileURL || (url.scheme == "https" && url.host != nil) else {
                throw ValidationError("Source images must be local files or HTTPS URLs")
            }
            let original = try await loadImage(url)
            let bytes = postEmbed ? try preparePostImage(original) : original
            if bytes != original {
                compressedPostImages.insert(url)
                result.diagnostics.append("Compressed post image \(url): \(original.count) to \(bytes.count) bytes at original dimensions")
            }
            let mime: ATProto.MIMEType
            if bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { mime = .png }
            else if bytes.starts(with: [255, 216, 255]) { mime = .jpeg }
            else { throw ValidationError("Source image is not PNG or JPEG: \(url) (\(bytes.count) bytes)") }
            let blob = localImageBlob(bytes, mimeType: mime)
            imageData[blob.ref] = bytes
            loadedImages[cacheKey] = blob
            return blob
        }
        func image(_ asset: OME.ImageAsset, title: String? = nil) async throws -> OME.Image {
            let source: Open<OME.Image.Source>
            switch asset.source {
            case let .blob(blob): source = .known(.blob(blob))
            case let .url(url): source = url.isFileURL ? .known(.blob(try await blob(for: url))) : .known(.url(url))
            }
            let value = OME.Image(source: source, title: title,
                role: OME.Image.Role(rawValue: asset.role.rawValue).map { .known($0) },
                renderingMode: asset.renderKind == .transparent ? .known(.template) : .known(.original),
                appearance: asset.appearance.map { .known(OME.Image.Appearance(rawValue: $0.rawValue)!) },
                focalPoint: asset.focalPoint.map { .init(x: $0.x, y: $0.y) })
            try value.validateForPublication()
            return value
        }
        func media(_ assets: [OME.ImageAsset]?) async throws -> [Open<OME.Media>]? {
            guard let assets, !assets.isEmpty else { return nil }
            var values: [Open<OME.Media>] = []
            for asset in assets { values.append(.known(.image(try await image(asset)))) }
            return values
        }
        func materialize<T: Decodable>(_ type: T.Type, _ draft: some Encodable) throws -> T {
            try JSONDecoder().decode(type, from: JSONEncoder().encode(draft))
        }
        func datetime(_ date: Date) -> ATProto.DateTime {
            .init(rawValue: ISO8601DateFormatter().string(from: date))
        }

        for entry in source.events.sorted(by: { $0.directoryName < $1.directoryName }) {
            guard var event = events[entry.directoryName] else { continue }
            // The source importer owns overnight times, inferred ends, file assets and source references.
            let normalized = try OME.SourceDatabaseInsertion(.init(
                source: .init(events: [entry]), organizerID: account, sourceRootURL: sourceRoot
            ))
            let sourceContributors = try normalized.contributors.map { try materialize(OME.Contributor.self, $0) }
            let sourceStages = try normalized.stages.map { try materialize(OME.Stage.self, $0) }
                .sorted { ($0.sortIndex ?? 0, $0.id.stageID.rawValue.rawValue) < ($1.sortIndex ?? 0, $1.id.stageID.rawValue.rawValue) }
            let sourceSchedules = try normalized.schedules.map { try materialize(OME.Schedule.self, $0) }
                .sorted { $0.date.description < $1.date.description }
            let sourceItems = try normalized.scheduleItems.map { try materialize(OME.ScheduleItem.self, $0) }
            let sourceCredits = try normalized.scheduleItemContributors.map { try materialize(OME.ScheduleItem.Contributor.self, $0) }
            let performanceDetails = try normalized.scheduleItemPerformanceDetails.map { try materialize(OME.ScheduleItem.PerformanceDetails.self, $0) }
            let channels = try normalized.channels.map { try materialize(OME.Channel.self, $0) }
                .sorted { ($0.sortIndex ?? 0, $0.id.channelID.rawValue.rawValue) < ($1.sortIndex ?? 0, $1.id.channelID.rawValue.rawValue) }
            event.media = try await media(normalized.events.first?.images)
            var graph = EventRecordGraph(event: event)
            var contributors: [OME.ID<OME.Contributor>: Contributor] = [:]
            for value in sourceContributors.sorted(by: { $0.id.contributorID.rawValue.rawValue < $1.id.contributorID.rawValue.rawValue }) {
                let id = try identities.uri(collection: Contributor.lexiconID, event: event, key: value.id.contributorID.rawValue.rawValue)
                guard contributors[value.id.contributorID] == nil else { throw ValidationError("Duplicate source contributor") }
                let sourceLinks = SourceContributorLinks(value.links ?? [])
                guard preserveLinkText || sourceLinks.unresolved.isEmpty else {
                    throw ValidationError("Contributor \(value.name) has non-URL link text: \(sourceLinks.unresolved.joined(separator: "; ")). Use --preserve-link-text to include it in the description.")
                }
                var description = value.bio
                if !sourceLinks.unresolved.isEmpty {
                    description = ([value.bio].compactMap { $0 } + ["Source link text:\n" + sourceLinks.unresolved.joined(separator: "\n")]).joined(separator: "\n\n")
                    result.diagnostics.append("\(entry.directoryName)/\(value.name): preserved \(sourceLinks.unresolved.count) non-URL link values as description text")
                }
                result.diagnostics += sourceLinks.normalized.map { "\(entry.directoryName)/\(value.name): normalized link \($0)" }
                let record = try Contributor(id: id, event: event.id, name: value.name, createdAt: event.createdAt,
                    subject: value.did, description: description,
                    links: sourceLinks.links.isEmpty ? nil : sourceLinks.links,
                    media: try await media(value.images))
                try record.validateReferences()
                contributors[value.id.contributorID] = record
                graph.contributors.append(record)
            }
            var places: [OME.ID<OME.Stage>: EventPlace] = [:]
            for value in sourceStages {
                let id = try identities.uri(collection: EventPlace.lexiconID, event: event, key: value.id.stageID.rawValue.rawValue)
                guard places[value.id.stageID] == nil, let color = OME.Color(rawValue: value.color.rawValue) else {
                    throw ValidationError("Duplicate stage or invalid stage color")
                }
                let lineup = try value.lineup?.map { key in
                    guard let contributor = contributors[key] else { throw ValidationError("Stage \(value.name) references missing contributor \(key)") }
                    return contributor.id
                }
                let place = try EventPlace(id: id, event: event.id, name: value.name, createdAt: event.createdAt,
                    media: try await media(value.images), kind: .known(.stage(.init(color: color,
                        category: value.category?.rawValue, sortIndex: value.sortIndex,
                        shortLabel: value.iconShortCode, lineup: lineup))))
                places[value.id.stageID] = place
                graph.places.append(place)
            }
            // A source stage category defines an attendee-facing program; the source order defines lanes.
            var programs: [String: Program] = [:]
            for stage in sourceStages {
                let category = stage.category?.rawValue ?? ""
                if programs[category] == nil {
                    let id = try identities.uri(collection: Program.lexiconID, event: event, key: category)
                    let lanes = sourceStages.filter { ($0.category?.rawValue ?? "") == category }.compactMap { places[$0.id.stageID]?.id }
                    let program = try Program(id: id, event: event.id, title: category.isEmpty ? "Schedule" : category,
                        createdAt: event.createdAt, eventPlaces: lanes)
                    programs[category] = program
                    graph.programs.append(program)
                }
            }
            var schedules: [OME.ID<OME.Schedule>: Schedule] = [:]
            for value in sourceSchedules {
                let id = try identities.uri(collection: Schedule.lexiconID, event: event, key: value.id.scheduleID.rawValue.rawValue)
                let record = try Schedule(id: id, event: event.id, date: value.date, createdAt: event.createdAt, title: value.customTitle)
                schedules[value.id.scheduleID] = record
                graph.schedules.append(record)
            }
            for value in sourceItems.sorted(by: { $0.id.scheduleItemID.rawValue.rawValue < $1.id.scheduleItemID.rawValue.rawValue }) {
                guard let stage = sourceStages.first(where: { $0.id.stageID == value.stageID }),
                      let place = places[value.stageID], let program = programs[stage.category?.rawValue ?? ""],
                      let scheduleID = value.scheduleID, let schedule = schedules[scheduleID] else {
                    throw ValidationError("Program item \(value.title) has an unresolved stage or festival day")
                }
                var credits: [ProgramItem.Credit] = []
                for credit in sourceCredits.filter({ $0.id.scheduleItemID == value.id.scheduleItemID }).sorted(by: { $0.id.sortIndex < $1.id.sortIndex }) {
                    let contributor = credit.contributorID.flatMap { contributors[$0] }
                    if credit.contributorID != nil && contributor == nil { throw ValidationError("Unresolved program credit") }
                    guard let name = contributor?.name ?? credit.anonymousName ?? credit.contributorActor?.description else {
                        throw ValidationError("A program credit needs a display name")
                    }
                    credits.append(.init(name: name, contributor: contributor?.id,
                        billing: .known(credit.billing == .primary ? .primary : .supporting), role: credit.role?.rawValue))
                }
                let recordings = performanceDetails.first { $0.id == value.id }?.recordings ?? []
                let media: [Open<OME.Media>] = try recordings.map { recording in
                    if let reference = recording.record { return .known(.record(.init(uri: reference.uri))) }
                    guard let url = recording.url else { throw ValidationError("A recording has no URL or record") }
                    return .known(.external(.init(uri: url)))
                }
                let id = try identities.uri(collection: ProgramItem.lexiconID, event: event, key: value.id.scheduleItemID.rawValue.rawValue)
                graph.items.append(try ProgramItem(id: id, event: event.id, program: program.id, title: value.title,
                    createdAt: event.createdAt, description: value.description, schedule: schedule.id, eventPlace: place.id,
                    startsAt: datetime(value.startTime), endsAt: datetime(value.endTime),
                    credits: credits.isEmpty ? nil : credits, media: media.isEmpty ? nil : media))
            }
            var categories: [OME.ID<OME.Channel>: Social.Category] = [:]
            for value in channels {
                let id = try identities.uri(collection: Social.Category.lexiconID, event: event, key: value.id.channelID.rawValue.rawValue)
                var category = try Social.Category(id: id, event: event.id, name: value.name, createdAt: event.createdAt,
                    description: value.description.isEmpty ? nil : value.description,
                    defaultNotificationState: .known(value.defaultNotificationState == .subscribed ? .subscribed : .unsubscribed),
                    notificationsRequired: value.notificationsRequired)
                var media: [Open<OME.Media>] = []
                if let url = value.iconImageURL { media.append(.known(.image(.init(source: .known(.url(url)), role: .known(.icon(.init())))))) }
                if let url = value.headerImageURL { media.append(.known(.image(.init(source: .known(.url(url)), role: .known(.hero))))) }
                category.media = media.isEmpty ? nil : media
                categories[value.id.channelID] = category
            }
            var posts: [Social.Post] = []
            for value in normalized.communicationPosts.sorted(by: { ($0.id.channelID.rawValue.rawValue, $0.sortIndex) < ($1.id.channelID.rawValue.rawValue, $1.sortIndex) }) {
                guard var category = categories[value.id.channelID] else { throw ValidationError("Post \(value.title) has no category") }
                let key = String(decoding: try JSONEncoder().encode([value.id.channelID.rawValue.rawValue, value.id.postID.rawValue.rawValue]), as: UTF8.self)
                let id = try identities.uri(collection: Social.Post.lexiconID, event: event, key: key)
                var post = try Social.Post(id: id, title: value.title.isEmpty ? nil : value.title, text: value.contents,
                    event: event.id, category: category.id, createdAt: value.timestamp.map(datetime) ?? event.createdAt,
                    delivery: .known(Social.Post.Delivery(rawValue: value.delivery.rawValue)!))
                var images: [ATProto.Blob] = []
                if let header = value.headerImageURL { images.append(try await blob(for: header, postEmbed: true)) }
                for asset in value.images ?? [] {
                    let b: ATProto.Blob
                    switch asset.source { case let .blob(value): b = value; case let .url(url): b = try await blob(for: url, postEmbed: true) }
                    if !images.contains(b) { images.append(b) }
                }
                var originalURLs: [URL] = []
                if let header = value.headerImageURL, !header.isFileURL, compressedPostImages.contains(header) { originalURLs.append(header) }
                for asset in value.images ?? [] {
                    if case let .url(url) = asset.source, !url.isFileURL, compressedPostImages.contains(url), !originalURLs.contains(url) { originalURLs.append(url) }
                }
                for url in originalURLs { post.text += "\n\nOriginal image: \(url.absoluteString)" }
                guard images.allSatisfy({ ($0.size ?? .max) <= 2_000_000 }) else { throw PostImagePublicationError.tooLarge }
                guard images.count <= 4 else { throw ValidationError("Post \(value.title) exceeds the four-image embed limit") }
                if !images.isEmpty {
                    post.embed = .init(["$type": .string("app.bsky.embed.images"), "images": .array(try images.map {
                        .object(["alt": .string(""), "image": try Lexicon.JSONValue(encoding: $0)])
                    })])
                }
                if value.isPinned { category.pinnedPosts = (category.pinnedPosts ?? []) + [id]; categories[value.id.channelID] = category }
                posts.append(post)
            }
            graph.categories = channels.compactMap { categories[$0.id.channelID] }
            event.programs = graph.programs.isEmpty ? nil : graph.programs.map(\.id)
            event.schedules = graph.schedules.isEmpty ? nil : graph.schedules.map(\.id)
            event.categories = graph.categories.isEmpty ? nil : graph.categories.map(\.id)
            for draft in normalized.posters {
                let poster = try materialize(OME.Poster.self, draft)
                event.media = (event.media ?? []) + [.known(.image(try await image(poster.image, title: poster.title)))]
            }
            if let map = normalized.siteMaps.first {
                var styles: [Event.SiteMap.Style] = []
                for style in map.styles { styles.append(.init(id: style.id.rawValue.rawValue, title: style.title, image: try await image(style.image))) }
                event.siteMap = .init(title: map.title, styles: styles, defaultStyleID: map.defaultStyleID?.rawValue.rawValue)
            }
            graph.event = event
            try graph.validate()
            for place in graph.places {
                if case let .known(.stage(use)) = place.kind {
                    guard Set(use.lineup ?? []).isSubset(of: Set(graph.contributors.map(\.id))) else { throw ValidationError("Unresolved stage lineup") }
                }
            }
            for post in posts { try post.validateGraph(event: event, category: graph.categories.first { $0.id == post.category }) }
            // Dependencies are written before the Event advertises the complete graph.
            for record in graph.contributors { try result.append(id: record.id, payload: record.encodeLexicon(), images: imageData) }
            for record in graph.places { try result.append(id: record.id, payload: record.encodeLexicon(), images: imageData) }
            for record in graph.programs { try result.append(id: record.id, payload: record.encodeLexicon(), images: imageData) }
            for record in graph.schedules { try result.append(id: record.id, payload: record.encodeLexicon(), images: imageData) }
            for record in graph.items { try result.append(id: record.id, payload: record.encodeLexicon(), images: imageData) }
            for record in posts { try result.append(id: record.id, payload: record.encodeLexicon(), images: imageData) }
            for record in graph.categories { try result.append(id: record.id, payload: record.encodeLexicon(), images: imageData) }
            try result.append(id: event.id, payload: event.encodeLexicon(), images: imageData)
        }
        guard Set(result.records.map(\.id)).count == result.records.count else { throw ValidationError("Duplicate publication record identity") }
        return result
    }

}
