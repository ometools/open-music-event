import ATProto
import ATProtoTypes
import Foundation
import GRDB
import Hummingbird
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventWeb
import SQLiteData

struct EventViewerContent {
    var graph: EventRecordGraph
    var posts: [Social.Post]
}

extension OpenMusicEventAppViewStore {
    func eventViewerContent(id: Event.ID) throws -> EventViewerContent? {
        try database.read { db in
            guard let graph = try EventRecordGraph.fetch(eventID: id, from: db) else { return nil }
            // Ingestion validates each record's payload. Reads check only graph relationships:
            // re-encoding and schema-validating every biography on every HTTP request is unnecessary.
            let programs = Dictionary(uniqueKeysWithValues: graph.programs.map { ($0.id, $0) })
            let scheduleIDs = Set(graph.schedules.map(\.id))
            let placeIDs = Set(graph.places.map(\.id))
            let categoryIDs = Set(graph.categories.map(\.id))
            guard Set(programs.keys) == Set(graph.event.programs ?? []),
                  scheduleIDs == Set(graph.event.schedules ?? []),
                  categoryIDs == Set(graph.event.categories ?? []),
                  graph.programs.allSatisfy({ Set($0.eventPlaces).isSubset(of: placeIDs) }),
                  graph.items.allSatisfy({ item in
                      guard let program = programs[item.program] else { return false }
                      return (item.schedule.map { scheduleIDs.contains($0) } ?? true)
                          && (item.eventPlace.map { placeIDs.contains($0) && program.eventPlaces.contains($0) } ?? true)
                  }) else { throw ValidationError("Referenced event content is not indexed yet") }
            let contributorIDs = Set(graph.contributors.map(\.id))
            guard graph.items.allSatisfy({ ($0.credits ?? []).allSatisfy { $0.contributor == nil || contributorIDs.contains($0.contributor!) } }) else {
                throw ValidationError("Referenced contributors are not indexed yet")
            }
            let posts = try Social.Post.where { $0.event.eq(id) }.fetchAll(db)
                .filter { $0.id.authority == id.authority }
            guard posts.allSatisfy({ $0.category.map { categoryIDs.contains($0) } ?? true }) else {
                throw ValidationError("Referenced post categories are not indexed yet")
            }
            let postIDs = Set(posts.map(\.id))
            guard graph.categories.allSatisfy({ ($0.pinnedPosts ?? []).allSatisfy { postIDs.contains($0) } }) else {
                throw ValidationError("Pinned posts are not indexed yet")
            }
            return EventViewerContent(graph: graph, posts: posts)
        }
    }
}

struct EventViewerSelection {
    var feature: EventViewerFeature = .schedule
    var kind: EventViewerScheduleKind = .singleStageAtOnce
    var values: [String: String]

    init(query: String?) throws {
        let pairs = URLComponents(string: "?" + (query ?? ""))?.queryItems ?? []
        var values: [String: String] = [:]
        for pair in pairs {
            guard values[pair.name] == nil else { throw HTTPError(.badRequest) }
            values[pair.name] = pair.value ?? ""
        }
        self.values = values
        if let value = values["feature"] {
            guard let feature = EventViewerFeature.allCases.first(where: { $0.webValue == value }),
                  ![.settings, .workspace, .notifications].contains(feature) else { throw HTTPError(.notFound) }
            self.feature = feature
        }
        if let value = values["schedule-kind"] {
            guard let kind = EventViewerScheduleKind.allCases.first(where: { $0.webValue == value }) else { throw HTTPError(.notFound) }
            self.kind = kind
        }
    }
}

