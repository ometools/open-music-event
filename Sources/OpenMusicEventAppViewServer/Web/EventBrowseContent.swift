import ATProto
import Elementary
import Foundation
import Hummingbird
import OpenMusicEventLexicon
import OpenMusicEventRouting
import OpenMusicEventWeb
import SQLiteData

struct EventBrowseSelection {
    var query: String
    var day: String
    var mode: String
    var sort: String
    init(query: String?) throws {
        let values = try EventViewerSelection(query: query).values
        self.query = (values["q"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        day = values["day"] ?? ""
        mode = values["mode"] ?? ""
        sort = values["sort"] ?? "soonest"
        guard ["", "inperson", "virtual", "hybrid"].contains(mode), ["soonest", "name"].contains(sort) else { throw HTTPError(.badRequest) }
        if !day.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let date = formatter.date(from: day), formatter.string(from: date) == day else { throw HTTPError(.badRequest) }
        }
    }
}

extension OpenMusicEventAppViewServer {
    static func browseResponse(query: String?, host: String, routeResolver: OpenMusicEventRouter,
                               store: OpenMusicEventAppViewStore?, now: Date = Date()) throws -> Response {
        guard let store else { return textResponse("Event browsing is temporarily unavailable.", status: .serviceUnavailable) }
        let selection = try EventBrowseSelection(query: query)
        let events = try store.database.read { try Event.all.fetchAll($0) }
        let sections = browseSections(events: events, selection: selection, host: host, routeResolver: routeResolver, now: now)
        let page = EventBrowseHTML(sections: sections, query: selection.query, day: selection.day, mode: selection.mode, sort: selection.sort)
        return Response(status: .ok, headers: [.contentType: "text/html; charset=utf-8", .cacheControl: "no-cache"],
            body: .init(byteBuffer: .init(string: page.render())))
    }

    static func browseSections(events: [Event], selection: EventBrowseSelection, host: String,
                               routeResolver: OpenMusicEventRouter, now: Date) -> [EventBrowseSection] {
        struct Entry {
            var row: EventBrowseRow
            var start: Date?
            var end: Date?
            var day: String?
            var mode: String
            var description: String
        }
        let entries = events.map { event -> Entry in
            let start = event.start?.date(in: event.timeZone)
            let end = event.end?.date(in: event.timeZone)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = event.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            let localDay = event.start?.calendarDay?.rawValue ?? event.timeZone.flatMap { _ in start.map(formatter.string) }
            let interval = DateIntervalFormatter()
            interval.timeZone = event.timeZone; interval.dateStyle = .medium; interval.timeStyle = .none
            let date = event.timeZone.flatMap { _ in start.map { interval.string(from: $0, to: end ?? $0) } } ?? localDay
            let mode: String
            switch event.mode {
            case .known(.inPerson): mode = "inperson"
            case .known(.virtual): mode = "virtual"
            case .known(.hybrid): mode = "hybrid"
            default: mode = ""
            }
            let url = openMusicEventEventPathRouter.path(for: event.id)
            let images = mediaImages(event.media)
            let image = images.first { $0.role == .known(.logo) } ?? images.first
            return Entry(row: .init(title: event.name, date: date, imageURL: image.flatMap { webImage($0, owner: event.id) }, url: url),
                start: start, end: end, day: localDay, mode: mode, description: event.description ?? "")
        }.filter { entry in
            (selection.day.isEmpty || entry.day == selection.day)
                && (selection.mode.isEmpty || entry.mode == selection.mode)
                && (selection.query.isEmpty || entry.row.title.localizedCaseInsensitiveContains(selection.query)
                    || entry.description.localizedCaseInsensitiveContains(selection.query))
        }.sorted { lhs, rhs in
            if selection.sort == "name" { return lhs.row.title.localizedStandardCompare(rhs.row.title) == .orderedAscending }
            if lhs.start != rhs.start { return (lhs.start ?? .distantFuture) < (rhs.start ?? .distantFuture) }
            return lhs.row.title.localizedStandardCompare(rhs.row.title) == .orderedAscending
        }
        guard !entries.isEmpty else { return [] }
        if !selection.day.isEmpty { return [.init(title: selection.day, events: entries.map(\.row))] }
        var groups: [EventBrowseSection] = [.init(title: "Happening Now", events: entries.filter {
            guard let start = $0.start, let end = $0.end else { return false }
            return start <= now && now <= end
        }.map(\.row))]
        let upcoming = entries.filter { ($0.start ?? .distantPast) > now }
        let undated = entries.filter { $0.start == nil }
        let past = entries.filter { $0.start != nil && ($0.end ?? $0.start!) < now }
        for (title, rows) in [("Upcoming", upcoming), ("More Events", undated), ("Past Events", past)] where !rows.isEmpty {
            groups.append(.init(title: title, events: rows.map(\.row)))
        }
        return groups
    }
}
