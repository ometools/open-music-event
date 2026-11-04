import ATProto
import Foundation

public extension OME.CalendarEvent {
    struct BrowseSummaries: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.calendar.browseEventSummaries")
        public typealias Input = Never
        public typealias Output = SummaryPage
        public init(parameters: Parameters) { self.parameters = parameters }

        public var parameters: Parameters

        public struct Parameters: Codable, Equatable, Sendable {
            public init(
                catalogs: [ATProto.NSID],
                query: String? = nil,
                north: Double? = nil,
                south: Double? = nil,
                east: Double? = nil,
                west: Double? = nil,
                cursor: String? = nil,
                limit: Int? = nil,
                dates: String? = nil,
                cell: String? = nil,
                publisherMode: String? = nil,
                publishers: [Int]? = nil
            ) {
                self.catalogs = catalogs
                self.query = query
                self.north = north
                self.south = south
                self.east = east
                self.west = west
                self.cursor = cursor
                self.limit = limit
                self.dates = dates
                self.cell = cell
                self.publisherMode = publisherMode
                self.publishers = publishers
            }

            public var catalogs: [ATProto.NSID]
            public var query: String? = nil
            public var north: Double? = nil
            public var south: Double? = nil
            public var east: Double? = nil
            public var west: Double? = nil
            public var cursor: String? = nil
            public var limit: Int? = nil
            public var dates: String? = nil
            public var cell: String? = nil
            public var publisherMode: String? = nil
            public var publishers: [Int]? = nil
        }
    }

    struct SummaryPage: Codable, Sendable {
        public init(
            events: [Summary],
            cursor: String? = nil,
            hasMore: Bool = false,
            evaluatedAt: Date
        ) {
            self.events = events
            self.cursor = cursor
            self.hasMore = hasMore
            self.evaluatedAt = evaluatedAt
        }

        public var events: [Summary]
        public var cursor: String?
        public var hasMore: Bool
        public var evaluatedAt: Date
    }

    struct Summary: Codable, Equatable, Identifiable, Sendable {
        public init(
            uri: String,
            catalog: String,
            name: String,
            startsAt: Date? = nil,
            endsAt: Date? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            markerMedia: OME.CalendarEvent.Media? = nil,
            timeZoneIdentifier: String? = nil,
            locationSummary: String? = nil,
            locality: String? = nil,
            region: String? = nil,
            country: String? = nil,
            publisherName: String? = nil,
            publisherAvatarURL: String? = nil,
            dateOnly: Bool = false,
            hasEventViewer: Bool = false
        ) {
            self.uri = uri
            self.catalog = catalog
            self.name = name
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.latitude = latitude
            self.longitude = longitude
            self.markerMedia = markerMedia
            self.timeZoneIdentifier = timeZoneIdentifier
            self.locationSummary = locationSummary
            self.locality = locality
            self.region = region
            self.country = country
            self.publisherName = publisherName
            self.publisherAvatarURL = publisherAvatarURL
            self.dateOnly = dateOnly
            self.hasEventViewer = hasEventViewer
        }

        public var id: String { uri }

        public var uri: String
        public var catalog: String
        public var name: String
        public var startsAt: Date?
        public var endsAt: Date?
        public var latitude: Double?
        public var longitude: Double?
        public var markerMedia: OME.CalendarEvent.Media?
        public var timeZoneIdentifier: String?
        public var locationSummary: String?
        public var locality: String?
        public var region: String?
        public var country: String?
        public var publisherName: String?
        public var publisherAvatarURL: String?
        public var dateOnly: Bool
        public var hasEventViewer: Bool
    }

}