extension EventViewerContent {
    func presentation(selection: EventViewerSelection) throws -> EventModel {
        let event = graph.event
        let programs = (event.programs ?? []).compactMap { id in graph.programs.first { $0.id == id } }
        let days = graph.schedules.sorted { $0.date.description < $1.date.description }
        func selected(_ key: String, in ids: [String]) throws -> String? {
            guard let value = selection.values[key] else { return ids.first }
            guard ids.contains(value) else { throw HTTPError(.notFound) }
            return value
        }
        let programID = try selected("program", in: programs.map { $0.id.description })
        let dayID = try selected("day", in: days.map { $0.id.description })
        let program = programs.first { $0.id.description == programID }
        let places = (program?.eventPlaces ?? []).compactMap { id in graph.places.first { $0.id == id } }
        _ = try selected("stage", in: places.map { $0.id.description })
        if let contributor = selection.values["contributor"], !graph.contributors.contains(where: { $0.id.description == contributor }) { throw HTTPError(.notFound) }
        if let category = selection.values["category"], !graph.categories.contains(where: { $0.id.description == category }) { throw HTTPError(.notFound) }
        if let post = selection.values["post"], !posts.contains(where: { $0.id.description == post && (selection.values["category"] == nil || $0.category?.description == selection.values["category"]) }) { throw HTTPError(.notFound) }
        let maps: [(id: String, title: String, image: OME.Image)]
        if let siteMap = event.siteMap {
            maps = siteMap.styles.map { ($0.id, $0.title, $0.image) }
        } else {
            maps = mediaImages(event.media).enumerated().filter { $0.element.role == .known(.siteMap) }
                .map { ("media-\($0.offset)", $0.element.title ?? "Site map", $0.element) }
        }
        if let style = selection.values["map"], !maps.contains(where: { $0.id == style }) { throw HTTPError(.notFound) }


        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = event.timeZone
        formatter.dateFormat = "h:mm a"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = formatter.locale
        dateFormatter.timeZone = event.timeZone
        dateFormatter.dateFormat = "EEEE, MMM d, yyyy"
        func scheduleURL(_ item: ProgramItem, stage: String?) -> String {
            webQuery(["feature": "schedule", "program": item.program.description,
                      "day": item.schedule?.description, "stage": stage]) + "#schedule"
        }
        let timestamps = ISO8601DateFormatter()
        timestamps.formatOptions = [.withInternetDateTime]
        let fractionalTimestamps = ISO8601DateFormatter()
        fractionalTimestamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: ATProto.DateTime?) -> Date? {
            value.flatMap { timestamps.date(from: $0.rawValue) ?? fractionalTimestamps.date(from: $0.rawValue) }
        }
        // Parse each instant once; sorting must not construct ISO formatters for every comparison.
        let itemDates = Dictionary(uniqueKeysWithValues: graph.items.map {
            ($0.id, (start: date($0.startsAt), end: date($0.endsAt)))
        })
        let performances = graph.items.sorted {
            if itemDates[$0.id]?.start != itemDates[$1.id]?.start { return (itemDates[$0.id]?.start ?? .distantFuture) < (itemDates[$1.id]?.start ?? .distantFuture) }
            return $0.id.description < $1.id.description
        }.map { item -> Performance in
            let place = graph.places.first { $0.id == item.eventPlace }
            let day = days.first { $0.id == item.schedule }
            let midnight = day?.date.atStartOfDay(in: event.timeZone)
            var value = Performance(id: item.id.description, title: item.title, stage: place?.name ?? "Unassigned",
                time: itemDates[item.id]?.start.map(formatter.string) ?? "Time not announced",
                endTime: itemDates[item.id]?.end.map(formatter.string),
                startMinute: midnight.flatMap { zero in itemDates[item.id]?.start.map { Int($0.timeIntervalSince(zero) / 60) } },
                endMinute: midnight.flatMap { zero in itemDates[item.id]?.end.map { Int($0.timeIntervalSince(zero) / 60) } },
                stageColor: "#78e0d6", stageLogoURL: place.flatMap { mediaImages($0.media).first }.flatMap { webImage($0, owner: event.id) })
            value.stageID = place?.id.description ?? ""
            value.scheduleURL = scheduleURL(item, stage: place?.id.description)
            return value
        }
        var model = EventModel(name: event.name, location: event.locations?.first?.name ?? "Location not announced",
            heroImageURL: mediaImages(event.media).first.flatMap { webImage($0, owner: event.id) },
            dateLine: event.start?.date(in: event.timeZone).map(dateFormatter.string),
            scheduleLabel: program?.title ?? "Schedule", timeZoneIdentifier: event.timeZone.identifier,
            summary: event.description, performances: performances)
        model.scheduleQuery = String(webQuery(["feature": "schedule", "program": programID, "day": dayID, "stage": selection.values["stage"]]).dropFirst())
        let selectedItemIDs = Set(graph.items.filter { $0.program.description == programID && $0.schedule?.description == dayID }.map { $0.id.description })
        model.schedulePerformances = places.flatMap { place in performances.filter { $0.stageID == place.id.description && selectedItemIDs.contains($0.id) && $0.startMinute != nil } }
        model.stagePerformances = graph.places.sorted { $0.name < $1.name }.map { place in
            var row = Performance(id: place.id.description, title: place.name, stage: place.name, time: "", stageLogoURL: mediaImages(place.media).first.flatMap { webImage($0, owner: place.id) })
            row.stageID = place.id.description
            let placeProgram = programs.first { $0.eventPlaces.contains(place.id) }
            let firstItem = graph.items.filter { $0.eventPlace == place.id && $0.schedule != nil }.sorted { (itemDates[$0.id]?.start ?? .distantFuture) < (itemDates[$1.id]?.start ?? .distantFuture) }.first
            row.scheduleURL = webQuery(["feature": "schedule", "program": placeProgram?.id.description, "day": firstItem?.schedule?.description, "stage": place.id.description])
            return row
        }
        model.scheduleStages = places.compactMap { place in model.stagePerformances.first { $0.stageID == place.id.description } }
        for index in model.scheduleStages.indices {
            model.scheduleStages[index].scheduleURL = webQuery(["program": programID, "day": dayID, "stage": model.scheduleStages[index].stageID])
        }
        model.programChoices = programs.map { .init(title: $0.title, url: webQuery(["program": $0.id.description, "day": dayID, "schedule-kind": selection.kind.webValue]), selected: $0.id.description == programID) }
        model.dayChoices = days.map { .init(title: $0.title ?? dateFormatter.string(from: $0.date.atStartOfDay(in: event.timeZone)), url: webQuery(["program": programID, "day": $0.id.description, "schedule-kind": selection.kind.webValue]), selected: $0.id.description == dayID) }
        model.contributors = graph.contributors.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { contributor in
            var value = OpenMusicEventWeb.Contributor(id: contributor.id.description, name: contributor.name,
                role: (contributor.roles ?? []).compactMap { if case .known(let role) = $0 { return role.rawValue }; return nil }.joined(separator: ", "),
                bio: contributor.description ?? "", avatarURL: mediaImages(contributor.media).first.flatMap { webImage($0, owner: contributor.id) }, accentColor: "#78e0d6",
                performanceIDs: graph.items.filter { ($0.credits ?? []).contains { $0.contributor == contributor.id } }.map { $0.id.description })
            value.links = webLinks(contributor.links)
            return value
        }
        model.contacts = webLinks(event.links)
        model.locations = (event.locations ?? []).enumerated().map { index, location in
            var address = ""; var latitude: Double?; var longitude: Double?
            for locator in location.locators ?? [] {
                switch locator {
                case .known(.address(let value)):
                    address = [value.street, value.locality, value.region, value.postalCode, value.country].compactMap { $0 }.joined(separator: ", ")
                case .known(.geo(let value)): latitude = Double(value.latitude); longitude = Double(value.longitude)
                default: break
                }
            }
            return EventLocation(id: String(index), name: location.name, address: address, detail: location.description, latitude: latitude, longitude: longitude)
        }
        let styleID = selection.values["map"] ?? event.siteMap?.defaultStyleID ?? maps.first?.id
        model.siteMapURL = maps.first { $0.id == styleID }.flatMap { webImage($0.image, owner: event.id) }
        model.mapChoices = maps.map { .init(title: $0.title, url: webQuery(["feature": "site-map", "map": $0.id]), selected: $0.id == styleID) }
        model.posters = mediaImages(event.media).filter { $0.role == .known(.poster) }.enumerated().map { index, image in
            EventPoster(id: String(index), title: image.title ?? image.alt?.rawValue ?? "Poster", imageURL: webImage(image, owner: event.id), accentColor: "#78e0d6")
        }
        let categories = (event.categories ?? []).compactMap { id in graph.categories.first { $0.id == id } }
        model.categoryChoices = [.init(title: "All posts", url: "?feature=communications", selected: selection.values["category"] == nil)] + categories.map {
            .init(title: $0.name, url: webQuery(["feature": "communications", "category": $0.id.description]), selected: $0.id.description == selection.values["category"])
        }
        let pinned = categories.flatMap { $0.pinnedPosts ?? [] }
        let filteredPosts = posts.filter { (selection.values["category"] == nil || $0.category?.description == selection.values["category"]) && (selection.values["post"] == nil || $0.id.description == selection.values["post"]) }
        model.posts = try filteredPosts.sorted {
            let left = pinned.firstIndex(of: $0.id); let right = pinned.firstIndex(of: $1.id)
            if left != right { return (left ?? Int.max) < (right ?? Int.max) }
            if $0.createdAt != $1.createdAt { return $0.createdAt.description > $1.createdAt.description }
            return $0.id.description < $1.id.description
        }.map { post in
            var images: [EventPoster] = []
            if case let .array(entries) = post.embed?.object["images"] {
                for (index, entry) in entries.enumerated() {
                    if let blobValue = entry.object?["image"] {
                        let blob = try blobValue.decoded(as: ATProto.Blob.self)
                        let image = OME.Image(source: .known(.blob(blob)))
                        images.append(EventPoster(id: String(index), title: entry.object?["alt"]?.string ?? "", imageURL: webImage(image, owner: post.id), accentColor: "#78e0d6"))
                    }
                }
            }
            return ViewerPost(id: post.id.description, title: post.title ?? "Update", text: webText(post), images: images,
                date: webDate(post.createdAt).map(dateFormatter.string) ?? post.createdAt.rawValue, pinned: pinned.contains(post.id),
                url: webQuery(["feature": "communications", "category": post.category?.description, "post": post.id.description]))
        }
        return model
    }
}

