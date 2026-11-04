import ATProto
import ComposableCalendarEvents
import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventLexicon
import SQLiteData

/// The same anonymous discovery service used by the public web browser.
public struct EventBrowseClient: Sendable {
    public var defaults: @Sendable () async throws -> PublisherSelection
    public var browse: @Sendable (OME.CalendarEvent.BrowseSummaries.Parameters) async throws -> OME.CalendarEvent.SummaryPage
    public var event: @Sendable (ATProto.URI) async throws -> CalendarEvent

    public struct PublisherSelection: Codable, Equatable, Sendable {
        public var mode: String
        public var publishers: [Int]

        public init(mode: String, publishers: [Int]) {
            self.mode = mode
            self.publishers = publishers
        }
    }

    public static func appView(host: ATProto.PDSHost) -> Self {
        Self(
            defaults: {
                @Dependency(XRPC.Client.self) var xrpc
                return try await withDependencies {
                    $0.pdsHost = host
                    $0.jsonDecoder = Self.appViewDecoder
                } operation: {
                    try await xrpc.run(PublisherDefaultsQuery()).defaults
                }
            },
            browse: { parameters in
                @Dependency(XRPC.Client.self) var xrpc
                return try await withDependencies {
                    $0.pdsHost = host
                    $0.jsonDecoder = Self.appViewDecoder
                } operation: {
                    try await xrpc.run(OME.CalendarEvent.BrowseSummaries(parameters: parameters))
                }
            },
            event: { uri in
                @Dependency(XRPC.Client.self) var xrpc
                let event = try await withDependencies {
                    $0.pdsHost = host
                    $0.jsonDecoder = Self.appViewDecoder
                } operation: {
                    try await xrpc.run(OME.CalendarEvent.GetEvent(uri: uri))
                }
                guard event.uri == uri else {
                    throw ValidationError("The AppView returned a different event")
                }
                return event.browseDetail(appViewHost: host)
            }
        )
    }

    static var appViewDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func uiAutomation(database: any DatabaseWriter) -> Self {
        let fixtures = CalendarEventsClient.uiAutomation(database: database)
        return Self(
            defaults: { PublisherSelection(mode: "allExcept", publishers: []) },
            browse: { parameters in
                @Dependency(\.date.now) var now
                let page = try await fixtures.browse(.init(collection: EventCatalog.openMusicEvent.collection))
                let events = page.events.filter { event in
                    parameters.catalogs.contains(event.source.collection)
                        && (parameters.query?.isEmpty != false
                            || event.name.localizedCaseInsensitiveContains(parameters.query ?? ""))
                        && (parameters.dates == "all" || (event.endsAt ?? event.startsAt).map { $0 >= now } == true)
                }
                return .init(events: events.map { event in
                    .init(uri: event.uri.description, catalog: event.source.collection.rawValue,
                          name: event.name, startsAt: event.startsAt, endsAt: event.endsAt,
                          markerMedia: event.media.first.map { .init(url: $0.url, alt: $0.alt, role: $0.role) },
                          timeZoneIdentifier: event.timeZoneIdentifier,
                          locationSummary: event.locations.first?.summary, hasEventViewer: true)
                }, evaluatedAt: now)
            },
            event: fixtures.event
        )
    }
}

extension EventBrowseClient: DependencyKey {
    public static var liveValue: Self { .appView(host: "openmusicevent.app") }
    public static var testValue: Self {
        Self(
            defaults: { throw ValidationError("Browse defaults are not configured") },
            browse: { _ in throw ValidationError("Event browsing is not configured") },
            event: { _ in throw ValidationError("Browse detail loading is not configured") }
        )
    }
}

public extension DependencyValues {
    var eventBrowse: EventBrowseClient {
        get { self[EventBrowseClient.self] }
        set { self[EventBrowseClient.self] = newValue }
    }
}

// Only the defaults are needed here; the web's publisher-picker page is decoded independently.
struct PublisherDefaultsQuery: XRPC.Query, Sendable {
    static let nsid = ATProto.NSID("app.openmusicevent.calendar.getPublishers")
    typealias Input = Never
    struct Parameters: Codable, Sendable {}
    struct Output: Codable, Sendable { var defaults: EventBrowseClient.PublisherSelection }
    var parameters = Parameters()
}

extension OME.CalendarEvent.Summary {
    func browsePreview() throws -> CalendarEvent {
        guard let uri = ATProto.URI(uri),
              let collection = uri.collection,
              collection.rawValue == catalog,
              case let .did(publisherID) = uri.authority else {
            throw ValidationError("The AppView returned an invalid event address")
        }
        return CalendarEvent(
            uri: uri, name: name, startsAt: startsAt, endsAt: endsAt,
            locations: locationSummary.map { [.init(name: $0)] } ?? [],
            media: markerMedia.map { [.init(url: $0.url, alt: $0.alt, role: $0.role)] } ?? [],
            organizer: .init(id: publisherID, displayName: publisherName,
                             avatarURL: publisherAvatarURL.flatMap(URL.init(string:))),
            source: .init(collection: collection), timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

extension OME.CalendarEvent {
    func browseDetail(appViewHost: ATProto.PDSHost) -> CalendarEvent {
        let status: CalendarEvent.Status? = switch status {
        case .cancelled: .cancelled
        case .planned: .planned
        case .postponed: .postponed
        case .rescheduled: .rescheduled
        case .scheduled: .scheduled
        case let .unknown(value): .unknown(value)
        case nil: nil
        }
        let mode: CalendarEvent.Mode? = switch mode {
        case .hybrid: .hybrid
        case .inPerson: .inPerson
        case .virtual: .virtual
        case let .unknown(value): .unknown(value)
        case nil: nil
        }
        return CalendarEvent(
            uri: uri, cid: cid, name: name, description: description,
            startsAt: startsAt, endsAt: endsAt, createdAt: createdAt, status: status, mode: mode,
            locations: locations.map { .init(name: $0.name, street: $0.street, locality: $0.locality,
                region: $0.region, postalCode: $0.postalCode, country: $0.country,
                latitude: $0.latitude, longitude: $0.longitude, source: $0.source) },
            links: links.map { .init(name: $0.name, uri: $0.uri, source: $0.source) },
            media: media.map { .init(url: $0.url, alt: $0.alt, role: $0.role) },
            organizer: .init(id: organizer.id, handle: organizer.handle, displayName: organizer.displayName,
                             description: organizer.description, avatarURL: organizer.avatarURL),
            attendance: .init(going: attendance.going, interested: attendance.interested, notGoing: attendance.notGoing),
            source: .init(collection: source.collection, appViewHost: appViewHost),
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}