func webQuery(_ values: [String: String?]) -> String {
    var components = URLComponents()
    components.queryItems = values.keys.sorted().compactMap { key in values[key]!.map { URLQueryItem(name: key, value: $0) } }
    return components.string ?? ""
}
func safeWebURL(_ url: URL) -> String? {
    ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") ? url.absoluteString : nil
}
func mediaImages(_ media: [Open<OME.Media>]?) -> [OME.Image] {
    (media ?? []).compactMap { if case .known(.image(let image)) = $0 { return image }; return nil }
}
func webImage(_ image: OME.Image, owner: ATProto.URI) -> String? {
    switch image.source {
    case .known(.url(let url)): return ["https", "http"].contains(url.scheme ?? "") ? url.absoluteString : nil
    case .known(.blob(let blob)): return "/event-media" + webQuery(["record": owner.description, "cid": blob.ref.rawValue])
    default: return nil
    }
}
func webLinks(_ links: [OME.Link]?) -> [EventContact] {
    (links ?? []).compactMap { link in
        guard let url = safeWebURL(link.url) else { return nil }
        return EventContact(id: url, label: link.title ?? link.url.host ?? url, value: url, detail: link.description, href: url)
    }
}
func webText(_ post: Social.Post) -> [ViewerText] {
    let bytes = Array(post.text.utf8)
    var runs: [ViewerText] = []; var cursor = 0
    let facets = (post.facets ?? []).sorted { ($0.object["index"]?.object?["byteStart"]?.integer ?? 0) < ($1.object["index"]?.object?["byteStart"]?.integer ?? 0) }
    for facet in facets {
        guard let startValue = facet.object["index"]?.object?["byteStart"]?.integer,
              let endValue = facet.object["index"]?.object?["byteEnd"]?.integer,
              let start = Int(exactly: startValue), let end = Int(exactly: endValue),
              start >= cursor, end > start, end <= bytes.count,
              let text = String(bytes: bytes[start..<end], encoding: .utf8),
              case let .array(features) = facet.object["features"],
              let link = features.first(where: { $0.object?["$type"]?.string == "app.bsky.richtext.facet#link" })?.object?["uri"]?.string,
              let url = URL(string: link).flatMap(safeWebURL),
              let prefix = String(bytes: bytes[cursor..<start], encoding: .utf8) else { continue }
        runs.append(ViewerText(text: prefix)); runs.append(ViewerText(text: text, url: url)); cursor = end
    }
    runs.append(ViewerText(text: String(decoding: bytes[cursor...], as: UTF8.self)))
    return runs
}

func webDate(_ value: ATProto.DateTime) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value.rawValue) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value.rawValue)
}
